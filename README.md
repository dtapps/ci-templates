# ci-templates

CNB（云原生构建）流水线模板与配套脚本仓库。业务仓库通过 `.cnb.yml` 的 `include` 引用本仓库的 YAML，即可复用代码评审、安全扫描、SCA、Code Wiki 与知识库构建，并把结果统一推送到企业微信 / 飞书 / 钉钉。

[![CNB 访问](https://commit.cool/badge/visit/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 仓库年龄](https://commit.cool/badge/age/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 主要语言](https://commit.cool/badge/language/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 许可证](https://commit.cool/badge/license/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates)

[![npm 版本](https://img.shields.io/npm/v/@dtapp/ci-templates?label=npm)](https://www.npmjs.com/package/@dtapp/ci-templates) [![npm 月下载](https://img.shields.io/npm/dm/@dtapp/ci-templates?label=%E6%9C%88%E4%B8%8B%E8%BD%BD)](https://www.npmjs.com/package/@dtapp/ci-templates) [![npm 近18月下载](https://img.shields.io/npm/d18m/@dtapp/ci-templates?label=%E8%BF%9118%E6%9C%88%E4%B8%8B%E8%BD%BD)](https://www.npmjs.com/package/@dtapp/ci-templates) [![许可证](https://img.shields.io/npm/l/@dtapp/ci-templates?label=%E8%AE%B8%E5%8F%AF%E8%AF%81)](https://github.com/dtapps/ci-templates/blob/main/LICENSE) [![安装体积](https://img.shields.io/npm/unpacked-size/@dtapp/ci-templates?label=%E5%AE%89%E8%A3%85%E4%BD%93%E7%A7%AF)](https://www.npmjs.com/package/@dtapp/ci-templates) [![jsDelivr 月下载](https://data.jsdelivr.com/v1/package/npm/@dtapp/ci-templates/badge)](https://www.jsdelivr.com/package/npm/@dtapp/ci-templates) [![Socket 安全评分](https://socket.dev/api/badge/npm/package/@dtapp/ci-templates)](https://socket.dev/npm/package/@dtapp/ci-templates)

## 模板一览

| 文件                       | 触发事件                           | 作用                                                                                               |
|----------------------------|------------------------------------|----------------------------------------------------------------------------------------------------|
| `code-review.yml`          | `pull_request`                     | 调用 `cnbcool/code-review` 做 AI 代码评审，输出 `code_review.json`，渲染后通知三个 IM 平台         |
| `cnb-sechook.yml`          | `pull_request`                     | 读取 `cnbcool/cnb-sechook` 生成的 `sec_overview.md`，汇总敏感信息与漏洞统计并通知                  |
| `sca.yml`                  | `push`、`pull_request.target`      | 开源组件漏洞 / License 全量与增量扫描、SBOM 生成；PR 侧开启 `high` 门禁，结果通过 `endStages` 通知 |
| `code-security-config.yml` | `pull_request`                     | 调用 `cnbcool/code-security-config validate` 自检代码安全扫描配置                                  |
| `codewiki.yml`             | `tag_push`、`web_trigger_codewiki` | 生成 Code Wiki，文档写入 `/${CNB_BUILD_WORKSPACE}/${CNB_REPO_SLUG}/codewiki`                       |
| `knowledge-base.yml`       | `push`、`tag_push`、`issue.*`      | 构建知识库，并在 Issue 创建 / 关闭 / 重开 / 更新 / 评论时同步                                      |

## 在业务仓库中接入

在目标仓库根目录的 `.cnb.yml` 中按需 `include`：

```yaml
include:
  - https://cnb.cool/dtapp/ci-templates/-/blob/main/code-review.yml
  - https://cnb.cool/dtapp/ci-templates/-/blob/main/cnb-sechook.yml
  - https://cnb.cool/dtapp/ci-templates/-/blob/main/sca.yml
```

说明：

- URL 格式为 `https://cnb.cool/<repo-slug>/-/blob/<ref>/<file>`；生产环境建议把 `main` 换成固定的分支或 tag，避免模板变更影响构建。
- 合并规则：本地 `.cnb.yml` 覆盖 `include` 的内容，`include` 数组中后引入的文件覆盖先引入的文件。
- 通知类模板通过 `imports` 从私有仓库 `https://cnb.cool/dtapp/envs/-/blob/main/webhook.yml` 注入 webhook 密钥；跨仓库引用时需要在该配置文件中配置 `allow_slugs` / `allow_events` 等访问权限。
- 需要的环境变量：`WECOM_BOT_WEBHOOK`、`FEISHU_BOT_WEBHOOK`、`DINGTALK_BOT_WEBHOOK`、`DINGTALK_BOT_SECRET`。模板中的通知 stage 均设置了 `allowFailure: true`，通知失败不会阻塞主流程。
- 渲染脚本默认不在业务仓库中；stage 会在 `scripts/ci/render-ci-notice.sh` 不存在时从 `https://cnb.cool/dtapp/ci-templates/-/git/raw/main/scripts/ci/render-ci-notice.sh` 下载，因此构建环境需要能访问 `cnb.cool`。也可以提前把脚本复制到目标仓库的同名路径，跳过下载。

更多背景见 CNB 文档：[文件引用](https://docs.cnb.cool/zh/build/file-reference.html)、[语法手册 · include](https://docs.cnb.cool/zh/build/grammar.html#include)、[触发规则](https://docs.cnb.cool/zh/build/trigger-rule.html)。

## 通知正文渲染脚本

`scripts/ci/render-ci-notice.sh` 是三个通知模板共用的 POSIX sh 脚本，把插件输出统一渲染成三种平台的正文：

```sh
sh scripts/ci/render-ci-notice.sh sechook [输出.md]
sh scripts/ci/render-ci-notice.sh review  [输出.md]
sh scripts/ci/render-ci-notice.sh sca full|diff [输出.md]
sh scripts/ci/render-ci-notice.sh --self-test
```

每次渲染会生成：

- `<name>_notice.md`：Markdown 版，链接为 `[查看详情](URL)`，供企业微信 `fromFile` 和钉钉 `content` 使用；
- `<name>_notice.txt`：纯文本版，URL 裸写，供脚本内部继续转换；
- `<name>_notice_feishu.json`：飞书 `post` 富文本，链接是可点击的 `a` 标签。

正文通过 `##[set-output ...]` 以 base64 导出，对应 key 分别为 `scan` / `scan_text`、`review` / `review_text`、`sca` / `sca_text`。脚本依赖 `jq`、`curl`、`base64`、`date`，流水线中使用镜像 `docker.cnb.cool/dtapp/alpine:latest`；本地自检需先安装 `jq`。

## 脚本同步（`scripts/ci/fetch-scripts.sh`）

`scripts/ci/fetch-scripts.sh` 是给业务仓库用的自举脚本：文件顶部固定四个同源仓库和一份脚本清单，运行时按清单把脚本下载到**与模板仓库完全一致的相对路径**。业务仓库只要保留这一个文件，就不必手工复制或逐个跟版本。

```sh
sh scripts/ci/fetch-scripts.sh            # 同步：缺失的下载，已存在的比 sha256，不同则更新
sh scripts/ci/fetch-scripts.sh --force    # 不做比对，已存在也直接覆盖
sh scripts/ci/fetch-scripts.sh --check    # 只查存在性（不下载、不比对），缺失时退出码 1
sh scripts/ci/fetch-scripts.sh --list     # 查看清单与候选源顺序
```

四个源仓库内容一致，脚本探测当前 CI 平台并用同平台仓库：CNB → GitHub → Gitee → GitLab；一个都匹配不上（本地开发等）时按同一顺序取，即默认 CNB。某个源取不到文件（超时、404）会自动换下一个源，回退是每个文件独立的，全部失败才报错；加 `--no-fallback` 可关掉回退。也可用 `--source cnb|github|gitee|gitlab` 指定起点源，`CI_TEMPLATES_REF` 固定分支或 tag（默认 `main`）。

各平台下载地址格式不同：GitLab 是 `/-/raw/<ref>/<path>`，Gitee 是 `/raw/<ref>/<path>`（302 到内容域，靠 `curl -L` 跟随）。GitCode 没有可用的 raw 地址（网页 raw 对 `.sh` 只返回 HTML / 403「暂不支持预览」，只有 `api.gitcode.com` 的 raw API 能取到文件），因此未纳入。

本地已有同名文件时不会直接信任：先下载远端内容算 sha256，与本地一致就跳过、不一致就覆盖，所以仓库里不会停着旧版本脚本。下载先写临时文件、比对通过才 `mv`，失败不会破坏已有文件；`.sh` 必须以 `#!` 开头才落盘，避免把错误页面写成脚本。当前清单：`scripts/ci/delete-release.sh`、`scripts/ci/describe-artifact.sh`、`scripts/ci/render-ci-notice.sh`。

时间 / 日期的取值与时区约定见 [`scripts/ci/time-and-date.md`](scripts/ci/time-and-date.md)（CNB 用北京时间，其余用 UTC）。

## 格式化

`Makefile` 提供配置 / 文档类文件的格式化入口，底层是 `scripts/format.sh`：

```sh
make format                 # YAML + JSON + SQL + Markdown + Dockerfile + Shell
make format-yaml            # 仅 YAML，其余同理：format-json / format-sql / format-markdown / format-docker / format-shell
scripts/format.sh yaml      # 直接调用脚本，支持 yaml|json|sql|shell|markdown|docker|all
FORMAT_STRICT=1 make format # 工具缺失时直接失败（默认只打印安装提示并跳过）
```

涉及工具：`yamlfmt`、`gojq`、`sql-formatter`、`markdownfmt`、`shfmt`、`dockerfmt`。脚本不会自动安装工具，缺失时会打印对应的 `go install` 命令。格式化目标路径和参数集中在 `scripts/format.sh` 顶部的「可自定义配置区」，移植到其他项目时只需修改这一段。

## 脚本压缩

`make minify-shell` 把 `scripts/` 下的 shell 脚本生成紧凑副本，产物在 `dist/minify/`（已加入 `.gitignore`），原文件不动：

```sh
make minify-shell                  # 压缩全部 .sh
make minify                        # 全部压缩产物（目前只有 Shell）
scripts/minify.sh shell a.sh b.sh  # 只压指定文件
MINIFY_OUT=build/min make minify   # 换产物目录
```

压缩会删掉整行注释和空行，但有三处必须原样保留，否则脚本会被改坏：shebang；第 2 行到第一个空行的头部注释块（`delete-release.sh` / `fetch-scripts.sh` 的 `usage()` 靠 `sed -n '2,/^$/p' "$0"` 从这里取正文，删了 `--help` 就废）；以及 heredoc 内部（脚本清单、自检用例都在里面）。行首缩进同样不动。

每个产物写入前都会过两道校验：按 shebang 选 `sh -n` / `bash -n` 做语法检查，并比对头部用法段与原文件一致；任一不通过就报错且不写盘。

## 多远程同步

`Makefile` 中的 `sync` / `push` / `push-force` 用于同时操作多个远程，远程列表来自 `GIT_REMOTE`（逗号分隔），优先级为：环境变量 > `.env` > 默认值 `origin`。

```sh
GIT_REMOTE=origin,github make sync
```

`sync` 会依次 `fetch` 并 `merge --ff-only`，然后向所有远程 `push`；`push-force` 会执行 `git push --force`，使用前请确认影响。

## 仓库

| 平台    | 地址                                   |
|---------|----------------------------------------|
| CNB     | https://cnb.cool/dtapp/ci-templates    |
| GitHub  | https://github.com/dtapps/ci-templates |
| Gitea   | https://gitea.com/dtapps/ci-templates  |
| GitLab  | https://gitlab.com/dtapps/ci-templates |
| Gitee   | https://gitee.com/dtapps/ci-templates  |
| GitCode | https://gitcode.com/dtapp/ci-templates |

## 许可证

见 [LICENSE](LICENSE) 文件。

## Star 走势

<details>
<summary><b>点击展开查看图表</b></summary>

**CNB**

[![CNB Star 走势](https://commit.cool/stars/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates)

**GitHub**

[![Star 走势](https://api.star-history.com/chart?repos=dtapps/ci-templates&type=date&legend=top-left)](https://www.star-history.com/?repos=dtapps%2Fci-templates&type=date&legend=top-left)

</details>

## 下载量统计图

<details>
<summary><b>点击展开查看图表</b></summary>

[![下载量统计图](https://release-monitor.com/chart/dtapps/ci-templates.svg?stable=5)](https://release-monitor.com/#/dtapps/ci-templates)

</details>
