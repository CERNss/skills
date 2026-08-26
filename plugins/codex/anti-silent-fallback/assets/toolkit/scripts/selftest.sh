#!/usr/bin/env bash
#
# selftest.sh —— 工具包自测
#
# 有 semgrep 时：
#   - 对 examples/ 跑规则集，断言 bad.* 每个文件至少命中一条、good.py 零命中；
#   - 断言规则集里每一条规则都至少被一个 example 命中（防止写了不生效的规则）。
# 无 semgrep 时：
#   - 用 python3 校验规则集 YAML 语法与结构（id 前缀 / 必填字段 / id 唯一）。
# 无论有无 semgrep，以下逻辑都要跑：
#   - 豁免对账（缺 fallback-key / key 未登记 / 裸 nosemgrep / 合规写法）
#   - 白名单对账（过期即 fail / test 标识缺失 warn，strict 下 fail）
#   - 极简 YAML 解析器降级路径（屏蔽 PyYAML 后仍能对账）
#   - hook 模式在 semgrep 缺失时的放行 + strict 阻断
#
# 用法: bash scripts/selftest.sh
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd -P "${SCRIPT_DIR}/.." && pwd)"
CHECK="${SCRIPT_DIR}/check-fallback.sh"
RULES="${PKG_DIR}/semgrep/silent-fallback.yaml"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fallback-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
SKIP=0
OUT=""
RC=0

ok()   { printf '  [PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
skip() { printf '  [SKIP] %s\n' "$*"; SKIP=$((SKIP + 1)); }
section() { printf '\n=== %s ===\n' "$*"; }

capture() {
    set +e
    OUT="$("$@" 2>&1)"
    RC=$?
    set -e
}

expect_rc() {
    # expect_rc <期望值> <用例名>
    if [ "$RC" -eq "$1" ]; then
        ok "$2 (exit=$RC)"
    else
        bad "$2 (期望 exit=$1，实际 $RC)"
        printf '%s\n' "$OUT" | sed 's/^/        | /'
    fi
}

expect_contains() {
    # expect_contains <子串> <用例名>
    if printf '%s' "$OUT" | grep -q -- "$1"; then
        ok "$2"
    else
        bad "$2 (输出中找不到 '$1')"
        printf '%s\n' "$OUT" | sed 's/^/        | /'
    fi
}

# --------------------------------------------------------------------------
# fixture：造一个最小仓库
#   $1 目录  $2 registry 内容标记(valid|expired|notest)  $3 代码内容标记
# --------------------------------------------------------------------------
write_registry() {
    local dir="$1" kind="$2" exp="2099-12-31"
    if [ "$kind" = "expired" ]; then
        exp="2020-01-01"
    fi
    mkdir -p "${dir}/policy"
    cat >"${dir}/policy/fallbacks.yaml" <<YAML
fallbacks:
  - key: cache-read-degrade
    module: app/profile
    trigger: TimeoutError from redis
    behavior: 回源查主库
    reason: 只读路径，缓存不是事实来源
    owner: profile-team
    approved_by: tech-lead
    approved_at: "2026-01-01"
    expires: "${exp}"
    test: test_fallback_cache_read_degrade
YAML
}

write_test_file() {
    # 让 registry 的 test 标识在仓库中可被找到
    mkdir -p "$1/app"
    cat >"$1/app/test_profile.py" <<'PY'
def test_fallback_cache_read_degrade():
    """故障注入：断言 redis 超时时回源且 degraded=True。"""
    assert True
PY
}

write_code() {
    # $1 dir, $2 = good|nokey|unregistered|bare
    mkdir -p "$1/app"
    case "$2" in
        good)
            cat >"$1/app/svc.py" <<'PY'
# fallback-key: cache-read-degrade
# nosemgrep: silent-fallback-python-broad-except-swallow
try:
    value = read_cache()
except Exception:
    value = None
PY
            ;;
        nokey)
            cat >"$1/app/svc.py" <<'PY'
# nosemgrep: silent-fallback-python-broad-except-swallow
try:
    value = read_cache()
except Exception:
    value = None
