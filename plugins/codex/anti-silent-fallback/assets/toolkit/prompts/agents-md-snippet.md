# AGENTS.md / CLAUDE.md 规则片段

> 把下面代码块里的内容粘贴到目标仓库的 `AGENTS.md` 或 `CLAUDE.md`。
> **注意：这一段只是第一道「嘱咐层」，模型和人都可能忘。真正的强制在 hook / pre-commit / CI**
> （`scripts/check-fallback.sh`），改这段文字不会改变拦截行为，反之亦然。

```markdown
## 降级与错误处理（硬性规则）

1. **禁止未注册的降级。** 任何「失败时返回默认值 / 空值 / 缓存 / 本地模式」的行为，
   都必须先在 `policy/fallbacks.yaml` 登记一个 key（含 trigger / behavior / reason /
   owner / approved_by / expires / test），未登记的降级一律视为 bug。
2. **必须走统一入口。** Go 用 `fallback.Run(ctx, key, primary, degraded)`，
   Python 用 `fallback.run(key, primary, degraded, expected=(...))`。
   未注册的 key 会直接 panic / 抛 `UnregisteredFallbackError`。
3. **必须保留原始 error。** 向上传递时用 `fmt.Errorf("...: %w", err)` /
   `raise ... from exc`；禁止把异常替换成布尔值、`None`、空 dict/list。
4. **禁止这些写法**：裸 `except:`、`except Exception` 后只 `pass`/`return 默认值`、
   空 `catch {}`、`if err != nil { return nil }`、PHP 的 `@` 抑制符、
   凭据/端点类环境变量带默认值的 `os.getenv("X_API_KEY", "...")`。
   配置缺失就让它崩在启动阶段。
5. **豁免需要 key + 标注。** 确实无法走统一入口时，写两行注释（顺序不可颠倒）：
       # fallback-key: <白名单里的 key>
       # nosemgrep: <具体规则 id>        <- 必须紧贴命中起始行
   禁止裸 `nosemgrep`（不指名规则 id）。
6. **降级从不免费。** 每次降级必须留下：结构化日志（含原始 error）、
   `fallback_degraded_total{key}` 指标、以及返回给调用方的 `degraded` 标志。
7. **不要为了让检查通过而绕过检查。** 删报错、放宽异常类型、加 `# type: ignore`、
   改测试断言、加裸豁免——这些都算故意破坏，比原来的 bug 严重。
   改不动就停下来问人。

> 强制机制：`scripts/check-fallback.sh`（PostToolUse hook / pre-commit / CI）。
> 规则与模板见 `<工具包路径>/`（例如 `tools/anti-silent-fallback/`）：
> `semgrep/silent-fallback.yaml`、`policy/fallbacks.example.yaml`、`templates/`。
```
