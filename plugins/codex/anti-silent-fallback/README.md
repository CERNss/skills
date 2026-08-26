# anti-silent-fallback（Codex plugin）

**这是一个分发壳，不是源头。** 真正的工具包模板维护在 infra 仓库的
`codex-prompt/anti-silent-fallback/`——本机 checkout 在哪，由环境变量
`FALLBACK_TOOLKIT_SOURCE` 告诉同步脚本，plugin 内不写死任何机器的绝对路径。

本 plugin 把那份工具包整份拷进 `assets/toolkit/`，再包三个 skill，让 codex
能在任意仓库里「接入 / 审计 / 自检」，不必手动去 infra 里翻文件。

## 目录

```
.codex-plugin/plugin.json   plugin manifest
assets/toolkit/             infra 工具包的完整拷贝（唯一正本在 infra，见下方同步说明）
scripts/sync-from-source.sh 从 infra 源头单向同步到 assets/toolkit/
skills/
├── fallback-onboard/       把工具包接入目标仓库（README 第二章 8 步 checklist 的可执行版）
├── fallback-audit/         存量代码的静默降级 / 过度防御审计
└── fallback-selfcheck/     codex 侧「穷人版 hook」：改完代码、交付前主动跑 check-fallback.sh diff
```

`assets/toolkit/scripts/check-fallback.sh` 是**这个 plugin 里唯一的一份**检查脚本正本，
`scripts/` 目录下**不放它的副本**，避免两份脚本漂移。

## 同步方向（单向：infra → plugin）

改动一律改 infra 那份，然后跑：

```bash
FALLBACK_TOOLKIT_SOURCE=<infra checkout>/codex-prompt/anti-silent-fallback \
  bash ~/plugins/anti-silent-fallback/scripts/sync-from-source.sh
```

它是 `rsync -a --delete` 从 infra 到 `assets/toolkit/`，
**会覆盖 `assets/toolkit/` 下的本地改动**。不要在 `assets/toolkit/` 里直接编辑。

同步后建议跑一次自测确认没搬坏：

```bash
bash ~/plugins/anti-silent-fallback/assets/toolkit/scripts/selftest.sh
```

（无 semgrep 的机器上自测会退化为规则集结构校验 + 全套对账逻辑测试，仍应 `PASS`。）

## 工具包本身怎么用

见 `assets/toolkit/README.md`：五层机制、接入 checklist、豁免标注约定、
各语言补充 linter、设计取舍、故障注入测试写法。

## 与 Claude Code 的差异

工具包里的 `hooks/claude-settings.snippet.json` 是 Claude Code 的 `PostToolUse` hook 配置。
**codex 没有对等的 hook 机制**，所以在 codex 侧这一层由 `fallback-selfcheck` skill 替代：
靠模型在交付前主动跑 `check-fallback.sh diff`。强制点仍然是 pre-commit 和 CI。
