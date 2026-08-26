---
name: fallback-onboard
description: 把「反静默降级 / 过度防御拦截」工具包接入一个仓库：拷 semgrep 规则集与 check-fallback.sh、建 policy/fallbacks.yaml 降级白名单、装 pre-commit、接 CI（FALLBACK_CHECK_STRICT=1）、用 CODEOWNERS 保护白名单、把规则片段写进 AGENTS.md，最后跑 selftest 与 full 验收。当用户说「接入反静默降级 / 装 fallback 检查 / 加静默降级拦截 / 配 semgrep 拦截静默 fallback / 上降级白名单 / 接 anti-silent-fallback」时使用。
---

# 接入反静默降级工具包

把「不要写静默 fallback」从嘱咐下沉成机器可执行的拦截。**这是接入流程，不是审计流程**：
存量清理走 `fallback-audit` skill；交付前的单次自检走 `fallback-selfcheck` skill。

## 0. 先定位 plugin 自带的工具包

本 skill 加载时 codex 会提供 **base directory**（即本 `SKILL.md` 所在目录）。
工具包正本就在它上两级的 `assets/toolkit/`：

```
<base directory>/../../assets/toolkit/
```

开工第一件事，把它解析成绝对路径并存成变量（后续所有命令都用它）：

```bash
# 把 <base directory> 换成 codex 给出的绝对路径
TOOLKIT="$(cd "<base directory>/../../assets/toolkit" && pwd)"
ls "$TOOLKIT"   # 应看到 README.md ci examples hooks policy prompts scripts semgrep templates
```

若 base directory 拿不到，再退到默认安装位置 `~/plugins/anti-silent-fallback/assets/toolkit`；
两者都不存在就**停下来问用户**，不要凭记忆重写规则集。

再确认目标仓库根：

```bash
TARGET="$(git -C . rev-parse --show-toplevel)"
PKG="$TARGET/tools/anti-silent-fallback"     # 工具包在目标仓库里的落位，可与用户商量改
```

接入前先跟用户确认三件事：`$PKG` 落位路径、目标仓库有哪些语言（决定拷不拷 Go/Python 模板）、
CI 平台是不是 GitHub Actions（不是的话第 5 步要改写）。

## 1. 拷文件

```bash
mkdir -p "$PKG" "$TARGET/policy"
cp -R "$TOOLKIT/semgrep" "$TOOLKIT/scripts" "$PKG"/
cp -R "$TOOLKIT/examples" "$PKG"/                                   # 可选，full 模式会自动排除
cp "$TOOLKIT/policy/fallbacks.example.yaml" "$TARGET/policy/fallbacks.yaml"
chmod +x "$PKG/scripts/check-fallback.sh" "$PKG/scripts/selftest.sh"
```

| 拷什么 | 拷到哪 | 必需？ |
| --- | --- | --- |
| `semgrep/silent-fallback.yaml` | `$PKG/semgrep/` | 必需 |
| `scripts/check-fallback.sh` | `$PKG/scripts/` | 必需 |
| `scripts/selftest.sh` | `$PKG/scripts/` | 建议（升级规则集后自测） |
| `policy/fallbacks.example.yaml` | **仓库根 `policy/fallbacks.yaml`**（重命名） | 必需 |
| `templates/go/fallback/fallback.go` | `internal/fallback/fallback.go` | 有 Go 代码则必需 |
| `templates/python/fallback.py` | `<yourapp>/fallback.py` | 有 Python 代码则必需 |
| `examples/` | `$PKG/examples/` | 可选 |

拷 Go 模板时**不要拷 `templates/go/fallback/go.mod`**（它只让工具包内自测能独立 build），
并把 `fallback.go` 的 import 路径改成宿主 module 路径。

## 2. 改占位符

工具包里所有片段都以 `tools/anti-silent-fallback/` 作为路径占位。若 `$PKG` 不是这个路径，
逐个文件替换：

| 文件 | 占位符 | 改成 |
| --- | --- | --- |
| `hooks/pre-commit-config.snippet.yaml` | `tools/anti-silent-fallback/` | `$PKG` 相对仓库根的路径 |
| `ci/github-actions.snippet.yml` | 同上 | 同上 |
| `prompts/agents-md-snippet.md` | `<工具包路径>` | 同上 |
| `hooks/claude-settings.snippet.json` | 同上 | 同上（codex 用户可跳过，见第 3 步） |
| `policy/fallbacks.yaml` | 三条示例条目 | 换成本仓库真实条目 |

`policy/fallbacks.yaml` 里的 `check-script-semgrep-missing` 和 `check-script-*` 两条**必须保留**
——它们描述的是 `check-fallback.sh` 自身的降级行为，删了 `full` 模式的豁免对账会红。
第三条业务示例条目删掉或换成真实条目。

## 3. 装编辑期 hook（codex 用户：可选，且机制不同）

