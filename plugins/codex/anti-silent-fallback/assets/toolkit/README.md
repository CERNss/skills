# 反静默降级 / 过度防御拦截工具包

治理 AI 编码工具（Claude Code / codex）和人写出的**静默 fallback**：吞掉异常返回默认值、
把配置错误降级成「看起来正常」、失败时伪造数据继续跑。

核心判断：**只在 `AGENTS.md` 里写规则是不够的**——模型会忘、人会赶工期。
所以这个工具包把约束从「嘱咐」下沉成「机器可执行的拦截」。

> 这是一个**模板库**，不是业务仓库。按下面的 checklist 把需要的文件拷到目标仓库
> （Go / Python / PHP / TS 混合仓库都可以，按需取用）。

---

## 一、五层机制一览

| 层 | 载体 | 拦截时机 | 能否绕过 | 作用 |
| --- | --- | --- | --- | --- |
| ① 嘱咐层 | `prompts/agents-md-snippet.md` → 目标仓库 `AGENTS.md` / `CLAUDE.md` | 模型生成代码前 | 极易（模型会忘） | 降低违规产出率，但**不能当作保障** |
| ② 代码结构层 | `templates/go/fallback/fallback.go`、`templates/python/fallback.py` | 运行时 | 需要主动绕开入口 | 统一降级入口；未注册 key 直接 panic；`degraded` 状态显式返回 |
| ③ 静态拦截层 | `semgrep/silent-fallback.yaml` + `policy/fallbacks.yaml` | 扫描时 | 需要写豁免（留痕） | 把「什么算违规」变成机器可判定；豁免必须带 key 且登记白名单 |
| ④ 硬阻断层 | `scripts/check-fallback.sh`（hook / pre-commit / CI） | 编辑后 / 提交前 / 合并前 | hook 可关、pre-commit 可 `--no-verify`、**CI 不可绕** | 真正的强制点 |
| ⑤ 测试层 | 白名单 `test` 字段 + 故障注入测试 | CI | 不可绕 | 保证「降级路径真的能工作」，而不是写了个从没跑过的兜底 |

三个阻断点的严格程度是**故意不同**的：

| 场景 | semgrep 命中 | semgrep 未安装 |
| --- | --- | --- |
| `hook`（编辑后） | exit 2，编辑被打回，stderr 喂回模型 | **告警放行**（已登记的降级，见第五节） |
| `diff`（pre-commit） | exit 1，提交被拦 | 直接失败 |
| `full`（CI，`FALLBACK_CHECK_STRICT=1`） | exit 1，合并被拦 | 直接失败 |

---

## 二、接入一个新仓库的 checklist

假设工具包在目标仓库里落位于 `tools/anti-silent-fallback/`（路径可自定，下文占位记作 `<PKG>`）。

### 1. 拷文件

```bash
TARGET=/path/to/your-repo
PKG="$TARGET/tools/anti-silent-fallback"

mkdir -p "$PKG"
cp -R semgrep scripts examples "$PKG"/            # 规则集 + 脚本 +（可选）样例
mkdir -p "$TARGET/policy"
cp policy/fallbacks.example.yaml "$TARGET/policy/fallbacks.yaml"   # 白名单落到仓库根 policy/
```

| 拷什么 | 拷到哪 | 必需？ |
| --- | --- | --- |
| `semgrep/silent-fallback.yaml` | `<PKG>/semgrep/` | 必需 |
| `scripts/check-fallback.sh` | `<PKG>/scripts/` | 必需 |
| `scripts/selftest.sh` | `<PKG>/scripts/` | 建议（升级规则集后自测） |
| `policy/fallbacks.example.yaml` | **仓库根 `policy/fallbacks.yaml`** | 必需（重命名） |
| `templates/go/fallback/fallback.go` | `internal/fallback/fallback.go` | 有 Go 代码则必需 |
| `templates/python/fallback.py` | `<yourapp>/fallback.py` | 有 Python 代码则必需 |
| `examples/` | `<PKG>/examples/` | 可选（`full` 模式会自动排除它） |
| `prompts/agents-md-snippet.md` 的正文 | `AGENTS.md` / `CLAUDE.md` | 必需 |

### 2. 改占位符

