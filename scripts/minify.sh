#!/usr/bin/env bash
#
# Shell 脚本压缩入口：把 scripts/ 下的 .sh 生成紧凑副本，产物放 dist/minify/。
#
# 为什么不能无脑删注释和空行：
#   - scripts/ci/*.sh 的用法说明就在头部注释块里，delete-release.sh / fetch-scripts.sh
#     的 usage() 用 `sed -n '2,/^$/p' "$0"` 从这里取正文；注释块或它后面那个空行被删，
#     --help 就会输出错乱，甚至把整份脚本当成用法打出来；
#   - heredoc（<<EOF / <<'EOF' / <<-EOF）里的内容是数据（脚本清单、自检用例、JSON），
#     按普通文本去注释会把其中以 # 开头的行误删。
#
# 压缩规则（安全优先，收益其次）：
#   1. 第 1 行 shebang 原样保留；
#   2. 第 2 行到第一个空行（含）整段原样保留——这正是 usage() 依赖的头部区；
#   3. heredoc 内部整段原样保留；
#   4. 其余整行注释与空行删除；
#   5. 行首缩进不动（对体积影响小，遇到续行 / 引号内书写反而容易改错）。
#
# 每个产物都会做两道校验，任一失败就报错并且不写盘：
#   - sh -n 语法检查；
#   - 头部用法段与原文件一致（保证 --help 不变）。
#
# 用法：
#   scripts/minify.sh shell              # 压缩 scripts/ 下所有 .sh
#   scripts/minify.sh shell a.sh b.sh    # 只压指定文件
#
# 环境变量：
#   MINIFY_OUT=dist/minify   产物目录（相对仓库根），默认 dist/minify

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_PREFIX="[Minify] "

###############################################################################
# 可自定义配置区（复制到其它项目时，只改这一段即可）
#
# - MINIFY_OUT：产物目录，按原相对路径存放（scripts/ci/x.sh -> dist/minify/scripts/ci/x.sh）
# - *_TARGETS / *_GLOB / *_EXCLUDES：与 format.sh 同一套约定
#   EXCLUDES 是 find -path 的 glob 模式，默认留空；数组用 ${arr[@]+"${arr[@]}"} 展开
###############################################################################

MINIFY_OUT="${MINIFY_OUT:-dist/minify}"
SHELL_TARGETS=("scripts/")
SHELL_GLOB="*.sh"
SHELL_EXCLUDES=()

###############################################################################

log() { printf '%s%s\n' "$LOG_PREFIX" "$*"; }
err() { printf '%s%s\n' "$LOG_PREFIX" "$*" >&2; }

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# awk 压缩程序：
#   head / hd 两个状态分别表示「头部区」「heredoc 内」，命中时整行原样输出。
#   heredoc 起始用动态拼出来的正则匹配，兼容 <<EOF / <<'EOF' / <<"EOF" / <<-EOF。
MINIFY_AWK='
BEGIN {
  head = 1
  hd = 0
  tag = ""
  q = "\047"
  hre = "<<-?[ \t]*[" q "\"]?[A-Za-z_][A-Za-z0-9_]*[" q "\"]?"
}
NR == 1 { print; next }
hd {
  print
  line = $0
  sub(/^\t+/, "", line)
  if (line == tag) { hd = 0; tag = "" }
  next
}
head {
  print
  if ($0 ~ /^[ \t]*$/) head = 0
  next
}
match($0, hre) {
  t = substr($0, RSTART, RLENGTH)
  sub(/^<<-?[ \t]*/, "", t)
  c = substr(t, 1, 1)
  if (c == q || c == "\"") t = substr(t, 2)
  n = length(t)
  if (n > 0) {
    c = substr(t, n, 1)
    if (c == q || c == "\"") t = substr(t, 1, n - 1)
  }
  print
  hd = 1
  tag = t
  next
}
/^[ \t]*#/ { next }
/^[ \t]*$/ { next }
{ print }
'

