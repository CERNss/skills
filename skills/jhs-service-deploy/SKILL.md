---
name: jhs-service-deploy
description: 集换社（jihuanshe/tongdiao）gitops 服务新增 / 环境晋级 / 老配置迁移标准流程（testing→staging、testing→prod、staging→prod、全新服务首上、SealedSecret+envsubst→nacos+vault 迁移）。覆盖：同族模板选择、Nacos 配置起草+发布+回读验证、vault 引用清单二次确认、gitops envs 脚手架、跨仓前置清单。触发词：上 prod / 上 staging / 服务新增 / 环境晋级 / rollout / 拉起新环境 / 迁移 nacos / 老配置下掉。
---

# jhs 服务新增 / 环境晋级

适用：`cern-gitops` 仓（apps/<app>/envs/<env> + appsets 自动发现）+ 国内 Nacos（jhs-testing / jhs-staging / jhs-prod，同一 CN 集群）。
Tokyo 系环境（*-tokyo，aws-ap-tokyo 集群）流程同构，infra/惯例差异见 **references/jp-infra-catalog.md**
（东京 Nacos 域名口、JP vault 条目域无 -tokyo 后缀、镜像仓 ap-southeast-1、`<app>.apps.tcgcard.jp` 等）。

## 0. 核心原则（先读）

1. **模板优先级**：**结构形态一律参照 `apps/tcg-gateway`（标准样板）**——
   `base/{deployment,service,configmap,kustomization}` + `envs/<env>/{kustomization, base/<env>特有资源, overlays/四件套}`；
   base 里的 configmap 是**空壳回退占位**（`<app>-config`，无 data、不挂载、不引用）：原生 nacos 模式的
   新 app 也一律携带，给回退文件模式留口子（回退时 env 层 configMapGenerator replace + volume patch，
   不必动 base）。补占位属幂等变更：渲染 diff 只允许新增该空资源，Deployment/Service 零变化；
   overlays 固定 `deployment(只放 ENV+TZ)/replicas/settings/version`（+limits 按需），env 特有资源
   （ingress/secret/nodeport）放 `envs/<env>/base/` 走 resources 而**不是 patch**。
   配置内容则按：同族服务同目标环境 > 同族其他环境 > 同形态近亲（Go 服务 CN prod 参照 tcg-identity / tcg-trade）
   > **都没有 ⇒ 停下来主动问用户**（要配置来源 / 代码仓库 / 上游先例），不要自己编。
   被迁移的老 app 本身不当结构样板（反例：老 tcgwiki-*），只当值参照。
2. **各环境用各自的 vault 条目**：`infra/jhs-<env>/*` 与 `kubernetes/jhs-<env>/*` 跟着目标环境走，不跨环境借用。确需沿用其他环境资源时（先例：identity prod 沿用 testing PG），做法是在目标环境域镜像一个条目（如 `infra/jhs-prod/postgres-testing-write`），并且必须是用户明示的决策。
3. **Izumo SecretResolver fail-closed**：配置里出现的每个 `${vault:...}` 都必须是该环境 token 可读、已 provision 的路径，缺一个 ⇒ pod 启动即崩（不是优雅降级）。服务不消费的段一律留空 `""`，不放占位 vault 引用（先例：match 面 tcg-base-db.dsn 留空）。
   - **`enabled: false` 不豁免**：resolver 遍历解析后的**配置值**，不看功能开关——关掉的段里写 vault 引用照样解析。注释里的 `${vault:...}` 不参与解析（YAML parse 即丢弃），但也别写，防实现改文本替换时埋雷。
   - **迁移/晋级时别凭空加段**：目标是「与现网等价」，源配置没有的功能段不要因为别的环境有就搬。要加必须单独说明并让用户拍板——每加一段都可能引入新 vault 依赖或对生产的真实写操作。
   - **等价包括权限面与端点**：凭据等价看三要素——账号、端点、权限级别，逐项对齐老配置。
     多面服务常见「读面只读账号、写路径在别的面」，只读就配只读条目，别顺手换共享写条目「省事」；
     读写端点分离（只读集群端点 / 代理写入口 / 同实例多私网端点）时账号↔端点必须配套，不混搭。
   - **区域是独立信息域**：每个区域（CN / JP / …）有独立的 Nacos 实例、Vault 实例（域名可同构、内容独立）、
     老配置基线与共享 secret 声明者。晋级/迁移一律以**目标区域本地**的老配置和已验证条目为参照：
     段落集合与本区老配置比对（同一服务跨区不同构是常态），A 区拍板过的凭据/复用决策到 B 区要重新问。
