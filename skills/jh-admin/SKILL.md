---
name: jh-admin
description: >-
  操作集换社（jihuanshe）admin 平台时使用——通过 jh CLI 调用网关的 admin operations
  做线上管理动作（查询/变更配置、部署、绑定、回滚等）。本指南是 agent 驱动 jh 的契约说明书：
  调用方式、结果判读、错误处置、危险操作的审批流程，以及按任务分类的 playbook 索引。
  当你需要「以 admin 身份对集换社线上系统做查询或变更」时读它。
---

# 驱动 jh（集换社 admin CLI）

你即将用 `jh` 对集换社（jihuanshe）线上系统做 admin 操作。**先运行下面的命令读取随二进制分发的完整契约**（调用方式、JSON 信封、退出码语义、危险操作审批、按任务的 playbook 索引），然后照它做。

```bash
jh guide                 # 通用契约 + playbook 地图（入口，先读这个）
jh guide --list          # 机读 playbook 索引（默认 JSON 信封；--output pretty 看人类表格）
jh guide <topic>         # 读某个 playbook 的完整 SOP
```

本文件只是一个**指针**：真正的、与你本机 `jh` 版本锁定的指南在二进制里，用上面的命令现取。不要依赖本文件记具体的 operation 名或参数——一律以 `jh guide` 和 `jh schema` 的输出为准。

<!-- managed-by: jh skill install -->