PY
            ;;
        unregistered)
            cat >"$1/app/svc.py" <<'PY'
# fallback-key: totally-made-up-key
# nosemgrep: silent-fallback-python-broad-except-swallow
try:
    value = read_cache()
except Exception:
    value = None
PY
            ;;
        bare)
            cat >"$1/app/svc.py" <<'PY'
# nosemgrep
try:
    value = read_cache()
except Exception:
    value = None
PY
            ;;
    esac
}

run_audit() {
    # run_audit <fixture 目录> <子命令> [strict]
    capture env \
        FALLBACK_REPO_ROOT="$1" \
        FALLBACK_REGISTRY="policy/fallbacks.yaml" \
        FALLBACK_CHECK_STRICT="${3:-0}" \
        bash "$CHECK" "$2"
}

# ==========================================================================
section "0. 脚本语法"
for s in "$CHECK" "${SCRIPT_DIR}/selftest.sh"; do
    capture bash -n "$s"
    expect_rc 0 "bash -n $(basename "$s")"
done
if command -v shellcheck >/dev/null 2>&1; then
    capture shellcheck -S error "$CHECK" "${SCRIPT_DIR}/selftest.sh"
    expect_rc 0 "shellcheck -S error"
else
    skip "shellcheck 未安装，跳过"
fi

# ==========================================================================
section "1. semgrep 规则集结构校验（不依赖 semgrep）"
capture python3 - "$RULES" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
try:
    import yaml
except ImportError:
    print("[SKIP] 无 PyYAML，只做非空检查")
    assert "rules:" in text
    sys.exit(0)

doc = yaml.safe_load(text)
rules = doc["rules"]
assert isinstance(rules, list) and rules, "rules 必须是非空列表"
ids = []
for r in rules:
    rid = r["id"]
    ids.append(rid)
    assert rid.startswith("silent-fallback-"), "规则 id 必须以 silent-fallback- 开头: %s" % rid
    assert r.get("message", "").strip(), "%s 缺 message" % rid
    assert r.get("severity") in ("ERROR", "WARNING", "INFO"), "%s severity 非法" % rid
    assert r.get("languages"), "%s 缺 languages" % rid
    assert any(k in r for k in ("pattern", "patterns", "pattern-either", "pattern-regex")), \
        "%s 没有任何 pattern" % rid
    msg = r["message"]
    assert ("fallbacks.yaml" in msg or "golangci-lint" in msg or "fail-fast" in msg), \
        "%s 的 message 没有给出修复指引" % rid
assert len(ids) == len(set(ids)), "规则 id 有重复"
print("规则数=%d ids=%s" % (len(ids), ",".join(ids)))
PYEOF
expect_rc 0 "规则集 YAML 语法与结构合法"
printf '        %s\n' "$OUT"

# ==========================================================================
section "2. examples/ 命中断言"
if command -v semgrep >/dev/null 2>&1; then
    JSON="${WORK}/examples.json"
    set +e
    semgrep --config "$RULES" --json --quiet --metrics=off \
        --disable-version-check --timeout 60 "${PKG_DIR}/examples" >"$JSON" 2>"${WORK}/semgrep.err"
    sg_rc=$?
    set -e
    if [ "$sg_rc" -gt 1 ]; then
        bad "semgrep 执行失败 (exit=$sg_rc)"
        sed 's/^/        | /' "${WORK}/semgrep.err"
    else
        capture python3 - "$JSON" "$RULES" "${PKG_DIR}/examples" <<'PYEOF'
import json, os, sys
results = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    import yaml
    all_ids = {r["id"] for r in yaml.safe_load(open(sys.argv[2], encoding="utf-8"))["rules"]}
except ImportError:
    all_ids = set()
ex = sys.argv[3]

by_file, hit_ids = {}, set()
for f in results.get("results", []):
    name = os.path.basename(f["path"])
    rid = f["check_id"].split(".")[-1]
    by_file.setdefault(name, set()).add(rid)
    hit_ids.add(rid)

