#!/usr/bin/env bash
# 解析本次要发布的版本号。
#
# 基准版本（nightly 用）以「首发制品库」为准：CNB 通用 npm 制品库里的
# dist-tags.latest / versions，读不到时回退到 git tag 里最大的正式版，
# 再读不到就按 0.0.0 起算（即首版 nightly 为 0.0.1-nightly.<日期>）。
#
# 环境变量输入：
#   VERSION   原始版本输入（crontab 任务的 env，或显式指定的大写变量）。
#   version   web_trigger 表单注入的小写输入：CNB 按 input key 原样注入环境变量，
#             所以 .cnb/web_trigger.yml 里的小写 `version` 到达脚本时是 $version，
#             而不是 $VERSION。两者同时存在时以 $VERSION 为准；都没填则默认 nightly。
#             取值之一：
#             1.2.3                    正式版
#             1.2.3-rc.1               预发布（rc 渠道）
#             1.2.3-beta.1             预发布（beta 渠道）
#             1.2.3-alpha.1            预发布（alpha 渠道）
#             1.2.3-nightly.20260101   预发布（nightly 渠道）
#             nightly                  展开为 <最新正式版 + 1 补丁>-nightly.<日期>；
#                                      日期跟随调度器时区：CNB 用北京时间（内置变量
#                                      CNB 的值为 true），GitHub Actions 用 UTC。
#   NPM_REGISTRY  查基准版本用的制品库，默认 CNB 通用 npm 制品库；
#                 注意不要用发布目标变量（PUBLISH_REGISTRY / NPMJS_REGISTRY）覆盖它。
# 输出（写入 $GITHUB_OUTPUT 风格的文件，默认 .version.env）：
#   VERSION       规范化后的 semver，不带前导 v（如 0.2.8-nightly.20261114）
#   TAG           git 标签名（如 v0.2.8-nightly.20261114）
#   CHANNEL       stable | rc | beta | alpha | nightly | prerelease 之一
#   DIST_TAG      npm dist-tag：正式版 latest，rc/beta/alpha/nightly 用同名渠道，
#                 其它自定义预发布标识用 next
#   PRERELEASE    任意预发布渠道为 true，正式版为 false
#   LATEST        正式版为 true（Release 标记为 latest），预发布为 false
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
    en:cannot_determine_pkg) printf 'resolve-version: cannot determine package name (package.json or CNB_REPO_NAME_LOWERCASE)\n' ;;
    zh:cannot_determine_pkg) printf 'resolve-version：无法确定包名（package.json 或 CNB_REPO_NAME_LOWERCASE）\n' ;;
    en:version_required) printf "resolve-version: VERSION input is required (a semver, or the literal 'nightly')\n" ;;
    zh:version_required) printf "resolve-version：缺少 VERSION 输入（需为 semver 或字面量 'nightly'）\n" ;;
    en:invalid_semver) printf "resolve-version: '%s' is not a semver (expected 1.2.3 or 1.2.3-rc.1, or 'nightly')\n" "$@" ;;
    zh:invalid_semver) printf "resolve-version：'%s' 不是合法的 semver（应为 1.2.3、1.2.3-rc.1 或 'nightly'）\n" "$@" ;;
    en:resolved) printf 'resolved: version=%s tag=%s channel=%s dist-tag=%s prerelease=%s latest=%s\n' "$@" ;;
    zh:resolved) printf '已解析：version=%s tag=%s channel=%s dist-tag=%s prerelease=%s latest=%s\n' "$@" ;;
  esac
}

OUTPUT_FILE="${OUTPUT_FILE:-.version.env}"

# PKG_NAME from package.json, else @<group>/<repo> from the built-in env.
PKG_NAME="${PKG_NAME:-$(node -p "require('./package.json').name" 2>/dev/null || true)}"
[ -n "$PKG_NAME" ] || PKG_NAME="@${CNB_GROUP_SLUG_LOWERCASE:-}/${CNB_REPO_NAME_LOWERCASE:-}"
[ -n "$PKG_NAME" ] || {
  msg cannot_determine_pkg >&2
  exit 1
}

# 首发制品库（CNB 通用 npm 制品库）。这里只用来查基准版本，不代表实际发布目标。
NPM_REGISTRY="${NPM_REGISTRY:-https://npm.cnb.cool/dtapp/ci-templates/-/packages/}"

# VERSION precedence: uppercase VERSION (crontab job env / explicit override), then
# lowercase version (web_trigger form input key), else default to nightly.
raw="${VERSION:-${version:-nightly}}"
# Trim whitespace and a single leading `v` (v1.2.3 -> 1.2.3).
raw="${raw#"${raw%%[![:space:]]*}"}"
raw="${raw%"${raw##*[![:space:]]}"}"
raw="${raw#v}"

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+(\.[0-9A-Za-z.-]+)*)?$'

channel_of() {
  case "$1" in
    *-rc.*) echo rc ;;
    *-beta.*) echo beta ;;
    *-alpha.*) echo alpha ;;
    *-nightly.*) echo nightly ;;
    *-*) echo prerelease ;;
    *) echo stable ;;
  esac
}

