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
| 节点组件 | `_components/devnode` | `_components/stagingnode` | 在线服务不挂（默认池；prodnode 现网无人用）；**后台/任务类挂 `_components/jobnode`** |
| Nacos 账号 | jhs-testing | jhs-staging | jhs-prod（只读） |
| Nacos 密码 secret | `nacos-testing-rw-secret` | `nacos-staging-rw-secret` | `nacos-prod-ro-secret`（key: NACOS_PASSWORD） |
| Vault token secret | `vault-dev-rw-secret` | `vault-prod-ro-secret` | `vault-prod-ro-secret` |
| 共享 secret 声明者 | tcg-gateway/envs/testing | tcg-gateway/envs/staging | tcg-gateway/envs/prod（含 `s3-tcg-gateway-admin-secret`：S3AccessKey/S3SecretAccess） |
| 镜像仓库 | `jhs-cn-beijing.cr.volces.com/dev/<app>:<日期tag>` | 同 dev 仓 | `jhs-cn-beijing.cr.volces.com/prod/<app>:v*`（release 产出）；第三方镜像走 `/mirror/` |
| ingress 域名 | `<svc>.testing.tongdiaotech.com` | `<svc>.staging.tongdiaotech.com` | `<svc>.apps.tongdiaotech.com`（tls: `tongdiaotech-com-tls`） |
| 网关对外 | tcg-gateway.testing.tongdiaotech.com | — | tcg-gateway.apps.tongdiaotech.com |

`jobnode` = nodeAffinity 硬亲和 `jhs.io/dedicated=job` + 同键 toleration（NoSchedule），**专用 job 节点池，与 devnode 是不同物理节点**。
现网 prod 用它的 8 个 app：crawler-scheduler-crawler / crawler-scheduler-sink / spider / tcg-deck-deckfill-trainer /
tcg-base-worker / tcg-card-binder-worker / tcg-price-crontab / tcg-trade-job。
⚠ 跨环境推断网络可达性时注意：testing(devnode) 能连某 RDS ≠ prod(jobnode) 能连——同集群同 VPC 但不同节点，
安全组若按节点网段精确放行则未必覆盖。

⚠ 直连 ingress **默认只在 testing**；prod/staging 存量直连 2026-07-23 已批量下线（#6489），
prod 对外一律走 tcg-gateway，开本 app 专属域名需用户明示（先例 tcg-wiki-http）。
表中域名列是「获批要开时」的命名/证书惯例，不代表默认配备。

全环境通用：`VAULT_ADDR=https://vault.inc.tongdiaotech.com`；Nacos 集群内 `nacos.nacos.svc:8848`；
OTEL collector `grpc://signoz-otel-collector.monitoring:4317`（`OTEL_RESOURCE_ATTRIBUTES` 带 `deployment.environment=<env>,cloud.region=cn`）；
TZ=Asia/Shanghai；TOS 区域端点 `tos-s3-cn-beijing.volces.com` / region `cn-beijing`。

## Nacos 控制台 / API

- 控制台首选内网域名 `https://nacos.inc.tongdiaotech.com/nacos/#/`（2026-07-27 起可用，HTTPS）；
  备用外网口 `http://124.174.76.160/nacos/#/`（偶发整段 connect timeout，断了切内网域名口）。
  运维读写账号 `jhs-gitops`（**密码不落盘，找用户要**）。
- 登录 `POST /nacos/v1/auth/login`（username/password）→ accessToken；
  读 `GET /nacos/v1/cs/configs?dataId=&group=&tenant=<ns>&accessToken=`；
  列表加 `search=accurate&pageNo=1&pageSize=200`；
  发布 `POST /nacos/v1/cs/configs`（`--data-urlencode content@file` + `type=yaml`）。发布后**逐字节回读 cmp 验证**；
  ⚠ 发布返回 true 后立即回读偶见拿到旧版（传播延迟），cmp 失败先 sleep 2s 重读再判断，别急着重发。
  ⚠ 外网口偶发整段不通（connect timeout），发布类操作前先 `curl --connect-timeout 5` 探活。
  ⚠ **历史版本接口（v1 `/cs/history` 与 v2 `/cs/history/list`）服务端坏**（PG 后端 his_config_info 查询缺
  publish_type 列 → HTTP 500，2026-08-03 实测）——变更审计不可用，只能靠 `show=all` 的 create/modifyTime 粗判
  （两者相等 = 只发布过一次）；改任何配置前先把现值存档，这是唯一的回滚依据。
- dataId 惯例 `tcg-<svc>[-<face>]-config.yaml`，group 按业务域（TCG_BASE / TCG_TRADE / TCG_IDENTITY / GATEWAY / TCG_WIKI …）。

## Grafana / Prometheus（limits 定档实测数据源；PromQL 全区域通用，JP 只换 Grafana 入口——JP 入口待补）