errs = []
for name in ("bad.py", "bad.go", "bad.ts", "bad.php"):
    hits = by_file.get(name, set())
    if not hits:
        errs.append("%s 一条都没命中（规则失效或语言解析失败）" % name)
    else:
        print("  %-8s 命中 %d 条: %s" % (name, len(hits), ", ".join(sorted(hits))))
if by_file.get("good.py"):
    errs.append("good.py 出现命中（豁免标注失效）: %s" % sorted(by_file["good.py"]))
else:
    print("  %-8s 零命中（豁免标注生效）" % "good.py")
if all_ids:
    never = sorted(all_ids - hit_ids)
    if never:
        errs.append("以下规则没有被任何 example 命中: %s" % ", ".join(never))
for e in results.get("errors", []):
    errs.append("semgrep 报错: %s" % (e.get("message") or e))
if errs:
    for e in errs:
        print("  !! %s" % e)
    sys.exit(1)
print("  examples 命中断言全部通过")
PYEOF
        expect_rc 0 "examples 命中断言"
        printf '%s\n' "$OUT" | sed 's/^/      /'
    fi
else
    skip "semgrep 未安装：examples 命中断言无法执行（安装后重跑：pipx install semgrep）"
fi

# ==========================================================================
section "3. 豁免对账（不依赖 semgrep）"

FX="${WORK}/fx-ok"
write_registry "$FX" valid; write_test_file "$FX"; write_code "$FX" good
run_audit "$FX" audit-exemptions
expect_rc 0 "test_exemption_ok_passes: 合规豁免（key 在上、nosemgrep 在下）通过"

FX="${WORK}/fx-nokey"
write_registry "$FX" valid; write_code "$FX" nokey
run_audit "$FX" audit-exemptions
expect_rc 1 "test_exemption_key_missing_fails: 缺 fallback-key 被拦下"
expect_contains "缺少" "  └ 报错信息指出缺 fallback-key"

FX="${WORK}/fx-unreg"
write_registry "$FX" valid; write_code "$FX" unregistered
run_audit "$FX" audit-exemptions
expect_rc 1 "test_exemption_key_unregistered_fails: key 未登记被拦下"
expect_contains "totally-made-up-key" "  └ 报错信息点名未登记的 key"

FX="${WORK}/fx-bare"
write_registry "$FX" valid; write_code "$FX" bare
run_audit "$FX" audit-exemptions
expect_rc 1 "test_bare_nosemgrep_fails: 裸 nosemgrep 被拦下"

# ==========================================================================
section "4. 白名单对账（不依赖 semgrep）"

FX="${WORK}/fx-expired"
write_registry "$FX" expired; write_test_file "$FX"; write_code "$FX" good
run_audit "$FX" audit-registry
expect_rc 1 "test_registry_expired_fails: 过期降级被拦下"
expect_contains "过期" "  └ 报错信息说明已过期"

FX="${WORK}/fx-notest"
write_registry "$FX" valid; write_code "$FX" good   # 故意不写测试文件
run_audit "$FX" audit-registry
expect_rc 0 "test_registry_missing_test_warns: 非 strict 下 test 缺失只 warn"
expect_contains "WARN" "  └ 输出中有 WARN"
run_audit "$FX" audit-registry 1
expect_rc 1 "test_registry_missing_test_strict_fails: strict 下 test 缺失变 fail"

FX="${WORK}/fx-ok"
run_audit "$FX" audit-registry 1
expect_rc 0 "完整合规 fixture 在 strict 下也通过"

FX="${WORK}/fx-badfield"
write_registry "$FX" valid
python3 - "$FX/policy/fallbacks.yaml" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read().replace("    owner: profile-team\n", "")
open(p, "w", encoding="utf-8").write(s)
PYEOF
write_test_file "$FX"
run_audit "$FX" audit-registry
expect_rc 1 "缺必填字段 owner 被拦下"

# ==========================================================================
section "5. YAML 极简解析器降级路径"
STUB="${WORK}/pystub"
mkdir -p "$STUB"
cat >"${STUB}/yaml.py" <<'PY'
raise ImportError("selftest: PyYAML 被屏蔽，用于验证极简解析器降级路径")
PY
FX="${WORK}/fx-ok"
set +e
OUT="$(env PYTHONPATH="$STUB" FALLBACK_REPO_ROOT="$FX" \
    FALLBACK_REGISTRY="policy/fallbacks.yaml" \
    bash "$CHECK" audit-registry 2>&1)"
