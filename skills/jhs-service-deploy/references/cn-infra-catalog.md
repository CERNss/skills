# CN（国内集群）各环境 infra 信息落盘

快照时间：2026-07-15，来源 = 全量扫描 Nacos jhs-testing/jhs-staging/jhs-prod 三个命名空间的配置内容
（`${vault:...}` 引用 + DSN host 提取）。原则：**各环境用各自的 infra/jhs-<env> 与 kubernetes/jhs-<env> 条目**。
「已验证」= 该环境有正在运行的服务在解析该路径（fail-closed 下能跑 ⇒ 条目存在且 token 可读）。

## 环境速查

| | jhs-testing | jhs-staging | jhs-prod |
|---|---|---|---|
| 定位 | 日常联调 | 生产数据**只读**验证 | 生产 |
| appset | testing-appset（envs/testing） | staging-appset（envs/staging） | prod-appset（envs/prod） |
| 集群/ns | kubernetes.default.svc → 同名 ns（三环境同一 CN 集群） | 同左 | 同左 |
| 节点组件 | `_components/devnode` | `_components/stagingnode` | 不挂（默认池；prodnode 存在但现网 prod 无人用） |
| Nacos 账号 | jhs-testing | jhs-staging | jhs-prod（只读） |
| Nacos 密码 secret | `nacos-testing-rw-secret` | `nacos-staging-rw-secret` | `nacos-prod-ro-secret`（key: NACOS_PASSWORD） |
| Vault token secret | `vault-dev-rw-secret` | `vault-prod-ro-secret` | `vault-prod-ro-secret` |
| 共享 secret 声明者 | tcg-gateway/envs/testing | tcg-gateway/envs/staging | tcg-gateway/envs/prod（含 `s3-tcg-gateway-admin-secret`：S3AccessKey/S3SecretAccess） |
| 镜像仓库 | `jhs-cn-beijing.cr.volces.com/dev/<app>:<日期tag>` | 同 dev 仓 | `jhs-cn-beijing.cr.volces.com/prod/<app>:v*`（release 产出）；第三方镜像走 `/mirror/` |
| ingress 域名 | `<svc>.testing.tongdiaotech.com` | `<svc>.staging.tongdiaotech.com` | `<svc>.apps.tongdiaotech.com`（tls: `tongdiaotech-com-tls`） |
| 网关对外 | tcg-gateway.testing.tongdiaotech.com | — | tcg-gateway.apps.tongdiaotech.com |

全环境通用：`VAULT_ADDR=https://vault.inc.tongdiaotech.com`；Nacos 集群内 `nacos.nacos.svc:8848`；
OTEL collector `grpc://signoz-otel-collector.monitoring:4317`（`OTEL_RESOURCE_ATTRIBUTES` 带 `deployment.environment=<env>,cloud.region=cn`）；
TZ=Asia/Shanghai；TOS 区域端点 `tos-s3-cn-beijing.volces.com` / region `cn-beijing`。

## Nacos 控制台 / API

- 外网控制台 `http://124.174.76.160/nacos/#/`，运维读写账号 `jhs-gitops`（**密码不落盘，找用户要**）。
- 登录 `POST /nacos/v1/auth/login`（username/password）→ accessToken；
  读 `GET /nacos/v1/cs/configs?dataId=&group=&tenant=<ns>&accessToken=`；
  列表加 `search=accurate&pageNo=1&pageSize=200`；
  发布 `POST /nacos/v1/cs/configs`（`--data-urlencode content@file` + `type=yaml`）。发布后**逐字节回读 cmp 验证**；
  ⚠ 发布返回 true 后立即回读偶见拿到旧版（传播延迟），cmp 失败先 sleep 2s 重读再判断，别急着重发。
  ⚠ 外网口偶发整段不通（connect timeout），发布类操作前先 `curl --connect-timeout 5` 探活。
- dataId 惯例 `tcg-<svc>[-<face>]-config.yaml`，group 按业务域（TCG_BASE / TCG_TRADE / TCG_IDENTITY / GATEWAY / TCG_WIKI …）。

## jhs-prod vault ↔ 实例对照（已验证）