- CN 控制台 `https://grafana.apps.tongdiaotech.com`（浏览器带登录态）。免开 UI 直查 Prometheus：
  `GET /api/datasources/proxy/uid/prometheus/api/v1/query?query=<urlencoded PromQL>`，浏览器导航即返回 JSON。
- 定档常用 PromQL（namespace=`jhs-<env>`，container 名注意特例 consumer/job/router）：
  - CPU：`sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="jhs-prod",pod=~"<app>-.*",container="server"}[5m]))`，
    峰值套 `max_over_time((…)[7d:5m])`
  - 内存：`container_memory_working_set_bytes{…}`（同上套 max_over_time 取峰）
  - CFS 限流比：`rate(container_cpu_cfs_throttled_periods_total{…}[5m]) / rate(container_cpu_cfs_periods_total{…}[5m])`
  - 在跑镜像/版本：`kube_pod_container_info{…}`；现网 requests/limits：`{__name__=~"kube_pod_container_resource_(requests|limits)",…}`；
    pod 启动时刻：`kube_pod_start_time{…}`
- ⚠ pod 正则会同时命中滚动更新窗口内的新老 ReplicaSet，按 RS hash（pod 名第一段）分组归因版本。

## jhs-prod vault ↔ 实例对照（已验证）

**MySQL（现网商城库 tcg）**：host `mysql-bc32ad6b755b-custom-e51a-private.rds.ivolces.com:3306`（私网 custom 端点；部分老配置用 `mysqlbc32ad6b755b.rds.ivolces.com`）
- `infra/jhs-prod/mysql-tcg-prod-write`（USERNAME/PASSWORD）— 写账号（trade 全家 + tcg-wiki-rpc prod 在用）
- `infra/jhs-prod/mysql-tcg-prod-read` — 只读账号（trade 读面 + base-match staging 在用）

**MySQL（资料库 tcgdb，2026-07-31 用户确认 testing/prod 共用同一实例）**：host `mysql86ed8f4618ca.rds.ivolces.com:3306`，
库 `tcgdb`（裸表 `tcgdb_card_version_maps`）+ 跨库 `` `tcgdb-raw` ``（桥表 lol_en_cards / lol_sc_cards）。
testing 侧条目 `infra/jhs-testing/mysql-material-tcgdb-read` 已验证在跑；
**prod 侧 `infra/jhs-prod/mysql-material-tcgdb-read` 截至 2026-07-31 尚未 provision**（jhs-prod 全域 72 份配置零引用）。
⚠ 账号需同时有 `tcgdb.*` 与 `` `tcgdb-raw`.* `` 的 SELECT——DSN 只连 tcgdb，桥表靠限定名跨库读，只授一个库会静默半瘫。
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
- `infra/jhs-prod/postgres-tcgdeck-tcgdeck-write` → postgresa37a1b771058.rds-pg.ivolces.com（库 tcgdeck，deck 专属实例，2026-07-27 用户已建，tcg-deck prod 五面用；USERNAME/PASSWORD 两字段齐）
- `infra/jhs-prod/postgres-testing-write` → postgres582316ae20ce.rds-pg.ivolces.com（**testing 实例镜像进 prod 域**——identity 沿用 testing PG 的先例）

**Redis**：`infra/jhs-prod/redis-prod-write` → redis-cnlfqm5kgqs5394ma.redis.ivolces.com:6379（trade 在用）；
另有 `redis-prod-gateway-write`、`redis-tcgcard-binder-write`（host 见 raw 扫描）；
`redis-tcgwiki-write` → redis-cnlfhxmq556x5wz6a.redis.ivolces.com:6379（wiki 专属实例 db14，2026-07-20 用户已建）。

**ES**：`infra/jhs-prod/elasticsearch-prod-write` → es-cn-7pp2qp8330007okgh.public.elasticsearch.aliyuncs.com:9200（阿里云）；
`infra/jhs-prod/elasticsearch-volce-prod-write` → elasticsearch-o-00447gsxyq04.escloud.ivolces.com:9200（火山 escloud，tcg-search 用，2026-07-19 用户已建）。

**StarRocks**：`infra/jhs-prod/starrocks-prod-write` → 192.168.0.144:9030；`starrocks-tcgcard-binder-write` → 192.168.0.163:9030。

**TOS/S3**：`infra/jhs-prod/tos-crawler-scheduler-write`；`infra/jhs-prod/tos-infra-config-write`（ACCESS_KEY_ID/SECRET_ACCESS_KEY，infra-config bucket，2026-07-17 用户已建）。

**TIM 推送**：`infra/jhs-prod/tim-push-admin#IM_KEY`（生产聊天应用 1400373046 的 SecretKey，2026-07-17 用户已建；注意与 testing 的 `infra/jhs-testing/tim-push#SDK_SECRET_KEY` 命名不同构）。

