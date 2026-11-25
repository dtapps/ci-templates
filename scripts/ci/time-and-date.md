# CI 里的时间与日期

本目录脚本涉及时间/日期时的统一约定：**内部一律用 epoch 记录绝对时间，只在最后一步按平台格式化展示**。除了 CNB 需要强制北京时间，其余一律跟随系统真实时区。

- CNB → 强制北京时间（UTC+8）。CNB 镜像通常是 UTC，必须手工 `+8 * 3600`，不能指望容器时区
- GitHub Actions / GitLab CI → 跟随系统真实时区（两台 runner 默认 UTC，所以通常就是 UTC）
- 本机开发（没有任何 CI 变量）→ 跟随系统真实时区（例如 macOS 上是 `CST +0800`）

## 1. 平台判定

| 判定条件                                                    | 平台           | 展示时区                               |
|-------------------------------------------------------------|----------------|----------------------------------------|
| `CNB=true`（兜底：`CNB_BUILD_ID` / `CNB_PIPELINE_ID` 非空） | CNB            | 北京时间 UTC+8（强制）                 |
| `GITHUB_ACTIONS=true`                                       | GitHub Actions | 系统真实时区（默认 UTC）               |
| `GITLAB_CI=true`                                            | GitLab CI      | 系统真实时区（默认 UTC）               |
| `GITEE_CI` / `GITEE_GO_PIPELINE_ID` 非空                    | Gitee Go       | 系统真实时区                           |
| `CI=true`                                                   | 任意 CI        | **只能说明「在 CI 里」，不能区分平台** |

`CI=true` 是跨平台的通用约定（GitHub Actions、GitLab CI、Travis、CircleCI、Netlify 等都会设），所以不要拿它做平台分支——GitHub Actions 里 `CI` 和 `GITHUB_ACTIONS` 同时为 `true`。

GitHub Actions 有独立标识：`GITHUB_ACTIONS=true`，这是官方默认环境变量。同一族还有 `GITHUB_WORKFLOW`、`GITHUB_JOB`、`GITHUB_RUN_ID`、`GITHUB_RUN_NUMBER`、`GITHUB_SHA`、`GITHUB_REF` 等，但**没有构建开始时间**。

## 2. 时间来源

| 平台           | 取构建时间的变量                              | 格式                              | 备注                                                                    |
|----------------|-----------------------------------------------|-----------------------------------|-------------------------------------------------------------------------|
| CNB            | `CNB_BUILD_START_TIME`                        | `2026-11-18T05:45:30.123Z`（UTC） | 构建开始时刻                                                            |
| GitHub Actions | 无                                            | —                                 | 没有官方注入的时间变量；runner 默认 UTC，只能 `date '+%s'` 取当前 epoch |
| GitLab CI      | `CI_PIPELINE_CREATED_AT`、`CI_JOB_STARTED_AT` | `2026-11-18T05:45:30Z`（UTC）     | 前者是流水线创建时刻，更适合当「构建开始」                              |
| 兜底           | 无                                            | —                                 | `date '+%s'` 取当前 epoch                                               |

拿不到时间变量时不要报错，用当前时间（或原样回显变量值），保证通知/日志不会因为时间而中断。

## 3. 可直接复制的实现（POSIX sh）

```sh
# 平台：cnb / github / gitlab / other
ci_platform() {
  if [ "${CNB:-}" = 'true' ] || [ -n "${CNB_BUILD_ID:-}" ] || [ -n "${CNB_PIPELINE_ID:-}" ]; then
    printf 'cnb'
  elif [ "${GITHUB_ACTIONS:-}" = 'true' ]; then
    printf 'github'
  elif [ "${GITLAB_CI:-}" = 'true' ]; then
    printf 'gitlab'
  else
    printf 'other'
  fi
}

# ISO8601 -> "YYYY-MM-DD HH:MM:SS"（去掉 T / 毫秒 / 结尾 Z）
normalize_utc() {
  printf '%s' "$1" | sed -E 's/T/ /; s/\.[0-9]+//; s/Z$//'
}

# "YYYY-MM-DD HH:MM:SS" -> epoch 秒；GNU date 优先，BSD/macOS 兜底
utc_to_epoch() {
  local t e
  t="$(normalize_utc "$1")"
  e="$(date -u -d "${t} UTC" '+%s' 2>/dev/null || true)"
  [ -n "${e}" ] || e="$(date -u -j -f '%Y-%m-%d %H:%M:%S' "${t}" '+%s' 2>/dev/null || true)"
  printf '%s' "${e}"
}

# epoch 秒 -> "YYYY-MM-DD HH:MM:SS"（UTC 视角，带 -u）
epoch_to_text() {
  local e out
  e="$1"
  out="$(date -u -d "@${e}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
  [ -n "${out}" ] || out="$(date -u -r "${e}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
  printf '%s' "${out}"
}

# epoch 秒 -> "YYYY-MM-DD HH:MM:SS"（系统真实时区，不带 -u）
epoch_to_local_text() {
  local e out
  e="$1"
  out="$(date -d "@${e}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
  [ -n "${out}" ] || out="$(date -r "${e}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
  printf '%s' "${out}"
}

# 系统时区标签：UTC 显示 UTC，其余显示 "CST +0800" 这种无歧义写法
local_zone_label() {
  local z o
  z="$(date '+%Z' 2>/dev/null || true)"
  o="$(date '+%z' 2>/dev/null || true)"
  case "${z}" in
    '' | UTC | GMT) printf 'UTC' ;;
    *)
      if [ -n "${o}" ]; then
        printf '%s %s' "${z}" "${o}"
      else
        printf '%s' "${z}"
      fi
      ;;
  esac
}

# 最终展示文本：CNB 强制北京时间，其余跟随系统真实时区
ci_time_text() {
  local plat raw epoch
  plat="$(ci_platform)"

  case "${plat}" in
    cnb) raw="${CNB_BUILD_START_TIME:-}" ;;
    gitlab) raw="${CI_PIPELINE_CREATED_AT:-}" ;;
    *) raw='' ;;
  esac

  epoch=''
  if [ -n "${raw}" ]; then
    epoch="$(utc_to_epoch "${raw}")"
  fi
  if [ -z "${epoch}" ]; then
    epoch="$(date '+%s')"
  fi
  if [ -z "${epoch}" ]; then
    printf '%s' "${raw:-未知}"
    return 0
  fi

  case "${plat}" in
    cnb) printf '%s (UTC+8)' "$(epoch_to_text "$((epoch + 8 * 3600))")" ;;
    *) printf '%s (%s)' "$(epoch_to_local_text "${epoch}")" "$(local_zone_label)" ;;
  esac
}
```