工具包的 `hooks/claude-settings.snippet.json` 是 **Claude Code 的 `PostToolUse` hook** 配置。
**codex 没有对等的 hook 机制**，所以：

- 目标仓库有人用 Claude Code → 把该片段的 `hooks` 键合并进 `.claude/settings.json`
  （团队共享）或 `.claude/settings.local.json`（只影响自己），删掉 `_README` / `_comment` 键。
- 纯 codex 团队 → **跳过这一步**，改为让 codex 用 `fallback-selfcheck` skill
  在每回合交付前主动跑 `check-fallback.sh diff`。

这一层无论如何都不是强制点，强制点是第 4、5 步。

## 4. 装 pre-commit（提交即拦）

把 `$TOOLKIT/hooks/pre-commit-config.snippet.yaml` 的 `repos` 条目合并进目标仓库
`.pre-commit-config.yaml`（已有 `repos` 就追加一个 `- repo: local` 条目，不要整段覆盖），
`entry` 路径改成 `$PKG` 的实际相对路径，然后：

```bash
pip install pre-commit && pre-commit install
pre-commit run anti-silent-fallback --all-files
```

这一层 semgrep 缺失 = 直接失败，不放行。

## 5. 接 CI（唯一不可绕过的一层）

把 `$TOOLKIT/ci/github-actions.snippet.yml` 合并进 `.github/workflows/`（可独立成一个 workflow
文件，也可把 `jobs` 段并进已有 workflow），确认：

- `FALLBACK_CHECK_STRICT: "1"` 必须在（fail-closed）；
- `FALLBACK_REGISTRY` 指向真实白名单路径；
- semgrep 版本已 pin（片段里是 `semgrep==1.174.0`），升级版本时要重跑 `selftest.sh`；
- 按需填 `FALLBACK_EXCLUDE`（第三方 / 生成代码目录，空格分隔）。

非 GitHub Actions 的 CI，照抄那两条命令即可：
`FALLBACK_CHECK_STRICT=1 bash <PKG>/scripts/check-fallback.sh full` 和 `bash <PKG>/scripts/selftest.sh`。

**接完提醒用户把这个 job 设成分支保护的 required check** —— 这一步 codex 做不了，必须人去仓库设置里点。

## 6. 保护白名单（关键，别跳过）

`.github/CODEOWNERS` 加一行，让「改白名单」= 「走审批」：

```
/policy/fallbacks.yaml    @your-org/tech-leads @your-org/sre
```

`@your-org/...` 换成真实 team，**问用户要，不要自己编**。
没有这一步，白名单就是个人人可写的许愿池，整套机制退化成摆设。

## 7. 写进 AGENTS.md（嘱咐层）

打开 `$TOOLKIT/prompts/agents-md-snippet.md`，把其中 ```markdown 代码块**里面的正文**
（`## 降级与错误处理（硬性规则）` 那一节，7 条规则 + 末尾的强制机制说明）
整段追加到目标仓库的 `AGENTS.md`（有 `CLAUDE.md` 的话两份都贴）。
贴的时候把正文末尾的 `<工具包路径>` 换成 `$PKG` 的实际相对路径。

只贴代码块内容，不要把 snippet 文件顶部那段「> 把下面代码块里的内容粘贴到……」的说明一起贴进去。

## 8. 验收

```bash
bash "$PKG/scripts/selftest.sh"
FALLBACK_CHECK_STRICT=1 bash "$PKG/scripts/check-fallback.sh" full
```

- `selftest.sh` 期望结尾 `结果: PASS`（无 semgrep 的机器会退化成规则集结构校验 + 对账逻辑测试，仍应 PASS）。
- `full` 第一次在存量仓库上跑**大概率会红**，这是正常的——它照出了存量债。
  **不要**为了让它变绿去删规则、加裸 `nosemgrep`、或把命中项一股脑塞进白名单。
  正确动作：告诉用户「增量已拦住，存量需要清一轮」，然后引导他们跑 `fallback-audit` skill。

## 收尾报告给用户的内容

1. 落位路径 `$PKG`、白名单路径、改了哪几个仓库文件；
2. 第 3 步（Claude Code hook）是装了还是按 codex 场景跳过了；
3. 两条**必须由人完成**的动作：CI job 设为 required check、CODEOWNERS 里填真实 team；
4. 验收命令的实际输出（`full` 红的话，列出命中数量和 top 几个文件，并建议跑 `fallback-audit`）。

## 纪律

- 不要为了让检查通过而改规则集、放宽 semgrep 规则、或加裸 `nosemgrep`。
- 不要替用户编造 CODEOWNERS team 名、白名单的 `owner` / `approved_by` / `expires`。
- 目标仓库已有 `policy/fallbacks.yaml` 或 `.pre-commit-config.yaml` 时，**合并不覆盖**，
  覆盖前先给用户看 diff。
