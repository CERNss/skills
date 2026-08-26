#!/usr/bin/env bash
#
# sync-from-source.sh —— 从 infra 源头单向同步工具包到本 plugin 的 assets/toolkit/
#
#   源头（唯一正本）: /Users/cern/LocalDisk/D/Repo/infra/codex-prompt/anti-silent-fallback/
#   目标（分发拷贝）: <plugin 根>/assets/toolkit/
#
# 方向是单向的：infra → plugin。rsync 带 --delete，
# **会覆盖并删除 assets/toolkit/ 下的本地改动**。要改内容请改 infra 那份。
#
# 用法:
#   bash scripts/sync-from-source.sh            # 同步
#   bash scripts/sync-from-source.sh --dry-run  # 只看会改什么，不落盘
#
# 环境变量:
#   FALLBACK_TOOLKIT_SOURCE   覆盖源头路径（换机器 / 换 checkout 位置时用）

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

SOURCE_DIR="${FALLBACK_TOOLKIT_SOURCE:-/Users/cern/LocalDisk/D/Repo/infra/codex-prompt/anti-silent-fallback}"
DEST_DIR="${PLUGIN_ROOT}/assets/toolkit"

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    "")        ;;
    *)         printf '未知参数: %s\n用法: %s [--dry-run]\n' "$1" "$0" >&2; exit 2 ;;
esac

# 源头不存在时硬失败，不静默跳过：
# 静默跳过会让「同步过了」这件事变成假的，正是本工具包要治的病。
if [ ! -d "$SOURCE_DIR" ]; then
    printf '源头目录不存在: %s\n' "$SOURCE_DIR" >&2
    printf '换了 checkout 位置就设 FALLBACK_TOOLKIT_SOURCE 指过去。\n' >&2
    exit 1
fi

if [ ! -f "${SOURCE_DIR}/scripts/check-fallback.sh" ]; then
    printf '源头目录看起来不是这个工具包（缺 scripts/check-fallback.sh）: %s\n' "$SOURCE_DIR" >&2
    exit 1
fi

RSYNC_ARGS=(-a --delete)
if [ "$DRY_RUN" -eq 1 ]; then
    RSYNC_ARGS+=(--dry-run --itemize-changes)
    printf '[dry-run] 只列差异，不落盘\n'
fi

mkdir -p "$DEST_DIR"
rsync "${RSYNC_ARGS[@]}" "${SOURCE_DIR}/" "${DEST_DIR}/"

if [ "$DRY_RUN" -eq 1 ]; then
    exit 0
fi

printf '已同步: %s -> %s\n' "$SOURCE_DIR" "$DEST_DIR"
printf '建议跑一次自测确认没搬坏:\n  bash %s/scripts/selftest.sh\n' "$DEST_DIR"