| 文件 | 占位符 | 改成 |
| --- | --- | --- |
| `hooks/claude-settings.snippet.json` | `tools/anti-silent-fallback/` | `<PKG>` 的实际相对路径 |
| `hooks/pre-commit-config.snippet.yaml` | 同上 | 同上 |
| `ci/github-actions.snippet.yml` | 同上 | 同上 |
| `prompts/agents-md-snippet.md` | `<工具包路径>` | `<PKG>` |
| `templates/go/fallback/go.mod` | 整个文件 | **删掉**（它只是让工具包内自测能独立 `go build`） |
| `templates/go/fallback/fallback.go` | import 路径 | 宿主 module 路径 |
| `policy/fallbacks.yaml` | 三条示例条目 | 换成本仓库真实条目；`check-script-*` 两条**保留**（它们描述的是脚本自身行为） |

### 3. 装 hook（Claude Code，编辑即拦）

把 `hooks/claude-settings.snippet.json` 里的 `hooks` 键合并进
`.claude/settings.json`（团队共享）或 `.claude/settings.local.json`（只影响自己），
删掉 `_README` / `_comment` 键。验证：

```bash
echo '{"tool_input":{"file_path":"'"$PWD"'/some_file.py"}}' \
  | bash tools/anti-silent-fallback/scripts/check-fallback.sh hook ; echo "exit=$?"
```

### 4. 装 pre-commit（提交即拦）

把 `hooks/pre-commit-config.snippet.yaml` 合并进 `.pre-commit-config.yaml`，然后：

```bash
pip install pre-commit && pre-commit install
pre-commit run anti-silent-fallback --all-files
```

### 5. 接 CI（唯一不可绕过的一层）

把 `ci/github-actions.snippet.yml` 合并进 `.github/workflows/`，
并把这个 job 设成**分支保护的 required check**。CI 里必须 `FALLBACK_CHECK_STRICT=1`。

### 6. 保护白名单（关键，别跳过）

`.github/CODEOWNERS` 加一行，让「改白名单」= 「走审批」：

```
/policy/fallbacks.yaml    @your-org/tech-leads @your-org/sre
```

没有这一步，白名单就是个人人可写的许愿池，整套机制退化成摆设。

### 7. 存量清理（可选但强烈建议）

把 `prompts/audit-silent-fallback.md` 的正文喂给 Claude Code / codex 跑一轮存量审计。
它会同时产出：审计报告、针对本仓库的 semgrep 规则草稿、白名单初稿、PR 拆分建议。
**增量靠拦截，存量靠这一轮审计**，两者缺一不可。

### 8. 验收

```bash
bash tools/anti-silent-fallback/scripts/selftest.sh       # 工具包自测
FALLBACK_CHECK_STRICT=1 bash tools/anti-silent-fallback/scripts/check-fallback.sh full
```

---

## 三、豁免标注约定（务必按顺序写）

确实需要保留一处降级、又无法走统一入口时，写**两行注释**：

```python
# fallback-key: cache-read-degrade
# nosemgrep: silent-fallback-python-broad-except-swallow
try:
    ...
except Exception:
    return None
```

```go
// fallback-key: obs-lock-empty
// nosemgrep: silent-fallback-go-nilerr
if err != nil {
    return nil, nil
}
```

规则（`check-fallback.sh audit-exemptions` 会逐条校验）：

1. `nosemgrep` 注释必须**紧贴命中的起始行**。semgrep 只认「同一行」或「紧邻的上一行」；
   Python `try/except` 的命中起始行是 `try:`，Go 是 `if err != nil {`。
2. 所以 `fallback-key` 只能写在 `nosemgrep` 的**上一行**。
   把它插在 `nosemgrep` 和代码之间会让 `nosemgrep` 失效——这是最容易犯的错。
   对账逻辑接受 `fallback-key` 出现在 `nosemgrep` 的同一行、上一行或下一行，
   但只有「上一行」这一种写法能同时满足 semgrep 的解析要求。
3. **禁止裸 `nosemgrep`**（不指名规则 id）：它会一次性关掉所有规则，对账阶段直接判违规。
4. `fallback-key` 的值必须存在于 `policy/fallbacks.yaml`，否则 CI 红。

---

## 四、语言矩阵：semgrep 之外的补充 linter