**Kafka**：CN prod 有本地集群 `kafka-cnngkq2j9nczt3ym.kafka.cn-beijing.ivolces.com:9093`，
SASL_PLAINTEXT / PLAIN，凭据 `infra/jhs-prod/kafka-cn_beijing-write#USERNAME|#PASSWORD`
（条目名 `cn_beijing` 下划线混 `-write` 连字符，非笔误；trade 四面 auction/auction-rpc/job/consumer 已引用，
均 enabled=false 管道预埋 ⇒ 该条目尚无在跑服务实际解析过，属未验证条目）。
跨境场景走 ap-southeast 的 `kafka-ap-1c3wqcachatti...`，凭据 `infra/jhs-prod/kafka-southeast-write#USERNAME|#PASSWORD`
（crawler-scheduler 四面用 `:9093` ivolces 内网口 = 已验证在跑；idlinker 用 `:9491` volces 公网口；price-crontab 用 `:9092`——同集群三端点，别混）。
testing 侧 **jhs-dev 集群有两个入口，鉴权不同，别混**：
- `kafka.jhs-dev:9094` —— SASL_PLAINTEXT / PLAIN，凭据 `infra/jhs-testing/kafka-crawler-dev-write#USERNAME|#PASSWORD`（crawler-scheduler testing 在用 = 已验证）
- `kafka-nodeport-svc.jhs-dev:9094` —— **无 SASL、无 TLS**，配置里不写 sasl 段（tcg-idlinker link-write / mapper、tcg-fileservice derive 在用）

⚠ 字段名陷阱：tcg-idlinker 配置里**注释掉**的行把同一条目写成 `#KAFKA_USERNAME`/`#KAFKA_PASSWORD`，与现网跑着的 crawler-scheduler（`#USERNAME`/`#PASSWORD`）不一致——以跑着的那组为准。
⚠ topic 未必自动创建：idlinker 配置注释提示 jhs-dev broker 可能没开 auto-create，新 topic 要先让运维手工建。

配置写法有三种并存风格，跟同族服务走：crawler-scheduler = 业务段下扁平 kebab `kafka-*` 键；tcg-idlinker = 嵌套 `kafka:`/`kafka_producer:`/`kafka_consumer:` + snake_case；tcg-fileservice = 嵌套 `kafka:` + kebab + `enabled` 门控。
目标环境没有的设施 ⇒ 配置整段门控关闭。

