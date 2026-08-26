---
name: fallback-selfcheck
description: codex 侧的「穷人版 hook」——改完代码、结束回合交付前主动跑 check-fallback.sh diff，把自己刚写出的静默降级（吞异常返默认值、空 catch、if err != nil 返回 nil、PHP @ 抑制符）当场揪出来修掉。当用户说「交付前自检 / 跑降级检查 / 查一下有没有静默 fallback / 提交前检查 / check fallback」时使用；在已接入本工具包的仓库里改完代码后也应主动执行。
---

# 交付前自检：check-fallback.sh diff

Claude Code 有 `PostToolUse` hook，编辑完立刻被打回。**codex 没有这个机制**，
所以这一层只能靠自觉：**改完代码、结束回合之前，主动跑一次。**

跳过它的代价不是「少跑一个命令」，而是把静默降级带进了 pre-commit 和 CI ——
那两层是 fail-closed 的，最终一样要修，只是反馈晚了几十分钟。

## 何时跑

- 在目标仓库改动了 `.py .pyi .go .js .jsx .mjs .cjs .ts .tsx .php` 任一文件之后；
- 结束回合、向用户交付之前；
- 用户明确要求「提交前检查一下」时。

纯文档 / 配置 / YAML 改动可以跳过（脚本自己也会按后缀过滤，跑了也是 exit 0）。

## 怎么跑

### 情况 A：仓库已接入工具包（优先）

先找仓库里的落位（约定路径是 `tools/anti-silent-fallback/`，也可能被改过）：

```bash
REPO="$(git rev-parse --show-toplevel)"
PKG="$(find "$REPO" -maxdepth 4 -type f -path '*/anti-silent-fallback/scripts/check-fallback.sh' \
        -not -path '*/node_modules/*' | head -1 | xargs -r dirname | xargs -r dirname)"
echo "$PKG"
```

找到就直接跑（白名单、规则集都用仓库自己的，无需额外配环境变量）：

```bash
bash "$PKG/scripts/check-fallback.sh" diff
```

### 情况 B：仓库没接入（用 plugin 自带的正本）

本 skill 的 **base directory**（即本 `SKILL.md` 所在目录）上两级是 plugin 根，
工具包正本在 `assets/toolkit/`：

```bash
# 把 <base directory> 换成 codex 给出的绝对路径
TOOLKIT="$(cd "<base directory>/../../assets/toolkit" && pwd)"
```

拿不到 base directory 就退到默认安装位置 `~/plugins/anti-silent-fallback/assets/toolkit`。

跑的时候必须把 `FALLBACK_REGISTRY` 指向**目标仓库**的白名单，
否则对账会去读 plugin 自己的示例白名单，结论是假的：

```bash
REPO="$(git rev-parse --show-toplevel)"
FALLBACK_REGISTRY="$REPO/policy/fallbacks.yaml" \
FALLBACK_REPO_ROOT="$REPO" \
  bash "$TOOLKIT/scripts/check-fallback.sh" diff
```

仓库连 `policy/fallbacks.yaml` 都没有（说明完全没接入）→ 这次只是粗筛，
跑完在交付说明里加一句「本仓库尚未接入拦截机制，建议跑 `fallback-onboard`」。

## 读结果

| 退出码 | 含义 | 动作 |
| --- | --- | --- |
| 0 | 无命中 | 正常交付 |
| 1 | 有命中 | **当场修，修完重跑，直到 0 再交付** |
| 其它 | 脚本自身出错（semgrep 缺失、git 不可用等） | 在交付说明里如实报告，不要假装跑过了 |

`diff` 模式检查 git staged 文件；没有 staged 内容时退回 `git diff --name-only HEAD`。
所以刚改完还没 `git add` 也能查出来。

**semgrep 缺失时 `diff` 模式是硬失败**，不放行——这是刻意设计（「本地没装工具」不能成为
把静默降级提交进仓库的理由）。装法：`pip install semgrep` 或 `uvx semgrep`。

## 命中之后怎么修

按优先级：

1. **让它报错。** 配置 / 凭据 / 前置链路失败，直接抛出去，保留原始 error
   （Go `fmt.Errorf("...: %w", err)`，Python `raise ... from exc`）。绝大多数命中都该这么修。
2. **走统一降级入口。** 确实需要降级 → `fallback.Run(ctx, key, primary, degraded)` /
   `fallback.run(key, primary, degraded, expected=(...))`，key 必须先登记进 `policy/fallbacks.yaml`。
3. **登记豁免**（前两条都不适用时）。写两行注释，顺序不可颠倒：

   ```python
   # fallback-key: cache-read-degrade
   # nosemgrep: silent-fallback-python-broad-except-swallow
   try:
       ...
   ```

   `nosemgrep` 必须紧贴命中起始行，`fallback-key` 只能写在它的**上一行**——
   插在中间会让 `nosemgrep` 失效，这是最容易犯的错。

## 禁止事项（这条比上面所有内容都重要）

- **禁止用 `nosemgrep` 来「修」命中。** 加豁免不是修 bug，是申请一次例外，
  必须同时把 key 登记进 `policy/fallbacks.yaml`（含 owner / approved_by / expires / test），
  而那个文件受 CODEOWNERS 保护 —— 所以豁免只能由**用户**去走 PR 审批，
  codex 可以起草条目，但不能替用户拍板、也不能编造 owner / 到期日。
- **禁止裸 `nosemgrep`**（不指名规则 id）：它一次性关掉所有规则，对账阶段直接判违规。
- **禁止**为了让检查变绿去删报错、放宽 `except` 类型、改测试断言、改规则集、
  或把 `FALLBACK_CHECK_STRICT` 关掉。这些都算故意破坏，比原来的 bug 严重。
- 改不动、或不确定这处降级该不该保留 → **停下来问用户**，把两种改法的后果讲清楚，
  不要自行拍板。

## 交付说明里怎么写

跑完在回复里给一行结论，别默默跑完就完事：

- 通过：`降级自检: check-fallback.sh diff 通过（0 命中）`
- 修过：`降级自检: 初次 N 处命中，已改为 <抛错 / 走统一入口>，重跑 0 命中`
- 没跑成：`降级自检: 未能执行（原因），请手动跑 <命令>`

第三种情况必须如实写。谎报「已自检」本身就是一次静默降级。