semgrep 规则刻意写得窄（低误报优先），覆盖不到的部分交给各语言的专业 linter。

### Go — golangci-lint

`nilerr` 才是 `if err != nil { return nil }` 的完整覆盖者（做数据流分析，semgrep 只能命中最直白的写法）。

```yaml
# .golangci.yml
linters:
  enable:
    - errcheck    # 未检查的 error 返回值
    - errorlint   # %v 包装 error、类型断言不用 errors.As
    - nilerr      # err != nil 却返回 nil error  ★ 核心
    - bodyclose
linters-settings:
  errcheck:
    check-type-assertions: true
    check-blank: true          # 连 _ = f() 也要管
issues:
  exclude-use-default: false
```

### Python — ruff

```toml
# pyproject.toml
[tool.ruff.lint]
select = [
  "E722",   # 裸 except:
  "BLE001", # 捕获宽泛异常（blind except）  ★ 核心
  "S110",   # try-except-pass
  "S112",   # try-except-continue
  "TRY400", # 该用 logging.exception 的地方用了 logging.error（丢 traceback）
  "B904",   # except 里 raise 没带 from（丢异常链）
]
[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S110"]   # 测试里断言异常的写法可放宽
```

### TypeScript / JavaScript — ESLint

```js
// eslint.config.js
rules: {
  "no-empty": ["error", { allowEmptyCatch: false }],  // ★ 空 catch
  "no-useless-catch": "error",
  "@typescript-eslint/no-floating-promises": "error", // 未 await 的 promise = 静默失败
  "@typescript-eslint/no-unnecessary-condition": "warn",
}
```

### PHP — PHPStan / Psalm

PHP 生态里没有和 `nilerr` 对等的「空 catch」检查器，**这一块主要靠本工具包的 semgrep 规则**。
补充手段：

```neon
# phpstan.neon
parameters:
    level: 6
    checkUninitializedProperties: true
includes:
    - vendor/phpstan/phpstan-strict-rules/rules.neon   # 禁止松散比较、要求显式类型
```

```xml
<!-- psalm.xml：把「可能为 null 继续用」这类静默传播升级为 error -->
<issueHandlers>
  <PossiblyNullReference errorLevel="error"/>
  <PossiblyNullArgument errorLevel="error"/>
  <NullArgument errorLevel="error"/>
</issueHandlers>
```

另外在 PHP 项目里建议全局 `set_error_handler` 把 warning/notice 转成异常，
从根上消灭 `@` 抑制符存在的理由。

---

## 五、设计取舍（为什么是现在这样）

### 1. hook 模式下 semgrep 未安装 → 告警放行，而不是阻塞

这是整个工具包里**最容易被质疑**的一条决定，所以它本身就被登记在
`policy/fallbacks.example.yaml` 里，作为「一条白名单该怎么写」的示范
（`key: check-script-semgrep-missing`）。

理由：

- hook 是**开发期辅助**，semgrep 是可选重依赖。若在这里 fail-closed，
  新同事 clone 完仓库会被卡到一行代码都改不了，**结果必然是整条 hook 被摘掉**——
  那才是真正的、永久的静默失效。
- 这次放行不会让问题逃逸出仓库：`diff`（pre-commit）和 `full`（CI）两处都是 fail-closed。
  hook 只是把反馈提前，不是唯一防线。
- 放行时会打印**非常显眼**的多行警告，并点名白名单 key，让人知道「现在是没有保护的」。
- 提供逃生阀：`FALLBACK_CHECK_STRICT=1` 可以把 hook 也切成 fail-closed。

**用工具包自身的降级决策，示范一次「合规的降级长什么样」**：有 key、有理由、有到期日、
有 owner、有测试（`selftest.sh` 里的 `test_hook_semgrep_missing_warns`）、有逃生阀。

### 2. 反例：`jq`/`python3` 都缺失时是**硬阻断**（exit 2），不放行

同样是「工具缺失」，处理却相反。区别在于：semgrep 缺失时机制**还有后续防线**，
而两个 JSON 解析器都没有意味着 hook 永远不可能工作、且**没有任何提示**——
静默放行会让整层拦截变成看不见的摆设。
这条对比本身就是「什么该降级、什么不该降级」的教学案例。