# latest_stable <registry> <package name>
# Prints the highest stable (non-prerelease) version. The `latest` dist-tag is only
# trusted when it points to a stable version: this registry keeps nightly builds
# around, and bumping those would drift the nightly baseline upward.
latest_stable() {
  local registry="$1" pkg="$2" json latest
  if command -v curl >/dev/null 2>&1; then
    json="$(curl -fsSL --max-time 30 "${registry%/}/${pkg}" 2>/dev/null || true)"
  fi
  if [ -n "${json:-}" ]; then
    latest="$(
      printf '%s' "$json" | node -e '
			let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
				try{const j=JSON.parse(s);const t=j["dist-tags"]||{};
					const stable=v=>typeof v==="string"&&!/[-]/.test(v);
					if(stable(t.latest))return console.log(t.latest);
					const vs=Object.keys(j.versions||{}).filter(stable);
					if(vs.length){vs.sort((a,b)=>{const p=x=>x.split(".").map(Number);const A=p(a),B=p(b);for(let i=0;i<3;i++)if(A[i]!==B[i])return B[i]-A[i];return 0;});return console.log(vs[0]);}
				}catch{}
			});'
    )"
    if [ -n "$latest" ]; then
      echo "$latest"
      return 0
    fi
  fi
  # Fall back to the newest stable git tag (local, then remote).
  local tags
  tags="$(git tag --list 'v*' 2>/dev/null)" || tags=""
  if [ -z "$tags" ]; then
    tags="$(git ls-remote --tags --refs origin 'v*' 2>/dev/null | sed -n 's|.*refs/tags/||p')" || tags=""
  fi
  tags="$(printf '%s\n' "$tags" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
  if [ -n "$tags" ]; then
    echo "${tags#v}"
    return 0
  fi
  echo "0.0.0"
}

bump_patch() {
  local v="$1" maj min pat
  maj="${v%%.*}"
  v="${v#*.}"
  min="${v%%.*}"
  pat="${v#*.}"
  # Drop any prerelease suffix left on the patch segment.
  pat="${pat%%-*}"
  echo "${maj}.${min}.$((pat + 1))"
}

# Nightly 日期跟随调度器时区，避免跨零点时算出昨天的日期：
#   CNB（内置变量 CNB 的值为 true）：crontab 按 Asia/Shanghai 触发，用北京时间（UTC+8）。
#   GitHub Actions（GITHUB_ACTIONS=true）与本地：schedule 按 UTC 触发，用 UTC。
nightly_date() {
  if [ "${CNB:-}" = "true" ]; then
    # 用 Node 做固定 +8 偏移，避免依赖镜像里的 tzdata；没有 node 时退到 TZ 版 date。
    if command -v node >/dev/null 2>&1; then
      node -e 'const d=new Date(Date.now()+8*3600*1000);process.stdout.write(d.toISOString().slice(0,10).replace(/-/g,""))'
    else
      TZ=Asia/Shanghai date +%Y%m%d
    fi
  else
    date -u +%Y%m%d
  fi
}

if [ "$raw" = "nightly" ]; then
  base="$(latest_stable "$NPM_REGISTRY" "$PKG_NAME")"
  case "$base" in
    *[-]*) base="$(echo "$base" | sed 's/-.*//')" ;;
  esac
  VERSION="$(bump_patch "$base")-nightly.$(nightly_date)"
elif [ -z "$raw" ]; then
  msg version_required >&2
  exit 1
elif [[ ! $raw =~ $SEMVER_RE ]]; then
  msg invalid_semver "$raw" >&2
  exit 1
else
  VERSION="$raw"
fi

CHANNEL="$(channel_of "$VERSION")"
case "$CHANNEL" in
  stable)
    DIST_TAG="latest"
    PRERELEASE="false"
    LATEST="true"
    ;;
  prerelease)
    # Unrecognized prerelease id: publish under `next`, still a prerelease.
    DIST_TAG="next"
    PRERELEASE="true"
    LATEST="false"
    ;;
  *)
    DIST_TAG="$CHANNEL"
    PRERELEASE="true"
    LATEST="false"
    ;;
esac
TAG="v${VERSION}"

{
  echo "VERSION=${VERSION}"
  echo "TAG=${TAG}"
  echo "CHANNEL=${CHANNEL}"
  echo "DIST_TAG=${DIST_TAG}"
  echo "PRERELEASE=${PRERELEASE}"
  echo "LATEST=${LATEST}"
} >"$OUTPUT_FILE"

# CNB `exports` maps job-result keys to env vars; result keys are produced only
# by `##[set-output key=value]` lines on stdout. Without these, downstream
# stages (create tag / release / publish) receive empty VERSION / TAG / ....
# GitHub Actions 会把这种格式当成自家已废弃的 set-output 命令解析并报错，
# 而它从 .version.env 写入 $GITHUB_OUTPUT 的逻辑在发布工作流里，故这里跳过。
if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
  for key in VERSION TAG CHANNEL DIST_TAG PRERELEASE LATEST; do
    echo "##[set-output ${key}=${!key}]"
  done
fi

msg resolved "$VERSION" "$TAG" "$CHANNEL" "$DIST_TAG" "$PRERELEASE" "$LATEST"
cat "$OUTPUT_FILE"