**kubernetes/jhs-prod/**（应用自产密钥域）：`jwt-secret#JWT_SECRET`、`tcg-identity#PRIVACY_AES_ENCRYPT_KEY|WECHAT_APP_SECRET_PRO`、`tcg-trade#IM_KEY|ADA_PAY_*|NTES_DUN_*|WECHAT_OFFICIAL_ACCOUNT_SECRET|…`、`tcg-gateway#…`、`tcg-grade-service#…`、`tcg-price-crontab#…`、`tcg-idlinker#…`、`tcg-gitops#WEBHOOK_SECRET`。
`kubernetes/jhs-prod/tcg-base`（PLAN_SIGNING_KEY / DEEPLINK_SIGNING_SECRET / GITHUB_COSMO_DISPATCH_TOKEN / FILE_CALLBACK_SECRET，2026-07-17 用户已建）。

## jhs-testing vault ↔ 实例对照（已验证，节选常用）

- PG（tcgbase 等 dev 库）：`infra/jhs-testing/postgres-dev-write` → postgres47088f07c3d0.rds-pg.ivolces.com
  （tcg-search testing 库 tcgsearch；staging 用同实例独立库 tcgsearch_staging——staging 凭据需 prod 域镜像条目 infra/jhs-prod/postgres-dev-write，2026-07-19 拍板）
  ⚠ 2026-08-11 上午实列 infra/jhs-prod 时该镜像条目**尚不存在**（2026-07-19 拍板了没落地，jhs-staging 的
  tcg-search-config.yaml 一直在引用 ⇒ 期间该段 fail-closed）；同日用户已补建 `infra/jhs-prod/postgres-dev-write`
  （USERNAME=devuser / PASSWORD，实读验证，crawler-preprocess prod 双面 + tcg-search staging 共用）。
  教训：引用任何"catalog 已验证"条目前，先实列一遍目标域（`GET /v1/<mount>/metadata/<ns>?list=true`）——
  "有配置在引用"不等于"条目存在"。
- PG（identity 等）：`infra/jhs-testing/postgres-testing-write` → postgres582316ae20ce.rds-pg.ivolces.com
- MySQL（现网结构 testing 库 tcg）：`infra/jhs-testing/mysql-testing-write` → mysqlda9376289ad9.rds.ivolces.com:3306
- MySQL（tcg testing 另一实例）：`infra/jhs-testing/mysql-tcg-testing-write` → mysqldd8e60636efd.rds.ivolces.com:3306
- MySQL（**生产只读进 testing 域**）：`infra/jhs-testing/mysql-prod-read` → mysql-bc32ad6b755b-custom-e4b0-private.rds.ivolces.com:3306（注意 e4b0 端点，与 prod 域的 e51a 不同）
- ES：`infra/jhs-testing/elasticsearch-testing-write` → elasticsearch-o-0040o9qpa9g8.escloud.ivolces.com:9200
- ES（tcg-search 专用 escloud 实例）：`infra/jhs-testing/elasticsearch-volce-testing-write` →
  elasticsearch-o-00447gsxyq04.escloud.ivolces.com:9200（CN 三环境同址，2026-07-19 用户已建；prod 域对应条目 elasticsearch-volce-prod-write）
- Redis：`infra/jhs-testing/redis-testing-write`（redis-cnlfc3s9fctedp8ta / redis-cnlfejfecsejfte5a 两实例，按消费方查）。
  共享实例 cnlfejfecsejfte5a 的 db 占用：0=deck×3/grade×3/identity/idlinker/gateway/payment/base 家族、10=admin-api、14=wiki-rpc、
  12=card-binder-http（2026-08-03 起，key 带 `tcg-card-binder:` 前缀）、11=tcg-market-quote **staging** 三面（跨环境借用，
  用户 2026-09-14 指定）——新服务挑 db 先查这行避让。条目字段 USERNAME + PASSWORD 两个（2026-09-14 扫 jhs-testing 96 份配置确认）。
- TOS：`infra/jhs-testing/tos-infra-config-write`（infra-config bucket，subgraph/超图发布）；`tos-tcgai-write`；
  `tos-crawler-scheduler-write`（与 prod 同 bucket crawler-scheduler，testing 靠 object-key-prefix `jhs-testing/spider-data` 分路径，2026-07-20 用户确认）
- Kafka（dev 集群，集群内地址）：`kafka.jhs-dev:9094`（crawler-scheduler testing 在用，凭据 `kafka-crawler-dev-write`；idlinker link-write 配置里写的是 `kafka-nodeport-svc.jhs-dev:9094`，无 TLS）
- 其他：`tim-push#SDK_SECRET_KEY`、`sms-aliyun-admin`、`sms-volcengine-admin`、`app-feishu-admin`、`git-forgejo-admin`、`api-argocd-admin`、`starrocks-*`、`kafka-crawler-dev-write`
- `kubernetes/jhs-testing/`：jwt-secret、tcg-base（PLAN_SIGNING_KEY/DEEPLINK_SIGNING_SECRET/GITHUB_COSMO_DISPATCH_TOKEN）、tcg-trade、tcg-identity、tcg-gateway、tcg-deck、tcg-admin-api、tcg-wiki、tcg-price-crontab、tcg-idlinker、tcg-gitops

## jhs-staging（只读验证环境，条目极少）

- `infra/jhs-prod/mysql-tcg-prod-read`（跨域引用生产只读——staging 的设计就是读 prod 数据）
- `kubernetes/jhs-staging/jwt-secret`
- **`infra/jhs-staging/` 域首个条目** `postgres-tcgprice-tcgprice_svc-write` → postgres3edbf27559ff.rds-pg.ivolces.com:5432，
  库 tcgprice_svc（staging 专用 PG 实例，用户 2026-09-14 指定；tcg-price-service 主面 + tcg-market-quote 三面 staging 引用；
  vault-prod-ro token 能否读 `infra/jhs-staging/*` 尚待首启实测）。
- Redis：staging 借 testing 共享实例 `redis-cnlfejfecsejfte5a` + `infra/jhs-testing/redis-testing-write`（用户 2026-09-14 指定，
  market-quote 三面用 db 11）。⚠ 跨到 jhs-testing 域，vault-prod-ro token 按 tcg-search staging 先例**读不了**——
  首启 fail-closed 就把条目镜像成 `infra/jhs-staging/redis-testing-write` 改稿重发。
- ⚠ staging 的 `tcg-base.yaml` 是从 jhs-dev 拷的，**不能当惯例参考**；staging 正确姿势见 tcg-base-match staging。

## 重扫脚本（catalog 过期时刷新）

登录拿 token 后，对每个 ns 列全量配置、逐个拉内容，正则提取 `\$\{vault:([^#}]+)#([^}]+)\}` 与
`@tcp\(([^)]+)\)/(\w+)`、`host=([\w.-]+)`，按「同一行共现」映射 vault↔host。参考实现见
2026-07-15 会话 scratchpad `infra-catalog.json` 生成脚本（python3 + urllib，两段式：先 catalog 后 pair 映射）。