### 3. 白名单 `expires` 必填

降级是**欠的技术债**，不是永久设施。到期未续期 → CI 红 → 强制复审一次
「这个降级还需要吗 / 根因修了吗」。没有到期日的白名单会在两年内长成一份没人敢删的遗产。

### 4. registry 用编译期/导入期注册，不读 YAML

Go 和 Python 的 helper 都在代码里 `Register("key")`，而不是启动时解析 `fallbacks.yaml`。
理由：零依赖、启动即校验，更重要的是**审批就近性**——
如果代码从 YAML 读注册表，那么改 YAML 就能悄悄给一段代码开降级权限，而代码 diff 里毫无变化。
两份数据的漂移由 CI 对账兜底（并建议在仓库里加一个断言 `Registered()` ⊆ YAML keys 的测试）。

### 5. Python helper 的 `expected` 是必填参数

一个专治「宽泛 except」的工具，自己默认 `except Exception` 就是把要治的病写进处方。
强制写出 `expected=(TimeoutError, ConnectionError)`，是逼作者当场回答
「到底什么失败才配降级」。

### 6. PHP 规则用 `generic` + 正则，不用 PHP AST 模式

semgrep 的 PHP 解析器成熟度不如 Python/Go/TS。一条 AST 模式若在某个 semgrep 版本上解析失败，
**整个规则文件会连带失效**，所有语言的拦截静默消失——那本身就是一次静默降级。
正则规则牺牲一点精度，换取「永远不会因为解析器而整体失灵」。

### 7. 豁免标注拆成两行，而不是行尾追加

semgrep 把 `nosemgrep:` 之后的内容按逗号切分当作规则 id 列表，行尾追加其它文字有破坏解析的风险。
**本工具包的开发机上没有安装 semgrep，无法实测该行为**，因此采用保守的两行写法。
若你的环境有 semgrep 并实测「同一行追加 `fallback-key:` 不影响抑制」，可以简化成一行——
对账逻辑已经兼容同一行的写法。**在拿到实测证据之前不放宽**，这条纪律和本工具包要治的病是同一件事。

### 8. `or ""` / 多层 `.get()` 回退没有做成阻断规则

误报太高（正常代码里大量存在），做成规则只会让人整体关掉 semgrep。
这类模式留在 `prompts/audit-silent-fallback.md` 的检索清单里，由**人+AI 的存量审计**判定。
拦截层只放低误报规则，这是它能长期活下来的前提。

---

## 六、目录说明

```
codex-prompt/
├── README.md                              本文件
├── prompts/
│   ├── audit-silent-fallback.md           存量审计 prompt（产出报告+规则草稿+白名单初稿）
│   └── agents-md-snippet.md               贴进 AGENTS.md / CLAUDE.md 的规则片段（嘱咐层）
├── semgrep/
│   └── silent-fallback.yaml               9 条跨语言规则（py/go/js-ts/php）
├── policy/
│   └── fallbacks.example.yaml             白名单模板（拷成目标仓库 policy/fallbacks.yaml）
├── scripts/
│   ├── check-fallback.sh                  统一入口：hook / diff / full / audit-*
│   └── selftest.sh                        自测：规则命中断言 + 对账逻辑 + hook 降级路径
├── hooks/
│   ├── claude-settings.snippet.json       Claude Code PostToolUse hook 配置片段
│   └── pre-commit-config.snippet.yaml     pre-commit local hook 片段
├── ci/
│   └── github-actions.snippet.yml         CI job（STRICT=1，fail-closed）
├── templates/
│   ├── go/fallback/fallback.go            Go 统一降级入口（泛型 Run）
│   └── python/fallback.py                 Python 统一降级入口（FallbackResult）
└── examples/
    ├── bad.py / bad.go / bad.ts / bad.php 反面样例，每条规则至少被一个文件命中
    └── good.py                            正面样例，零命中（统一入口 + 合规豁免标注）
```

### `check-fallback.sh` 子命令