# 收集待压缩文件；带参数时直接用参数
collect_files() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return 0
  fi
  local p
  for p in ${SHELL_TARGETS[@]+"${SHELL_TARGETS[@]}"}; do
    [ -e "$p" ] || continue
    if [ -d "$p" ]; then
      local -a find_args=("$p" -type f -name "$SHELL_GLOB")
      local e
      for e in ${SHELL_EXCLUDES[@]+"${SHELL_EXCLUDES[@]}"}; do
        find_args+=(-not -path "$e")
      done
      find "${find_args[@]}" | sort
    else
      printf '%s\n' "$p"
    fi
  done
}

# 按 shebang 选解释器做语法检查：bash 脚本用 sh -n 会把 [[ ]]、数组误判成语法错误
syntax_check() {
  local f="$1"
  local line first
  line="$(sed -n '1s|^#![[:space:]]*||p' "$f")"
  first="${line%%[[:space:]]*}"
  if [ "${first##*/}" = 'env' ]; then
    line="${line#*[[:space:]]}"
    first="${line%%[[:space:]]*}"
  fi
  case "${first##*/}" in
    bash) bash -n "$f" 2>/dev/null ;;
    *) sh -n "$f" 2>/dev/null ;;
  esac
}

# 压缩单个文件：先写临时文件，两道校验通过后才 mv 到产物目录
compress_one() {
  local src="$1"
  local dest="$MINIFY_OUT/$src"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/minify.XXXXXX")"

  if ! awk "$MINIFY_AWK" "$src" >"$tmp"; then
    rm -f "$tmp"
    err "压缩失败（awk）：$src"
    return 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    err "压缩产物为空，放弃写入：$src"
    return 1
  fi

  if ! syntax_check "$tmp"; then
    rm -f "$tmp"
    err "压缩后语法检查未通过，放弃写入：$src"
    return 1
  fi

  local src_head dest_head
  src_head="$(sed -n '2,/^$/p' "$src")"
  dest_head="$(sed -n '2,/^$/p' "$tmp")"
  if [ "$src_head" != "$dest_head" ]; then
    rm -f "$tmp"
    err "压缩后头部用法段变化（--help 会坏），放弃写入：$src"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"
  mv -f "$tmp" "$dest"
  chmod 755 "$dest" 2>/dev/null || :

  local before after
  before="$(wc -c <"$src" | tr -d ' ')"
  after="$(wc -c <"$dest" | tr -d ' ')"
  TOTAL_FILES=$((TOTAL_FILES + 1))
  TOTAL_BEFORE=$((TOTAL_BEFORE + before))
  TOTAL_AFTER=$((TOTAL_AFTER + after))
  printf '%s%-40s %7s B -> %7s B\n' "$LOG_PREFIX" "$src" "$before" "$after"
  return 0
}

minify_shell() {
  local -a files=()
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    files+=("$f")
  done < <(collect_files "$@")

  if [ "${#files[@]}" -eq 0 ]; then
    log "没有可压缩的 Shell 文件，跳过。"
    return 0
  fi

  TOTAL_FILES=0
  TOTAL_BEFORE=0
  TOTAL_AFTER=0

  for f in "${files[@]}"; do
    compress_one "$f" || return 1
  done

  log "完成：${TOTAL_FILES} 个文件，${TOTAL_BEFORE} B -> ${TOTAL_AFTER} B"
  if [ "$TOTAL_BEFORE" -gt 0 ]; then
    local pct=$(((TOTAL_BEFORE - TOTAL_AFTER) * 100 / TOTAL_BEFORE))
    log "产物目录：${MINIFY_OUT}/（共减少 ${pct}%）"
  fi
  return 0
}

main() {
  local mode="${1:-}"
  case "$mode" in
    shell)
      shift
      minify_shell "$@"
      ;;
    '' | -h | --help)
      usage
      ;;
    *)
      err "未知目标：${mode}（可用：shell）"
      exit 2
      ;;
  esac
}

main "$@"
