# JP（东京 aws-ap-tokyo 集群）infra 信息落盘

快照时间：2026-07-22，来源 = tcg-wiki http/rpc 东京 prod 影子部署 + jhs-prod-tokyo 全量配置扫描。
与 CN catalog 同构原则：已验证 = 该环境有正在运行的服务在解析该路径。

## 环境速查（prod-tokyo，testing-tokyo 同构类推）

| 项 | 值 |
|---|---|
| appset / 目标 | prod-tokyo-appset（`apps/*/envs/prod-tokyo`）→ 集群 `aws-ap-tokyo`，ns `jhs-prod`（与 CN 同名 ns，不同集群） |
| Nacos 控制台 | **https://nacos.inc.tcgcard.jp/nacos/#/**（账号 jhs-gitops，密码找用户要；⚠ 旧 IP 口 57.183.76.246:38848 GET 通但 POST 一律 reset，API 必须走域名） |
| Nacos ns | `jhs-testing-tokyo` / `jhs-staging-tokyo` / `jhs-prod-tokyo`（**ns 带 -tokyo 后缀**；与 CN 不是一套） |
| 集群内 Nacos | `nacos.nacos.svc.cluster.local:8848`，账号 `jhs-prod`（secret `nacos-prod-ro-secret`，tcg-gateway/envs/prod-tokyo 声明） |
| Vault | `https://vault.inc.tcgcard.jp`（secret `vault-prod-ro-secret`）；**条目域无 -tokyo 后缀**（`infra/jhs-prod/*`、`kubernetes/jhs-prod/*`，与 CN vault 是两套同名域） |
| 镜像仓 | `jhs-ap-southeast-1.cr.volces.com/prod/<app>:v*`（dev 同仓 /dev/） |
| ingress | `<app>.apps.tcgcard.jp` + `tcgcard-jp-tls`（泛解析已就位；另有 *.tcgcard.ai 老域名族） |
| TZ / NODE_REGION | Asia/Tokyo / JP；OTEL `cloud.region=jp` |
| OTEL collector | **两个并存**：`otelcol.monitoring:4317`（老 tcgwiki http 等在用）与 `signoz-otel-collector.monitoring:4317`（老 tcgwiki-rpc、trade 新 app 在用）。迁移时保持各面老部署等价，不擅自统一 |

## jhs-prod vault ↔ 实例对照（已验证/已拍板）

- **MySQL 写**：`infra/jhs-prod/mysql-tcg-write` + `proxysql:3306` 库 tcg（trade 全家在用）
- **MySQL 只读**：`infra/jhs-prod/mysql-jhs_db-tcg-read` + Aurora 只读端点
  `jhs-db-prod-cluster.cluster-ro-c3syqs6qmo0r.ap-northeast-1.rds.amazonaws.com:3306` 库 tcg
  （账号 tcgwiki，2026-07-22 wiki 用；**cluster-ro 与 proxysql 是读/写两条路径，账号↔端点配套**）
- **PG（tcgsearch）**：`infra/jhs-prod/postgres-tcgsearch-tcgsearch-write` → jhs-postgre-tcgsearch-prod.c3syqs6qmo0r...rds.amazonaws.com
- **PG（tcgwiki，只读）**：`infra/jhs-prod/postgres-tcgwiki-tcgwiki-read` → jhs-postgre-prod.c3syqs6qmo0r...rds.amazonaws.com:5432 库 tcgwiki
  （2026-08-06 由 `postgres-jhs_postgre-tcgwiki-read` 切换，用户确认已 provision；旧条目已无任何配置引用，
  待 wiki 两面用新条目健康重启后可下线）
- **PG（tcgdata）**：`infra/jhs-prod/postgres-tcgdata-tcgdata-write`
- **Redis**：`infra/jhs-prod/redis-tcg-write` → cluster-redis-prod.j3kkot.0001.apne1.cache.amazonaws.com:6379
- **ES**：`infra/jhs-prod/elasticsearch-prod-write` → https://vpc-es-prod-7cfns5zwklzmalw2xhzm4elnyi.ap-northeast-1.es.amazonaws.com:443
- **DynamoDB**：`infra/jhs-prod/dynamodb-ap_northeast-jhs_tcgwiki-write`（ACCESS_KEY_ID/SECRET_ACCESS_KEY，region ap-northeast-1）
- `kubernetes/jhs-prod/tcg-trade`（大量业务密钥字段，trade 在用）

注：JP 条目名允许下划线（用户命名习惯，如 jhs_db / jhs_postgre / ap_northeast）——Vault 路径、resolver、
policy 前缀匹配、扫描正则全链路兼容，但 AWS RDS 实例标识符本身无下划线，条目名与实例名并非逐字对应。

## 踩坑记录

- 老东京 wiki 的 DB 账号**本来就是只读**（PG tcgwiki_ro、MySQL 走 cluster-ro 端点）：等价迁移时权限面
  也要等价——别把只读账号"升级"成共享写条目（CN 的复用共享写先例不自动跨区搬运，需用户重新拍板）。
- 段落集合按**区域各自的老配置**比对：东京老 wiki 无 redis/supergraph/tcg_search（CN 有 redis/supergraph），
  http 面多 notify；dynamodb 在 JP 是真实 AK/SK（CN 留空走默认凭据链）。同一服务不同区域不同构是常态。
