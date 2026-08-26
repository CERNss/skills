#!/usr/bin/env bash
#
# check-fallback.sh —— 反静默降级统一检查入口
#
# 子命令：
#   hook              从 stdin 读 Claude Code PostToolUse hook 的 JSON，对被编辑的单个文件跑
#                     semgrep。命中 → stderr 输出 + exit 2（Claude Code 会把编辑打回并把 stderr
#                     喂回模型，让它自己改）。文件不存在/非代码文件 → exit 0。
#   diff              对 git staged 文件（无 staged 则退回 `git diff --name-only HEAD`）跑
#                     semgrep，供 pre-commit 用。此模式 semgrep 缺失 = 硬失败。
#   full              CI 全量。三步：
#                       (a) 全仓库 semgrep 扫描
#                       (b) 豁免对账：每处 silent-fallback-* 的 nosemgrep 必须带 fallback-key，
#                           且该 key 必须在白名单里
#                       (c) 白名单对账：expires 未过期 + test 标识能在仓库里找到
#   audit-exemptions  只跑 (b)，供自测/调试
#   audit-registry    只跑 (c)，供自测/调试
#
# 环境变量：
#   FALLBACK_CHECK_STRICT=1   把「可降级」的检查点全部切成 fail-closed：
#                             hook 模式下 semgrep 缺失由放行改为 exit 2；
#                             白名单 test 标识找不到由 warn 改为 fail。CI 里应当设为 1。
#   FALLBACK_REGISTRY         白名单路径，默认 policy/fallbacks.yaml（相对仓库根）
#   FALLBACK_SEMGREP_CONFIG   规则集路径，默认 <本工具包>/semgrep/silent-fallback.yaml
#   FALLBACK_REPO_ROOT        仓库根，默认 git rev-parse --show-toplevel，失败则用 $PWD
#   FALLBACK_EXCLUDE          额外排除目录，空格分隔
#
# ---------------------------------------------------------------------------
# 豁免标注约定（顺序不可颠倒）
#
#   Python:                            Go / TS / PHP:
#     # fallback-key: cache-read        // fallback-key: cache-read
#     # nosemgrep: silent-fallback-...  // nosemgrep: silent-fallback-...
#     try:                              if err != nil {
#
#   1) `nosemgrep` 注释必须紧贴命中的**起始行**（Python try/except 的起始行是 `try:`，
#      Go 是 `if err != nil {`），semgrep 只认「同一行」或「紧邻的上一行」。
#   2) 因此 `fallback-key` 只能写在 nosemgrep 的**上一行**（或与 nosemgrep 同一行行尾）。
#      如果把 fallback-key 插在 nosemgrep 和代码之间，nosemgrep 会失效。
#   3) 不写在同一行的原因：semgrep 把 `nosemgrep:` 之后的内容按逗号切分当作规则 id 列表，
#      行尾追加其它文字有破坏解析的风险。本工具包开发机上没有 semgrep，无法实测该行为，
#      因此采用保守的「分两行」写法（本条约定属于「无证据不放宽」，见 README 设计取舍）。
#   4) 禁止裸 `nosemgrep`（不指名规则 id）：那会一次性关掉所有规则。对账阶段直接判违规。
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

SEMGREP_CONFIG="${FALLBACK_SEMGREP_CONFIG:-${PKG_DIR}/semgrep/silent-fallback.yaml}"
STRICT="${FALLBACK_CHECK_STRICT:-0}"

REPO_ROOT="${FALLBACK_REPO_ROOT:-}"
if [ -z "${REPO_ROOT}" ]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "${REPO_ROOT}" ]; then
    REPO_ROOT="$PWD"
fi

