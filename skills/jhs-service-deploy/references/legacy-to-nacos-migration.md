# 老配置（SealedSecret + flux envsubst）→ nacos+vault 迁移

首例：tcg-infra-event-hub（2026-07-16）。适用于仍是「gitops 里 config.yaml + configMapGenerator
+ SealedSecret 环境变量 + init-container `flux envsubst` 渲染挂载」老模式的服务，
迁移到 CONFIG_SOURCE=nacos + `${vault:...}` 标准（参照架构 tcg-base-*）。

## 老模式识别特征（recon 时确认齐全）

- `envs/<env>/kustomization.yaml` 有 `configMapGenerator:（behavior: replace, files: config.yaml）`
- `envs/<env>/base/secrets.yaml` 是 `kind: SealedSecret`（DB 账密等，密文不可回读）
- `overlays/settings.yaml` 有 `initContainers: init-config`（flux-cli envsubst）+ configdir volume
- 服务容器挂 `/app/configs/config.yaml`（subPath）

## 迁移前三个硬前置（缺一不可，先查再动手）

1. **二进制要支持 nacos env-bootstrap**。在服务代码仓 grep `CONFIG_SOURCE`：
   - 有（tcg-base 式 `configSourceOptions()`：`launcher.NacosModule()` + `source.NacosConfigModule(dataID, group)`）⇒ 直接迁；
   - 没有（如 tcg-infra 首迁时全部 tag 都是纯文件模式 `os.ReadFile`）⇒ 需要先在代码仓补
     cmd/main.go 双模式开关 + internal/source 接 Nacos builder，再出新 release。
     **这是迁移最常见的隐性缺口，不查就发 Nacos/合 PR = pod 全线起不来。**
   - `launcher.SecretsModule()` 是否已接也要看：接了的话文件模式就能解析 `${vault:...}`（迁移可分两步走）。
2. **配置契约对齐目标镜像版本**。老 config.yaml 的字段可能已废弃（tcg-infra 例：
   `setMaxIdleConns→maxidleconns`、`server.mode` 删除、新增 `auth.admin_token`）。
   以代码仓 `configs/config.tmpl.yaml`（或对应版本的 options struct）为准起草 Nacos 稿，
   不要照抄老 config.yaml。新版若有「配置契约强校验」，旧字段名会直接启动失败。
3. **健康检查路径可能一起变**（tcg-infra 例：/ping → Izumo 标准 /healthz+/readyz）。
   base/deployment.yaml 探针要跟镜像版本绑定升级，别漏。

## SealedSecret 值的处理（密文不可解密回读）

- 本地无 CN 集群 kubectl 时，DSN 的 host/port/dbname **只能找用户要**（或用户给仓库/文档链接）；
  别猜。可参照 catalog 同实例先例给出「待确认」猜测（如 tcginfra 系 prod 实例）。
- ⚠ **账号/端点不能按 catalog 惯例猜，也别自作主张照搬**：老服务常有专属账号 +
  同一 RDS 实例的不同 custom 私网端点（对照表见 catalog）。正确姿势：**先拿用户原值 →
  把「复用共享条目 vs 建专属条目」的差异（权限面/端点）摆出来 → 用户拍板**。
  专属条目命名 `infra/jhs-<env>/<引擎>-<服务>-write`；换凭据时 host 跟着凭据走已验证组合，
  别把新凭据配老端点搞出没人验证过的混搭。
- USERNAME/PASSWORD → 新建 Vault 条目（命名 `infra/jhs-<env>/postgres-<实例>-<库>-write`），
  明文由用户从原 SealedSecret 来源 provision，我们只写路径。
- 应用自产密钥（admin token 等）→ `kubernetes/jhs-<env>/<代码仓名>#<FIELD>`。
- 给用户的待 provision 清单用 **JSON 串**（path/fields/env/用途），方便直接照单建条目。

## gitops 改造清单（对照 tcg-base-http envs）

每个 env：
- 删 `config.yaml` + `base/secrets.yaml`；kustomization 去掉 configMapGenerator 与 secrets 资源。
  base/ 里的空 ConfigMap 保留不动（无人挂载，回退文件模式便利，tcg-gateway 先例）。
- settings.yaml 重写：去 initContainers/volumes/volumeMounts；加
  `envFrom nacos-<env>-secret` + `CONFIG_SOURCE=nacos` + NACOS_* + `CONFIG_NACOS_DATA_ID/GROUP`
  + `VAULT_ADDR/VAULT_TOKEN`（共享 secret 按环境，见 catalog，只按名引用）。
  ⚠ **OTEL env 不能照抄老 settings，一律显式 `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`**：
  老二进制普遍内置 grpc exporter、不读协议 env，所以老 settings 里没有这个变量；
  新式二进制（标准 OTel SDK env 自动配置）缺它时默认 http/protobuf，打到 collector 的
  gRPC 4317 端口 → 启动后持续刷 `malformed HTTP response "\x00\x00\x06\x04..."`（HTTP/2 帧）。
  这是所有「老镜像→新镜像」迁移的通病，与具体服务无关；以 tcg-base-http 式模板为准起草、
  别以任何服务的老 settings 为底稿。
- version.yaml：指向首个含 nacos 支持的 release；没有就占位 + TODO 注释
  （占位 tag 拉不下来 ⇒ 旧 RS 继续服务，滚动更新天然兜底，replicas 可不动）。
- kustomization 顶部注释写全「合并前置」清单（Nacos 已发布/vault 已建/镜像已发）。
- 迁移是对**在跑服务**的切换：上线顺序 testing 验证 → 再动 prod；写进 prod kustomization 注释。

## 切换后报错分诊（任何迁移通用：先判断是否迁移引入，再动手）

- **不变式**：某后端资源（DB/Redis/ES/MQ/第三方）的连接目标与凭据若与老配置**逐项一致**，
  服务端视角新老 pod 完全等同 ⇒ 该资源上的报错必然是**存量问题**（多为后台 goroutine 的
  非致命错，老 pod 一直在报只是没人看日志），不是迁移引入——别急着怀疑 vault 值/权限/schema。
  对照手段：翻老 RS pod 日志 grep 同样报错；或用同一凭据直连资源核实（如 PG 查 `pg_tables`）。
- 真正因迁移变化的报错，特征是**老 pod 没有、新 pod 有**，且总能对应到一处具体差异：
  OTLP 协议/端点、健康检查路径、配置契约字段改名、fail-closed 的 vault 路径缺失、
  新增配置段的默认值、连接目标切换（换库/换实例 ⇒ 空库缺表要建表灌数据）。
- 分诊顺序：先列「本次迁移实际改了什么」清单，把报错逐条归类到「存量 / 某项变更」，
  归不进去的再深挖。（先例：2026-07-19 tcg-search CN prod 词典表报错为存量，
  OTLP 报错为协议变更——一次切换两类报错并存，先分诊省三轮排查。）

## 与主流程（SKILL.md §3）的衔接

Nacos 起草仍走主流程：dataId `tcg-<svc>-config.yaml` @ 业务域 group（tcg-infra 系 = TCG_INFRA），
发布前停下来出 vault 两张表 + 前置清单等确认，发布后逐字节回读 cmp。
`debug`/`server.mode` 等遗留宽松项在 prod 稿收紧（debug: false），在稿内注释注明是收紧项。