4. **vault 清单二次确认**：发布任何配置前，把「复用的已验证条目」和「缺失待 provision 条目」分两张表列给用户确认。已验证 = 目标环境有正在运行的服务在解析该路径。
5. **prod 首发姿势**：占位 `prod/<app>:v*` 镜像 tag + `replicas=0`，前置齐了逐个拉起（tcg-trade 先例）；真实资金/库存类外呼（建单、扣款、combine-make）首发留占位不启用，联调后再开。
6. **staging 定位**（CN）：生产数据只读验证环境——vault 用 `vault-prod-ro-secret`、DB 用 `infra/jhs-prod/*-read`、写操作接受降级、绝不接真实建单。
7. **密码不落盘**：Nacos 控制台 jhs-gitops 密码每次找用户要；Vault 明文值由用户 provision，我们只写路径。
8. **配置来源要验证**：不是所有现网配置都能当惯例参考（反例：jhs-staging `tcg-base.yaml` 是从 jhs-dev 原样拷的）。以「有服务正在健康运行」为准。

## 1. Recon（改任何东西之前）

```
# gitops 侧
ls apps/<app>/envs/                          # 同族现有环境
cat apps/<近亲>/envs/<目标env>/kustomization.yaml  # 目标环境形态（secret 引用/依赖注释都在这）
kustomize/appsets: appsets/<env>-appset.yaml  # 确认 envs/<env> 会被自动发现、部署到哪个 ns
# Nacos 侧（API 用法见 references/cn-infra-catalog.md）
列目标 ns 配置 → 拉源环境配置 + 目标环境近亲配置（vault 路径参照）
```

环境速查、共享 secret、vault/host 对照 → **references/cn-infra-catalog.md**（各环境已知 infra 信息落盘，优先查它，别重新扫）。

## 2. gitops envs 脚手架（对齐 tcg-gateway 标准）

`envs/<env>/kustomization.yaml + overlays/{settings,deployment,version,replicas}.yaml`（限资源的面 + `limits.yaml` 按需；
env 特有资源如 ingress/nodeport/secret 放 `envs/<env>/base/*.yaml` 走 resources，不做 patch）：

- **base 归 base**：服务固有形态（容器端口、svc 端口、探针）写在 `apps/<app>/base/`，env 层不 patch 相同内容。
  resources 限额二分（判据：**换个环境这个数字还成立吗**）：服务属性（如 CPU 密集型解码）→ base/deployment，
  先例 tcg-base-worker；环境属性（数值由该环境数据量/流量决定）→ `overlays/limits.yaml`，只在需要的环境放，
  不塞 deployment/settings（容量调整是高频运维动作，独立文件 diff 可读、可横向盘点）。
  requests 别照抄老配置的极小值：与 limits 超卖比悬殊会挤压同节点邻居，拉起后按实际水位回调。
  改已有 app 的 base 时，先 `kubectl kustomize` 存各 env 渲染基线，改完 diff 必须逐字节零变化
  （幂等重构才不惊动现网 ArgoCD）。
- **kustomization**：resources `../../base`（+env 特有 base 资源）；components 按环境（testing=devnode、staging=stagingnode、prod=不挂）；顶部注释写清依赖（共享 secret 由谁声明、Nacos 配置要先发布、vault 缺失条目）。共享 secret **只按名引用、绝不重复声明**（两个 ArgoCD app 争同一资源）。
- **settings.yaml**：OTEL（**必带 `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`**——新式 Izumo/OTel SDK 按标准 env 选协议，缺它默认 http/protobuf 打 collector 的 gRPC 4317 → 持续刷 `malformed HTTP response "\x00\x00\x06\x04..."`（HTTP/2 帧）；`deployment.environment=<env>`, `cloud.region=cn`）+ `CONFIG_SOURCE=nacos` + Nacos 连接（ns/账号/密码 secret 按环境）+ 面专属 `CONFIG_NACOS_DATA_ID` + `VAULT_ADDR/VAULT_TOKEN`（token secret 按环境）。
- **deployment.yaml**：**只放** `ENV=<env>` + `TZ=Asia/Shanghai`（gateway 同款；端口/探针等归 base）。
- **settings 里的 env 注入要有消费者**：每个注入都对应配置里实际启用的功能段；段删了注入跟着删，别留死代码。
- **version.yaml**：testing/staging 用 `dev/<app>:<日期tag>`；prod 用 `prod/<app>:v*`（没有 v* release 就占位 + 注释说明）。
- **replicas.yaml**：prod 首发 0；testing/staging 通常 1。
- 全部写完跑 `kubectl kustomize apps/<app>/envs/<env>` 验证。