**MySQL（现网商城库 tcg）**：host `mysql-bc32ad6b755b-custom-e51a-private.rds.ivolces.com:3306`（私网 custom 端点；部分老配置用 `mysqlbc32ad6b755b.rds.ivolces.com`）
- `infra/jhs-prod/mysql-tcg-prod-write`（USERNAME/PASSWORD）— 写账号（trade 全家 + tcg-wiki-rpc prod 在用）
- `infra/jhs-prod/mysql-tcg-prod-read` — 只读账号（trade 读面 + base-match staging 在用）
- ⚠ **同一 RDS 实例 bc32ad6b755b 至少三个 custom 私网端点**，账号↔端点要配套、不可混搭：
  `custom-e51a`（prod 共享条目在用）/ `custom-e4b0`（testing 域 mysql-prod-read 在用）/
  `custom-b6b4`（老 tcgwiki 专属账号 tcgwiki 在用，新 tcg-wiki-rpc prod 已弃用改走 e51a+共享写）。

**PostgreSQL**（命名式样 `postgres-<实例>-<库>-write`）：
- `infra/jhs-prod/postgres-tcgdata-prod-write` / `postgres-tcggrade-write` → postgres26a4ffbc89ca.rds-pg.ivolces.com
- `infra/jhs-prod/postgres-tcginfra-crawler-scheduler-write` / `postgres-tcginfra-gitops-write` → postgres27ddd1675a66.rds-pg.ivolces.com
- `infra/jhs-prod/postgres-tcgprice-tcgprice-write` → postgresa6fffe10789a.rds-pg.ivolces.com
- `infra/jhs-prod/postgres-tcgsearch-tcgprice-write` → postgres258426c98095.rds-pg.ivolces.com
- `infra/jhs-prod/postgres-tcgsearch-tcgsearch-write` → postgres258426c98095.rds-pg.ivolces.com（库 tcgsearch，2026-07-19 用户已建，tcg-search prod 用）
- `infra/jhs-prod/postgres-tcgcard-binder-tcgcard-binder-write` → postgres60c3c3e28ad1.rds-pg.ivolces.com
- `infra/jhs-prod/postgres-tcgbase-tcgbase-write` → postgres1f0d976accfe.rds-pg.ivolces.com（库 tcgbase，2026-07-17 用户已建）
- `infra/jhs-prod/postgres-tcgwiki-tcgwiki-write` → postgrese2329fec7029.rds-pg.ivolces.com（库 tcgwiki，wiki 专属实例，2026-07-20 用户已建，tcg-wiki-rpc prod 用）
- `infra/jhs-prod/postgres-testing-write` → postgres582316ae20ce.rds-pg.ivolces.com（**testing 实例镜像进 prod 域**——identity 沿用 testing PG 的先例）

**Redis**：`infra/jhs-prod/redis-prod-write` → redis-cnlfqm5kgqs5394ma.redis.ivolces.com:6379（trade 在用）；
另有 `redis-prod-gateway-write`、`redis-tcgcard-binder-write`（host 见 raw 扫描）；
`redis-tcgwiki-write` → redis-cnlfhxmq556x5wz6a.redis.ivolces.com:6379（wiki 专属实例 db14，2026-07-20 用户已建）。

**ES**：`infra/jhs-prod/elasticsearch-prod-write` → es-cn-7pp2qp8330007okgh.public.elasticsearch.aliyuncs.com:9200（阿里云）；
`infra/jhs-prod/elasticsearch-volce-prod-write` → elasticsearch-o-00447gsxyq04.escloud.ivolces.com:9200（火山 escloud，tcg-search 用，2026-07-19 用户已建）。

**StarRocks**：`infra/jhs-prod/starrocks-prod-write` → 192.168.0.144:9030；`starrocks-tcgcard-binder-write` → 192.168.0.163:9030。

**TOS/S3**：`infra/jhs-prod/tos-crawler-scheduler-write`；`infra/jhs-prod/tos-infra-config-write`（ACCESS_KEY_ID/SECRET_ACCESS_KEY，infra-config bucket，2026-07-17 用户已建）。

**TIM 推送**：`infra/jhs-prod/tim-push-admin#IM_KEY`（生产聊天应用 1400373046 的 SecretKey，2026-07-17 用户已建；注意与 testing 的 `infra/jhs-testing/tim-push#SDK_SECRET_KEY` 命名不同构）。

**Kafka**：CN prod 无 kafka（jhs-prod 里引用的 kafka 都是 ap-southeast 的 `kafka-ap-1c3wqcachatti...`；testing 派生用的是 jhs-dev nodeport）。目标环境没有的设施 ⇒ 配置整段门控关闭。

