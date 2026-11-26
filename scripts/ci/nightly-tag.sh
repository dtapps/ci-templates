#!/usr/bin/env bash
# 在本次构建的提交上创建并推送发布标签（nightly 与正式版共用）。
#
# 定时任务和手动按钮都没有现成的 tag，而 Release 必须挂在一个 tag 上，
# 所以发布前在这里创建；tag_push 事件本身已带 tag，不需要跑本脚本。
#
# 必需环境变量：
#   TAG          要创建的标签名，如 v1.2.3 / v1.2.4-nightly.20260101
# 提交来源（按顺序取第一个非空的）：
#   TAG_COMMIT → COMMIT → CNB_COMMIT（CNB 内置）→ HEAD
# 可选：
#   DRY_RUN=1    只打印将要执行的命令，不真正打标签 / 推送
set -euo pipefail

# 输出语言：优先 CI_LANG，否则按 LC_ALL > LC_MESSAGES > LANG 自动判断。
case "${CI_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in
  zh* | ZH*) CI_LANG=zh ;;
  *) CI_LANG=en ;;
esac

msg() {
  local key="$1"
  shift
  case "$CI_LANG:$key" in
    en:required_env) printf '%s is required\n' "$@" ;;
    zh:required_env) printf '缺少必需的环境变量 %s\n' "$@" ;;
    en:tag_exists_moving) printf '==> tag %s already exists, moving to %s\n' "$@" ;;
    zh:tag_exists_moving) printf '==> 标签 %s 已存在，将移动到 %s\n' "$@" ;;
    en:creating_tag) printf '==> creating tag %s -> %s\n' "$@" ;;
    zh:creating_tag) printf '==> 创建标签 %s -> %s\n' "$@" ;;
    en:dry_run_push) printf '[dry-run] git push --force origin refs/tags/%s\n' "$@" ;;
    zh:dry_run_push) printf '[dry-run] git push --force origin refs/tags/%s\n' "$@" ;;
    en:pushed_tag) printf '==> pushed tag %s\n' "$@" ;;
    zh:pushed_tag) printf '==> 已推送标签 %s\n' "$@" ;;
  esac
}

require() {
  if [ -z "$(printenv "$1" 2>/dev/null)" ]; then
    msg required_env "$1" >&2
    exit 1
  fi
}

require TAG
DRY_RUN="${DRY_RUN:-0}"

TAG_COMMIT="${TAG_COMMIT:-${COMMIT:-${CNB_COMMIT:-HEAD}}}"

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  msg tag_exists_moving "$TAG" "$TAG_COMMIT"
  [ "$DRY_RUN" = "1" ] || git tag -f "$TAG" "$TAG_COMMIT"
else
  msg creating_tag "$TAG" "$TAG_COMMIT"
  [ "$DRY_RUN" = "1" ] || git tag "$TAG" "$TAG_COMMIT"
fi

if [ "$DRY_RUN" = "1" ]; then
  msg dry_run_push "$TAG"
else
  git push --force origin "refs/tags/${TAG}"
  msg pushed_tag "$TAG"
fi