RC=$?
set -e
expect_rc 0 "test_registry_parses_without_pyyaml: 无 PyYAML 时对账仍通过"
expect_contains "parser=minimal(builtin)" "  └ 确实走了极简解析器"

# 同时验证极简解析器能吃下带块标量的模板文件
set +e
OUT="$(env PYTHONPATH="$STUB" FALLBACK_REPO_ROOT="$PKG_DIR" \
    FALLBACK_REGISTRY="policy/fallbacks.example.yaml" \
    bash "$CHECK" audit-registry 2>&1)"
RC=$?
set -e
expect_rc 0 "极简解析器能解析模板 fallbacks.example.yaml（含 >- 块标量）"
expect_contains "条目=3" "  └ 解析出 3 条白名单"

# ==========================================================================
section "6. hook 模式"
HOOK_JSON='{"tool_name":"Edit","tool_input":{"file_path":"'"${FX}"'/app/svc.py"}}'

# 6.1 非代码文件直接放行
capture env FALLBACK_REPO_ROOT="$FX" bash "$CHECK" hook <<< '{"tool_name":"Write","tool_input":{"file_path":"/etc/hosts"}}'
expect_rc 0 "hook: 非代码文件放行"

# 6.2 不存在的文件放行
capture env FALLBACK_REPO_ROOT="$FX" bash "$CHECK" hook <<< '{"tool_name":"Edit","tool_input":{"file_path":"/nope/nope.py"}}'
expect_rc 0 "hook: 文件不存在放行"

# 6.3 空 JSON / 无 file_path 放行
capture env FALLBACK_REPO_ROOT="$FX" bash "$CHECK" hook <<< '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
expect_rc 0 "hook: 无 file_path 放行"

# 6.4 semgrep 缺失时的降级放行 / strict 阻断
MINPATH="/usr/bin:/bin:/usr/sbin:/sbin"
if PATH="$MINPATH" command -v semgrep >/dev/null 2>&1; then
    skip "test_hook_semgrep_missing_warns: 最小 PATH 下仍能找到 semgrep，无法构造缺失场景"
else
    set +e
    OUT="$(env PATH="$MINPATH" FALLBACK_REPO_ROOT="$FX" \
        bash "$CHECK" hook <<< "$HOOK_JSON" 2>&1)"
    RC=$?
    set -e
    expect_rc 0 "test_hook_semgrep_missing_warns: semgrep 缺失时放行（已登记降级）"
    expect_contains "check-script-semgrep-missing" "  └ 警告里点名了白名单 key"

    set +e
    OUT="$(env PATH="$MINPATH" FALLBACK_REPO_ROOT="$FX" FALLBACK_CHECK_STRICT=1 \
        bash "$CHECK" hook <<< "$HOOK_JSON" 2>&1)"
    RC=$?
    set -e
    expect_rc 2 "test_hook_semgrep_strict_blocks: STRICT=1 时改为阻断 (exit 2)"
fi

# 6.5 有 semgrep 时，编辑违规文件应被打回
if command -v semgrep >/dev/null 2>&1; then
    VIOL="${WORK}/viol.py"
    printf 'try:\n    x = f()\nexcept Exception:\n    x = None\n' >"$VIOL"
    printf 'try:\n    x = f()\nexcept Exception:\n    pass\n' >"$VIOL"
    capture env FALLBACK_REPO_ROOT="$FX" bash "$CHECK" hook <<< '{"tool_name":"Edit","tool_input":{"file_path":"'"$VIOL"'"}}'
    expect_rc 2 "hook: 违规文件被打回 (exit 2)"
    expect_contains "fallback-key" "  └ stderr 里给了修法指引"
else
    skip "hook 命中路径需要 semgrep"
fi

# ==========================================================================
section "汇总"
printf '  PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -ne 0 ]; then
    printf '  结果: FAIL\n'
    exit 1
fi
printf '  结果: PASS\n'
exit 0