**kubernetes/jhs-prod/**（应用自产密钥域）：`jwt-secret#JWT_SECRET`、`tcg-identity#PRIVACY_AES_ENCRYPT_KEY|WECHAT_APP_SECRET_PRO`、`tcg-trade#IM_KEY|ADA_PAY_*|NTES_DUN_*|WECHAT_OFFICIAL_ACCOUNT_SECRET|…`、`tcg-gateway#…`、`tcg-grade-service#…`、`tcg-price-crontab#…`、`tcg-idlinker#…`、`tcg-gitops#WEBHOOK_SECRET`。
`kubernetes/jhs-prod/tcg-base`（PLAN_SIGNING_KEY / DEEPLINK_SIGNING_SECRET / GITHUB_COSMO_DISPATCH_TOKEN / FILE_CALLBACK_SECRET，2026-07-17 用户已建）。

## jhs-testing vault ↔ 实例对照（已验证，节选常用）

- PG（tcgbase 等 dev 库）：`infra/jhs-testing/postgres-dev-write` → postgres47088f07c3d0.rds-pg.ivolces.com
  （tcg-search testing 库 tcgsearch；staging 用同实例独立库 tcgsearch_staging——staging 凭据需 prod 域镜像条目 infra/jhs-prod/postgres-dev-write，2026-07-19 拍板）
- PG（identity 等）：`infra/jhs-testing/postgres-testing-write` → postgres582316ae20ce.rds-pg.ivolces.com
- MySQL（现网结构 testing 库 tcg）：`infra/jhs-testing/mysql-testing-write` → mysqlda9376289ad9.rds.ivolces.com:3306
- MySQL（tcg testing 另一实例）：`infra/jhs-testing/mysql-tcg-testing-write` → mysqldd8e60636efd.rds.ivolces.com:3306
- MySQL（**生产只读进 testing 域**）：`infra/jhs-testing/mysql-prod-read` → mysql-bc32ad6b755b-custom-e4b0-private.rds.ivolces.com:3306（注意 e4b0 端点，与 prod 域的 e51a 不同）
- ES：`infra/jhs-testing/elasticsearch-testing-write` → elasticsearch-o-0040o9qpa9g8.escloud.ivolces.com:9200
- ES（tcg-search 专用 escloud 实例）：`infra/jhs-testing/elasticsearch-volce-testing-write` →
  elasticsearch-o-00447gsxyq04.escloud.ivolces.com:9200（CN 三环境同址，2026-07-19 用户已建；prod 域对应条目 elasticsearch-volce-prod-write）
- Redis：`infra/jhs-testing/redis-testing-write`（redis-cnlfc3s9fctedp8ta / redis-cnlfejfecsejfte5a 两实例，按消费方查）
- TOS：`infra/jhs-testing/tos-infra-config-write`（infra-config bucket，subgraph/超图发布）；`tos-tcgai-write`；
  `tos-crawler-scheduler-write`（与 prod 同 bucket crawler-scheduler，testing 靠 object-key-prefix `jhs-testing/spider-data` 分路径，2026-07-20 用户确认）
- Kafka（dev 集群，集群内地址）：`kafka.jhs-dev:9094`（crawler-scheduler testing 在用，凭据 `kafka-crawler-dev-write`；idlinker link-write 配置里写的是 `kafka-nodeport-svc.jhs-dev:9094`，无 TLS）
- 其他：`tim-push#SDK_SECRET_KEY`、`sms-aliyun-admin`、`sms-volcengine-admin`、`app-feishu-admin`、`git-forgejo-admin`、`api-argocd-admin`、`starrocks-*`、`kafka-crawler-dev-write`
- `kubernetes/jhs-testing/`：jwt-secret、tcg-base（PLAN_SIGNING_KEY/DEEPLINK_SIGNING_SECRET/GITHUB_COSMO_DISPATCH_TOKEN）、tcg-trade、tcg-identity、tcg-gateway、tcg-deck、tcg-admin-api、tcg-wiki、tcg-price-crontab、tcg-idlinker、tcg-gitops

## jhs-staging（只读验证环境，条目极少）

- `infra/jhs-prod/mysql-tcg-prod-read`（跨域引用生产只读——staging 的设计就是读 prod 数据）
- `kubernetes/jhs-staging/jwt-secret`
- ⚠ staging 的 `tcg-base.yaml` 是从 jhs-dev 拷的，**不能当惯例参考**；staging 正确姿势见 tcg-base-match staging。

## 重扫脚本（catalog 过期时刷新）

登录拿 token 后，对每个 ns 列全量配置、逐个拉内容，正则提取 `\$\{vault:([^#}]+)#([^}]+)\}` 与
`@tcp\(([^)]+)\)/(\w+)`、`host=([\w.-]+)`，按「同一行共现」映射 vault↔host。参考实现见
2026-07-15 会话 scratchpad `infra-catalog.json` 生成脚本（python3 + urllib，两段式：先 catalog 后 pair 映射）。