| 子命令 | 用途 | 命中时退出码 |
| --- | --- | --- |
| `hook` | 读 Claude Code PostToolUse JSON，检查单文件 | 2（编辑被打回） |
| `diff` | 检查 git staged（或 `HEAD` diff）文件 | 1 |
| `full` | CI 全量：semgrep 扫描 + 豁免对账 + 白名单对账 | 1 |
| `audit-exemptions` | 只跑豁免对账（调试/自测用） | 1 |
| `audit-registry` | 只跑白名单对账（调试/自测用） | 1 |

### 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `FALLBACK_CHECK_STRICT` | `0` | `1` = 全面 fail-closed（CI 必设） |
| `FALLBACK_REGISTRY` | `policy/fallbacks.yaml` | 白名单路径（相对仓库根或绝对路径） |
| `FALLBACK_SEMGREP_CONFIG` | `<PKG>/semgrep/silent-fallback.yaml` | 规则集路径 |
| `FALLBACK_REPO_ROOT` | `git rev-parse --show-toplevel`，失败则 `$PWD` | 扫描根目录 |
| `FALLBACK_EXCLUDE` | 空 | 额外排除目录，空格分隔 |

---

## 七、测试层：故障注入

白名单每条的 `test` 字段指向一个**故障注入测试**标识，CI 会在仓库里 grep 它
（找不到默认 warn，`FALLBACK_CHECK_STRICT=1` 时 fail）。这一层回答的是：
「这条降级路径**真的能工作**吗，还是写完就没跑过？」

最小写法：

```python
# test_fallback_cache_read_degrade
def test_fallback_cache_read_degrade(monkeypatch):
    def boom():
        raise TimeoutError("redis down")
    result = fallback.run("cache-read-degrade", boom, lambda: {"src": "db"},
                          expected=(TimeoutError,))
    assert result.degraded is True                 # 降级事实必须可观测
    assert isinstance(result.cause, TimeoutError)  # 原始异常必须保留
    assert result.value == {"src": "db"}
```

```go
// TestFallback_cache_read_degrade
func TestFallback_cache_read_degrade(t *testing.T) {
    var seen error
    fallback.OnFallback = func(key string, cause error) { seen = cause }
    v, degraded, err := fallback.Run(context.Background(), "cache-read-degrade",
        func() (string, error) { return "", errors.New("redis down") },
        func() string { return "from-db" })
    if !degraded || v != "from-db" || seen == nil || !errors.Is(err, ...) {
        t.Fatal("降级路径没按预期工作")
    }
}
```

三条断言缺一不可：**降级发生了**、**原始错误保住了**、**兜底值是对的**。

---

## 八、常见反问

**Q：这会不会把正常的错误处理也拦下来？**
规则刻意写得窄，只拦「分支体里什么都不做 / 只返回字面量默认值」的写法。
`except X: logger.exception(...); raise` 不会命中，`if err != nil { return nil, fmt.Errorf(...) }` 不会命中。

**Q：模型被打回后会不会自己加个 `nosemgrep` 绕过去？**
会——所以 `nosemgrep` 必须带 `fallback-key`，key 必须在白名单里，白名单由 CODEOWNERS 保护。
模型可以写豁免，但写不进审批。这正是「把约束下沉」的意义：让绕过的成本高于修复的成本。

**Q：规则改坏了怎么办？**
`bash scripts/selftest.sh`。它会断言每条规则至少被一个 example 命中、`good.py` 零命中，
并在无 semgrep 的机器上退化为规则集结构校验 + 全套对账逻辑测试。

---

## 九、Codex plugin 分发

**本仓库的这个目录（`prompts/codex/anti-silent-fallback/`）是工具包的唯一源头。**
plugin 分发壳在同仓库的 `plugins/codex/anti-silent-fallback/`，安装位置是
`~/plugins/anti-silent-fallback`（含 `fallback-onboard` / `fallback-audit` /
`fallback-selfcheck` 三个 skill，工具包整份拷贝在 plugin 的 `assets/toolkit/`）。

**同步是单向的：本目录 → plugin。** 改完这里之后跑：

```bash
FALLBACK_TOOLKIT_SOURCE=<skills checkout>/prompts/codex/anti-silent-fallback \
  bash ~/plugins/anti-silent-fallback/scripts/sync-from-source.sh
```

`FALLBACK_TOOLKIT_SOURCE` 指向本机 skills checkout 里的这个目录——
分发出去的拷贝里不写死任何机器的绝对路径。
