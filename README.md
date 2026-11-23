# ci-templates

CNB（云原生构建）流水线模板与配套脚本仓库。业务仓库通过 `.cnb.yml` 的 `include` 引用本仓库的 YAML，即可复用代码评审、安全扫描、SCA、Code Wiki 与知识库构建，并把结果统一推送到企业微信 / 飞书 / 钉钉。

[![漏洞扫描](https://cnb.cool/dtapp/ci-templates/-/badge/security/vulnerability/full/latest)](https://cnb.cool/dtapp/ci-templates/-/security) [![CNB 访问](https://commit.cool/badge/visit/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 星标](https://cnb.cool/dtapp/ci-templates/-/badge/star)](https://cnb.cool/dtapp/ci-templates) [![CNB 分叉](https://cnb.cool/dtapp/ci-templates/-/badge/fork)](https://cnb.cool/dtapp/ci-templates) [![CNB 仓库年龄](https://commit.cool/badge/age/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 主要语言](https://commit.cool/badge/language/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 许可证](https://commit.cool/badge/license/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB 存储用量](https://commit.cool/badge/usage/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB Git 存储](https://commit.cool/badge/usage/git/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates) [![CNB LFS 存储](https://commit.cool/badge/usage/lfs/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates)

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

## 格式化

`Makefile` 提供配置 / 文档类文件的格式化入口，底层是 `scripts/format.sh`：

```sh
make format                 # YAML + JSON + SQL + Markdown + Dockerfile + Shell
make format-yaml            # 仅 YAML，其余同理：format-json / format-sql / format-markdown / format-docker / format-shell
scripts/format.sh yaml      # 直接调用脚本，支持 yaml|json|sql|shell|markdown|docker|all
FORMAT_STRICT=1 make format # 工具缺失时直接失败（默认只打印安装提示并跳过）
```

涉及工具：`yamlfmt`、`gojq`、`sql-formatter`、`markdownfmt`、`shfmt`、`dockerfmt`。脚本不会自动安装工具，缺失时会打印对应的 `go install` 命令。格式化目标路径和参数集中在 `scripts/format.sh` 顶部的「可自定义配置区」，移植到其他项目时只需修改这一段。

## 多远程同步

`Makefile` 中的 `sync` / `push` / `push-force` 用于同时操作多个远程，远程列表来自 `GIT_REMOTE`（逗号分隔），优先级为：环境变量 > `.env` > 默认值 `origin`。

```sh
GIT_REMOTE=origin,github make sync
```

`sync` 会依次 `fetch` 并 `merge --ff-only`，然后向所有远程 `push`；`push-force` 会执行 `git push --force`，使用前请确认影响。

## 许可证

见 [LICENSE](LICENSE) 文件。

## Star 走势

<details>
<summary><b>点击展开查看图表</b></summary>

[![CNB Star 走势](https://commit.cool/stars/dtapp/ci-templates)](https://cnb.cool/dtapp/ci-templates)

</details>