输出示例：

```text
CNB（CNB_BUILD_START_TIME=2026-11-18T05:45:30.123Z）      -> 2026-11-18 13:45:30 (UTC+8)
GitHub Actions（无时间变量，取当前时间，runner 默认 UTC） -> 2026-11-18 05:45:31 (UTC)
本机开发（macOS，CST）                                   -> 2026-11-25 21:46:11 (CST +0800)
```

## 4. GNU date 与 BSD date 对照

两个系统的 `date` 参数完全不通用，凡是涉及「字符串 ↔ epoch」都必须双写：

| 用途           | GNU（Linux / Alpine / CNB 镜像）           | BSD（macOS）                                                  |
|----------------|--------------------------------------------|---------------------------------------------------------------|
| 字符串转 epoch | `date -u -d '2026-11-18 05:45:30 UTC' +%s` | `date -u -j -f '%Y-%m-%d %H:%M:%S' '2026-11-18 05:45:30' +%s` |
| epoch 转字符串 | `date -u -d '@1731908730' '+%F %T'`        | `date -u -r 1731908730 '+%F %T'`                              |
| 当前 epoch     | `date +%s`                                 | `date +%s`（相同；`-u` 只影响格式化，不影响 `%s`）            |

判断方式就是「先试 GNU，输出为空再试 BSD」，不要靠 `uname` 猜——容器里可能是任意组合。

## 5. 自检规范

时间相关逻辑的自检**不能依赖当前时钟**，否则结果不可复现、跨时区跑会飘：

```sh
CNB_BUILD_START_TIME='2026-11-18T05:45:30.123Z'
[ "$(ci_time_text)" = '2026-11-18 13:45:30 (UTC+8)' ] && echo ok
```

`scripts/ci/render-ci-notice.sh` 的 `build_time_text()` 就是这么做的（只覆盖 CNB 的 UTC→+8 转换），可以作为落地参考。

## 6. 常见坑

1. **不要在 CNB 里靠 `TZ=Asia/Shanghai` 拿北京时间**：精简镜像（如 Alpine）没装 `tzdata` 时没有 zoneinfo，`TZ` 会被忽略、仍按 UTC 走。北京时间一律用 epoch `+8 * 3600`；本机开发直接读系统时区即可，不用手动设 `TZ`。
2. **macOS 没有 `date -d`**：`date -d '@123'` 会报 illegal option，必须换 `date -r`。
3. **`date +%s%3N` 在 macOS 不返回毫秒**：会输出 `1731908730%3N` 这种字面量，别用它算毫秒时间戳。
4. **BSD `-j -f` 要求格式完全匹配**：给 `2026-11-18T05:45:30.123Z` 直接解析会失败，必须先 `normalize_utc` 去掉 `T`、毫秒和 `Z`。
5. **带偏移的 ISO8601（`2026-11-18T05:45:30+08:00`）**：GNU 能解析，BSD 的 `-j -f` 不能。归一化时若把偏移直接切掉会丢掉实际时刻；需要严格处理时先按偏移修正 epoch 再格式化。
6. **`$(date +%s)` 不会有前导零**，但若从别处拿到带前导零的数字，`$((08))` 在 bash 里会被当八进制报错，比较/运算前先去掉前导零。
7. **不要用 `CI=true` 判断平台**，见第 1 节。