分支：从 `upstream/main` 切 `cern/<app>-<目的>`，push origin，PR 到 upstream（tongdiao/gitops）。别把无关 untracked 文件带进 commit。

## 3. Nacos 配置起草 + 发布

1. 以「模板优先级」选底稿，逐段做环境替换：
   - vault 路径 → 目标环境域；DB host → 目标环境实例（见 catalog）；
   - rpc-client / 下游 svc 地址 → `<svc>.jhs-<env>:<port>`；
   - 对外 URL → 环境域名（testing `*.testing.tongdiaotech.com` / prod 网关 `tcg-gateway.apps.tongdiaotech.com`）；
   - `debug: false`（prod）；kafka 等目标环境没有的基础设施 → 整段门控关闭而不是留错地址。
2. **停：输出 vault 两张表（复用/缺失）+ 非 vault 前置清单，等用户确认。**
3. 确认后发布（dataId/group 惯例：`tcg-<svc>[-<face>]-config.yaml` @ 业务域 group），发布完**逐字节回读比对**（下载回来 `cmp` 原稿）。
   老配置迁移场景再加一道：**顶层段落集合比对**（yaml.safe_load 新旧两份，set(keys) 必须相等），
   多出来的段就是凭空加的依赖。
4. 有待定项（如 PG 路径未建）：配置里留醒目 `TODO(待用户提供)` 注释占位，replicas=0 兜底，路径落地后改稿重发。

## 4. 收尾（必做）

- 给用户「拉起前置清单」：镜像 release、vault provision、DB 迁移/种子数据、跨仓 CI（如 tcg-base cosmo workflow 环境列表）、gateway 路由注册（放量开关）。
- 更新 memory（rollout 进展 + 待办），有新踩的坑回写本 skill / catalog。
- catalog 过期迹象（新实例、新 vault 域）→ 用 references/cn-infra-catalog.md 底部的重扫脚本刷新。

## 5. 晋级路径差异

| 路径 | 底稿 | 要点 |
|---|---|---|
| testing→staging | testing 配置 | 切 prod 只读凭据（`vault-prod-ro-secret` + `infra/jhs-prod/*-read`）；写路径降级；真实外呼禁用 |
| staging→prod | staging（已验证 prod host）+ testing（完整段落） | read→write 账号；补 staging 刻意留空的段（signing-key 等，prod 新随机值）；真实外呼默认仍占位 |
| testing→prod | testing 配置 + 目标环境近亲 prod 配置（vault 参照） | 全量环境替换；缺失条目最多，重点跑第 3.2 步确认 |
| 全新服务首上 | 同族 > 近亲 > **问用户** | 问：代码仓、配置模板/示例、消费哪些 DB/中间件、对外暴露方式 |
| 老配置迁移（SealedSecret+envsubst → nacos+vault） | 老 config.yaml 只当值参照，契约以代码仓 config.tmpl.yaml 为准 | **先查二进制是否支持 CONFIG_SOURCE=nacos**（多半要先改代码+发版）；SealedSecret 值不可回读，DSN host/库名找用户要；详细流程 → **references/legacy-to-nacos-migration.md** |

## 6. 影子部署 → 切流（规范化改名 / 平行迁移通用姿势）

1. **影子期**：新 app 全量脚手架 + Nacos 配置就位，镜像用**老部署现网同款 tag**（保证同二进制，且需含
   CONFIG_SOURCE 链路；老现网 tag 太旧不含时，用含该链路的最近 v*，并在 version.yaml 注释说明差异）；
   replicas=0 合入，前置齐后拉起，只验证 nacos+vault 启动链路（看 SecretResolver 日志），不接流量。
2. **域名**：新 app 只带**本 app 专属标准域名** ingress（`<app>.apps.<区域根域>` + 区域共享 tls，path /）。
   老域名的 ingress 留在老 app，切流阶段再迁；不要做「同 host+path 双 ingress 并存等接管」的方案——
   行为依赖 controller 的 oldest-wins 细节，reviewer 也难审。
3. **切流清单**（每项都是独立开关，逐个执行可回退）：老 app replicas 缩 0；老域名 ingress 迁移或
   老 svc selector shim 到新 pod；消费方配置里的老 svc 地址逐个迁到 `<新app>-svc`（消费方清单事先枚举：
   gateway 路由、其他服务的 rpc-client 地址、NodePort、联邦子图 routing_url 等）；确认后老 env 目录下线。
4. **收尾**：切流完成前老 app 不删；期间双份资源并存是预期状态，kustomization 头注释写清「老 app 继续服务，
   本 app 影子」避免误解。