REGISTRY_REL="${FALLBACK_REGISTRY:-policy/fallbacks.yaml}"
case "$REGISTRY_REL" in
    /*) REGISTRY="$REGISTRY_REL" ;;
    *)  REGISTRY="${REPO_ROOT}/${REGISTRY_REL}" ;;
esac

# 参与检查的代码后缀
CODE_EXT_RE='\.(py|pyi|go|js|jsx|mjs|cjs|ts|tsx|php)$'

TMPDIR_SELF=""
cleanup() {
    if [ -n "$TMPDIR_SELF" ] && [ -d "$TMPDIR_SELF" ]; then
        rm -rf "$TMPDIR_SELF"
    fi
}
trap cleanup EXIT

# 注意：不要写成 `tmp="$(mktmp)"` —— 命令替换在子 shell 里执行，
# 全局变量赋值会丢，trap cleanup 就删不掉临时目录。
ensure_tmp() {
    if [ -z "$TMPDIR_SELF" ]; then
        TMPDIR_SELF="$(mktemp -d "${TMPDIR:-/tmp}/fallback-check.XXXXXX")"
    fi
}

log_err() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<'USAGE'
用法: check-fallback.sh <hook|diff|full|audit-exemptions|audit-registry>

  hook              stdin 读 Claude Code PostToolUse JSON，检查单文件，命中 exit 2
  diff              检查 git staged（或 HEAD diff）文件，命中 exit 1
  full              CI 全量：semgrep 扫描 + 豁免对账 + 白名单对账
  audit-exemptions  仅豁免对账
  audit-registry    仅白名单对账

环境变量: FALLBACK_CHECK_STRICT / FALLBACK_REGISTRY / FALLBACK_SEMGREP_CONFIG /
          FALLBACK_REPO_ROOT / FALLBACK_EXCLUDE
USAGE
}

# --------------------------------------------------------------------------
# semgrep 封装
# --------------------------------------------------------------------------
have_semgrep() { command -v semgrep >/dev/null 2>&1; }

run_semgrep() {
    # --error: 有命中就以非 0 退出；--metrics=off/--disable-version-check: 不联网
    semgrep \
        --config "$SEMGREP_CONFIG" \
        --error \
        --quiet \
        --metrics=off \
        --disable-version-check \
        --timeout 60 \
        "$@"
}

semgrep_missing_banner() {
    log_err ""
    log_err "############################################################"
    log_err "# [fallback-check] 未检测到 semgrep，静默降级拦截当前是关闭的 #"
    log_err "############################################################"
    log_err "  安装:  pipx install semgrep   或   pip install semgrep"
    log_err "  这次放行是一条**已登记**的降级: fallback-key: check-script-semgrep-missing"
    log_err "  （登记在 policy/fallbacks.yaml；理由与到期日见该文件）"
    log_err "  想让它 fail-closed: 设置 FALLBACK_CHECK_STRICT=1"
    log_err ""
}

# --------------------------------------------------------------------------
# 内嵌 python helper（对账逻辑）
#   py_helper <mode> <args...>
#   mode: audit-exemptions | audit-registry
# --------------------------------------------------------------------------
py_helper() {
    python3 - "$@" <<'PYEOF'
# -*- coding: utf-8 -*-
"""白名单/豁免对账逻辑。零额外依赖：PyYAML 有则用，没有则退化为极简解析器。"""
import datetime
import os
import re
import sys

CODE_EXT = {".py", ".pyi", ".go", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".php"}
# 查找 test 标识时搜得更宽一些：测试可能写在 shell/其它语言里
TEST_CORPUS_EXT = CODE_EXT | {
    ".sh", ".bash", ".rb", ".java", ".kt", ".rs", ".cs", ".scala", ".ex", ".exs",
}
SKIP_DIRS = {
    ".git", "node_modules", "vendor", "dist", "build", "target",
    ".venv", "venv", "__pycache__", ".next", ".mypy_cache", ".pytest_cache",
    ".tox", ".gradle", "coverage",
}
REQUIRED_FIELDS = [
    "key", "module", "trigger", "behavior", "reason",
    "owner", "approved_by", "approved_at", "expires", "test",
]
KEY_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
NOSEMGREP_RE = re.compile(r"nosemgrep\b\s*(?::\s*(?P<ids>[^\n]*))?")
FALLBACK_KEY_RE = re.compile(r"fallback-key\s*:\s*(?P<key>[A-Za-z0-9_-]+)")


# ---------------------------------------------------------------- YAML 加载
def _minimal_parse(text):
    """极简 YAML 子集解析器。

    只认 policy/fallbacks.yaml 这一种固定结构：顶层 `fallbacks:` 下面是
    `- key: value` 列表，值为标量（允许 >- / | 块标量与引号）。
    结构对不上就抛异常 —— 降级路径依然 fail-closed，不静默放行。
    fallback-key: check-script-yaml-minimal-parser
    """
    items, cur, block_field, block_indent = [], None, None, None
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))

        if block_field is not None:
            if stripped and indent > block_indent:
                cur[block_field] = (cur[block_field] + " " + stripped).strip()
                continue
            block_field, block_indent = None, None

        if not stripped or stripped.startswith("#"):
            continue
        if stripped == "fallbacks:":
            continue

        if stripped.startswith("- "):
            cur = {}
            items.append(cur)
            stripped = stripped[2:].strip()
            indent += 2
        if cur is None:
            continue
        if ":" not in stripped:
            raise ValueError("无法解析的行: %r" % raw)
        field, _, value = stripped.partition(":")
        field, value = field.strip(), value.strip()
        if value in (">-", ">", "|", "|-", ">+"):
            cur[field] = ""
            block_field, block_indent = field, indent
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        cur[field] = value
    return {"fallbacks": items}


def load_registry(path):
    """返回 (entries, parser_name)。文件不存在 → 抛错（不静默当成空白名单）。"""
    if not os.path.isfile(path):
        raise SystemExit("[FAIL] 白名单文件不存在: %s（用 FALLBACK_REGISTRY 指定路径，"
                         "或从工具包拷贝 policy/fallbacks.example.yaml）" % path)
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    try:
        import yaml  # 首选
    except ImportError:
        data, parser = _minimal_parse(text), "minimal(builtin)"
    else:
        data, parser = yaml.safe_load(text) or {}, "pyyaml"
    entries = (data or {}).get("fallbacks") or []
    if not isinstance(entries, list):
        raise SystemExit("[FAIL] %s: 顶层 `fallbacks:` 必须是列表" % path)
    return entries, parser


# ------------------------------------------------------------- 文件列表读取
def iter_files(root, filelist, pkg_dir, exts=None):
    exts = exts or CODE_EXT
    with open(filelist, "rb") as fh:
        blob = fh.read()
    excluded_root = os.path.join(pkg_dir, "examples")
    extra = [d for d in os.environ.get("FALLBACK_EXCLUDE", "").split() if d]
    for raw in blob.split(b"\0"):
        if not raw:
            continue
        rel = raw.decode("utf-8", "replace")
        path = os.path.normpath(os.path.join(root, rel))
        parts = os.path.normpath(rel).split(os.sep)
        if any(p in SKIP_DIRS for p in parts):
            continue
        if extra and any(p in parts or path.startswith(os.path.join(root, p) + os.sep)
                         for p in extra):
            continue
        if os.path.splitext(path)[1] not in exts:
            continue
        # 工具包自带的反面/正面样例不参与宿主仓库对账
        if path.startswith(excluded_root + os.sep):
            continue
        if not os.path.isfile(path):
            continue
        yield path


def read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError as exc:  # 读不了就报出来，不吞
        raise SystemExit("[FAIL] 无法读取 %s: %s" % (path, exc))


# ------------------------------------------------------------ (b) 豁免对账
def audit_exemptions(registry, root, filelist, pkg_dir):
    entries, parser = load_registry(registry)
    known = set()
    for e in entries:
        if isinstance(e, dict) and e.get("key"):
            known.add(str(e["key"]))
    violations, checked = [], 0

    for path in iter_files(root, filelist, pkg_dir):
        lines = read_lines(path)
        for i, line in enumerate(lines):
            m = NOSEMGREP_RE.search(line)
            if not m:
                continue
            ids_raw = m.group("ids") or ""
            ids = [x.strip() for x in ids_raw.split(",") if x.strip()]
            if not ids:
                violations.append((path, i + 1,
                                   "裸 nosemgrep（未指名规则 id）会一次性关掉所有规则，"
                                   "必须写成 `nosemgrep: <rule-id>`"))
                continue
            targeted = [x for x in ids if x.startswith("silent-fallback-")]
            if not targeted:
                continue
            checked += 1
            window = "\n".join(lines[max(0, i - 1):i + 2])
            km = FALLBACK_KEY_RE.search(window)
            if not km:
                violations.append((path, i + 1,
                                   "豁免 %s 缺少 `fallback-key: <key>` 标注"
                                   "（写在 nosemgrep 同一行行尾或紧邻的上/下一行）"
                                   % ",".join(targeted)))
                continue
            key = km.group("key")
            if key not in known:
                violations.append((path, i + 1,
                                   "fallback-key `%s` 未登记在 %s"
                                   % (key, os.path.relpath(registry, root))))

    print("[audit-exemptions] parser=%s 白名单条目=%d 已检查豁免点=%d"
          % (parser, len(known), checked))
    if violations:
        print("[FAIL] 发现 %d 处未登记/不合规的豁免:" % len(violations))
        for path, lineno, msg in violations:
            print("  %s:%d  %s" % (os.path.relpath(path, root), lineno, msg))
        return 1
    print("[OK] 所有 silent-fallback-* 豁免均已登记")
    return 0


# ---------------------------------------------------------- (c) 白名单对账
def split_test_ids(value):
    return [t for t in re.split(r"[\s/,;|]+", str(value or "")) if t]


def audit_registry(registry, root, filelist, pkg_dir, strict):
    entries, parser = load_registry(registry)
    today = datetime.date.today()
    errors, warnings = [], []
    seen = set()

    if not entries:
        print("[audit-registry] parser=%s 白名单为空，跳过" % parser)
        return 0

    corpus = None  # 延迟加载：只有需要查 test 标识时才读全仓库

    for idx, e in enumerate(entries):
        if not isinstance(e, dict):
            errors.append("第 %d 条不是 mapping" % (idx + 1))
            continue
        key = str(e.get("key") or "")
        label = key or ("#%d" % (idx + 1))
        for field in REQUIRED_FIELDS:
            if not str(e.get(field) or "").strip():
                errors.append("%s: 缺字段 `%s`" % (label, field))
        if key and not KEY_RE.match(key):
            errors.append("%s: key 必须是 kebab-case" % label)
        if key in seen:
            errors.append("%s: key 重复" % label)
        seen.add(key)

        raw_exp = str(e.get("expires") or "").strip()
        if raw_exp:
            try:
                exp = datetime.datetime.strptime(raw_exp, "%Y-%m-%d").date()
            except ValueError:
                errors.append("%s: expires `%s` 不是 YYYY-MM-DD" % (label, raw_exp))
            else:
                if exp < today:
                    errors.append("%s: 降级已于 %s 过期，请复审后续期或删除该降级"
                                  % (label, raw_exp))
                elif (exp - today).days <= 30:
                    warnings.append("%s: 还有 %d 天到期 (%s)"
                                    % (label, (exp - today).days, raw_exp))

        tests = split_test_ids(e.get("test"))
        if tests:
            if corpus is None:
                corpus = {}
                for path in iter_files(root, filelist, pkg_dir, TEST_CORPUS_EXT):
                    corpus[path] = "\n".join(read_lines(path))
            hit = any(t in blob for t in tests for blob in corpus.values())
            if not hit:
                msg = "%s: test 标识 %s 在仓库中找不到（故障注入测试没写？）" % (
                    label, "/".join(tests))
                (errors if strict else warnings).append(msg)

    print("[audit-registry] parser=%s 条目=%d today=%s strict=%d"
          % (parser, len(entries), today.isoformat(), int(strict)))
    for w in warnings:
        print("  [WARN] %s" % w)
    if errors:
        print("[FAIL] 白名单有 %d 处问题:" % len(errors))
        for e in errors:
            print("  %s" % e)
        return 1
    print("[OK] 白名单校验通过（无过期条目）")
    return 0


def main(argv):
    mode = argv[1]
    if mode == "audit-exemptions":
        registry, root, filelist, pkg_dir = argv[2:6]
        return audit_exemptions(registry, root, filelist, pkg_dir)
    if mode == "audit-registry":
        registry, root, filelist, pkg_dir, strict = argv[2:7]
        return audit_registry(registry, root, filelist, pkg_dir, strict == "1")
    raise SystemExit("未知 py_helper mode: %s" % mode)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF
}

require_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_err "[fallback-check] 缺少 python3，无法执行对账。这是环境缺陷，不降级放行。"
        exit 1
    fi
}

build_file_list() {
    # $1 = 输出文件（NUL 分隔的相对路径）
    local out="$1"
    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$REPO_ROOT" ls-files -z >"$out"
    else
        ( cd "$REPO_ROOT" && find . -type f -print0 ) >"$out"
    fi
}

# --------------------------------------------------------------------------
# hook
# --------------------------------------------------------------------------
cmd_hook() {
    local payload file_path
    payload="$(cat)"
    file_path=""

    if command -v jq >/dev/null 2>&1; then
        file_path="$(printf '%s' "$payload" \
            | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
    fi
    if [ -z "$file_path" ] && command -v python3 >/dev/null 2>&1; then
        file_path="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("file_path") or ti.get("notebook_path") or "")
' 2>/dev/null || true)"
    fi
    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        # 与 semgrep 缺失不同：jq/python3 全都没有意味着 hook 永远不可能工作，
        # 静默放行会让整层拦截变成看不见的摆设，所以这里 fail-closed。
        log_err "[fallback-check] hook 需要 jq 或 python3 解析输入，两者都不存在。"
        log_err "                 请安装其一，或从 .claude/settings.json 移除本 hook。"
        exit 2
    fi

    [ -n "$file_path" ] || exit 0
    [ -f "$file_path" ] || exit 0
    printf '%s' "$file_path" | grep -Eq "$CODE_EXT_RE" || exit 0

    if ! have_semgrep; then
        semgrep_missing_banner
        if [ "$STRICT" = "1" ]; then
            log_err "[fallback-check] FALLBACK_CHECK_STRICT=1 → 拒绝在无 semgrep 的情况下放行"
            exit 2
        fi
        exit 0
    fi

    local out rc
    ensure_tmp
    out="${TMPDIR_SELF}/hook.out"
    rc=0
    run_semgrep "$file_path" >"$out" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        {
            echo "[fallback-check] 检测到静默降级/过度防御，本次编辑已被打回："
            echo
            cat "$out"
            echo
            echo "修法（二选一，不要绕过）："
            echo "  1) 直接向上抛错，保留原始 error/异常链，让调用方看见真实失败；"
            echo "  2) 确属有意降级 → 走统一入口（fallback.Run / fallback.run），"
            echo "     在 ${REGISTRY_REL} 登记 key（含 trigger/reason/owner/expires/test），"
            echo "     再按约定标注两行注释："
            echo "        # fallback-key: <key>"
            echo "        # nosemgrep: <rule-id>     <- 必须紧贴命中起始行"
            echo "  禁止：删掉报错、改宽 except、加裸 nosemgrep 来让检查通过。"
        } >&2
        exit 2
    fi
    exit 0
}

# --------------------------------------------------------------------------
# diff
# --------------------------------------------------------------------------
cmd_diff() {
    local files
    files="$(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)"
    if [ -z "$files" ]; then
        files="$(git -C "$REPO_ROOT" diff --name-only --diff-filter=ACM HEAD 2>/dev/null || true)"
    fi
    if [ -z "$files" ]; then
        echo "[fallback-check] 没有待检查的改动文件"
        exit 0
    fi

    local targets=()
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        printf '%s' "$f" | grep -Eq "$CODE_EXT_RE" || continue
        [ -f "${REPO_ROOT}/${f}" ] || continue
        targets[${#targets[@]}]="${REPO_ROOT}/${f}"
    done <<EOF
$files
EOF

    if [ "${#targets[@]}" -eq 0 ]; then
        echo "[fallback-check] 改动中没有需要检查的代码文件"
        exit 0
    fi

    if ! have_semgrep; then
        # diff 模式是提交前的强制关卡，缺 semgrep 直接失败（不适用 hook 的那条降级）
        log_err "[fallback-check] 缺少 semgrep，pre-commit 关卡无法生效 → 失败。"
        log_err "                 安装: pipx install semgrep 或 pip install semgrep"
        exit 1
    fi

    local rc=0
    run_semgrep "${targets[@]}" || rc=$?
    if [ "$rc" -ne 0 ]; then
        log_err ""
        log_err "[fallback-check] 提交被拦下：上述位置存在未登记的静默降级。"
        log_err "  → 改为向上抛错，或走统一 fallback 入口 + ${REGISTRY_REL} 登记 + 两行豁免标注。"
        exit 1
    fi
    echo "[fallback-check] diff 检查通过（${#targets[@]} 个文件）"
    exit 0
}

# --------------------------------------------------------------------------
# audit-exemptions / audit-registry / full
# --------------------------------------------------------------------------
cmd_audit_exemptions() {
    require_python
    ensure_tmp
    local list="${TMPDIR_SELF}/files.bin"
    build_file_list "$list"
    py_helper audit-exemptions "$REGISTRY" "$REPO_ROOT" "$list" "$PKG_DIR"
}

cmd_audit_registry() {
    require_python
    ensure_tmp
    local list="${TMPDIR_SELF}/files.bin"
    build_file_list "$list"
    py_helper audit-registry "$REGISTRY" "$REPO_ROOT" "$list" "$PKG_DIR" "$STRICT"
}

cmd_full() {
    local failed=0

    echo "=== [1/3] semgrep 全量扫描 : $REPO_ROOT ==="
    if ! have_semgrep; then
        log_err "[FAIL] 缺少 semgrep：CI 全量扫描无法执行。"
        log_err "       CI 里请先 pip install semgrep（见 ci/github-actions.snippet.yml）。"
        failed=1
    else
        local excl=()
        local d rel
        for d in .git node_modules vendor dist build target .venv venv __pycache__ .next; do
            excl[${#excl[@]}]="--exclude"
            excl[${#excl[@]}]="$d"
        done
        # shellcheck disable=SC2086  # 故意不加引号：按空格拆成多个排除项
        for d in ${FALLBACK_EXCLUDE:-}; do
            excl[${#excl[@]}]="--exclude"
            excl[${#excl[@]}]="$d"
        done
        # 工具包自带的反面样例必然命中，排除掉
        case "${PKG_DIR}/" in
            "${REPO_ROOT}/"*)
                rel="${PKG_DIR#"${REPO_ROOT}"/}"
                excl[${#excl[@]}]="--exclude"
                excl[${#excl[@]}]="${rel}/examples"
                ;;
        esac
        local rc=0
        run_semgrep ${excl[@]+"${excl[@]}"} "$REPO_ROOT" || rc=$?
        if [ "$rc" -ne 0 ]; then
            log_err "[FAIL] semgrep 扫描发现未登记的静默降级"
            failed=1
        else
            echo "[OK] semgrep 扫描通过"
        fi
    fi

    echo
    echo "=== [2/3] 豁免对账（nosemgrep ↔ fallback-key ↔ 白名单）==="
    cmd_audit_exemptions || failed=1

    echo
    echo "=== [3/3] 白名单对账（expires / test）==="
    cmd_audit_registry || failed=1

    echo
    if [ "$failed" -ne 0 ]; then
        log_err "=== [fallback-check] full 检查未通过 ==="
        exit 1
    fi
    echo "=== [fallback-check] full 检查全部通过 ==="
    exit 0
}

main() {
    if [ "$#" -lt 1 ]; then
        usage
        exit 64
    fi
    case "$1" in
        hook)             cmd_hook ;;
        diff)             cmd_diff ;;
        full)             cmd_full ;;
        audit-exemptions) cmd_audit_exemptions ;;
        audit-registry)   cmd_audit_registry ;;
        -h|--help|help)   usage; exit 0 ;;
        *)                log_err "未知子命令: $1"; usage; exit 64 ;;
    esac
}

main "$@"
