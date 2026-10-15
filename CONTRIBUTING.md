# 参与 HnuHole 开发

采用 Feature Branch + Conventional Commits + Pull Request。规则适用于人和 agent，
核心约束见 [AGENTS.md](AGENTS.md)，PR 使用[统一模板](.github/pull_request_template.md)。

## 任务与分工

新 session 默认一个新需求，先明确目标、范围和完成标准；同一 session 的追问继续原需求。
发现无关问题另记任务。一个需求可有多个逻辑完整的 commit，最终通过 PR 交付。
每个新分支对应明确需求或子任务，不用长期万能分支承接所有工作。

开始时在实际源码仓库执行只读检查，确认位置、已有改动、分支及远端：

```sh
git rev-parse --show-toplevel
git status --short --branch
git branch -vv
git remote -v
git worktree list
```

已有暂存、未暂存和未跟踪文件须保留，不擅自 stash、reset、clean、覆盖或提交。
agent 是独立同事，分工须明确目标、文件范围、依赖、交付与验证；只有明确授权才委派。
并行写入使用独立 worktree 和分支。独立需求各开 PR；同一需求的子任务经主 agent 审查后整合。

## 分支

从最新 `origin/main` 建立分支。以下以图片预览为例，替换为本次需求名及空闲目录：

```sh
git fetch origin refs/heads/main:refs/remotes/origin/main
git worktree add -b codex/feat/image-preview ../HnuHole-image-preview origin/main
cd ../HnuHole-image-preview
```

这不会切换原工作区或修改本地 main。失败时先查看原因，不强制覆盖已有引用或目录。
Codex 命名为 `codex/<type>/<slug>`，人工可用 `<type>/<slug>`。
type 为 `feat|fix|refactor|docs|test|chore|ci|build|perf|revert`；slug 用小写英文、数字、连字符。
例：`fix/upload-timeout`、`codex/chore/collaboration-rules`。

依赖未合并功能时，可从该功能分支建立子任务分支，在 PR 写明依赖、目标和合并顺序；
不能把上游全部改动冒充本需求。独立需求仍从 main 建立。不直接向 main／master 提交、推送或强推。

## 提交

格式 `type(scope)!: 描述`，scope 与 `!` 可选，描述可用中文；type 同分支类型。
scope 用小写英文、数字、点、下划线、斜线和连字符。
破坏性变更用 `!`，正文说明迁移影响。

```text
feat(image): 支持双指缩放
fix(auth): 修复过期会话恢复
docs(workflow): 更新协作流程
```

一次提交围绕一个逻辑目的，相关实现、测试、必要文档可一起提交，不按文件机械拆分。
不要使用 `update`、`最终版`、`fixup!` 等送审标题，不依赖 squash 掩盖含糊提交。
执行检查后查看差异，明确暂存文件，再审查暂存区：

```sh
git diff
git add <本需求的文件路径>
git diff --cached
python tools/check-collaboration.py --staged
```

得到提交授权后才运行 `git commit -m "feat(image): 支持双指缩放"`。
禁止未经检查 `git add .`；提交、推送、合并、删除分支均须用户明确请求或已有授权。
授权仅在对应任务和操作范围内持续有效，不为已经授权的同一操作反复确认。
编写代码不自动授权推送、合并或部署；没有提交授权时交付可审查的本地差异。

## 文件与凭据

应提交源码、必要项目资源、依赖声明与锁文件、测试、迁移、CI、文档及脱敏配置模板。
不提交真实环境文件、密钥、个人 IDE 状态、缓存、日志、APK 或构建产物。
单个新增／修改文件超过 10 MiB 时使用 Git LFS，并在 PR 说明用途。
`.gitignore` 只影响未跟踪文件；停止跟踪先确认归属，泄漏密钥必须撤销／轮换。
公共证书和必要测试资源不等于私钥；自动检查只识别常见风险，不能代替人工审查或完整密钥扫描。

## 可选本地钩子

脚本仅使用 Python 3.9+ 标准库。可按操作临时启用，不改变其他 worktree 设置：

```sh
git -c core.hooksPath=.githooks commit -m "feat(image): 支持双指缩放"
git -c core.hooksPath=.githooks push -u origin codex/feat/image-preview
```

以上命令同样以获得对应授权为前提。钩子校验分支、暂存内容、提交标题，并阻止向 main／master 推送。
如需长期启用，先检查 `git config --get core.hooksPath`，确认没有其他钩子，再执行
`git config --local core.hooksPath .githooks`。该设置影响共享此 Git 仓库的所有 worktree；
其他 worktree 尚无这些文件时不要全局启用。本次不自动修改该配置。
本地钩子可被绕过，仍需 CI 和服务器端保护。

## PR、验证与合并

得到授权后只推需求分支：`git push -u origin <当前需求分支>`。PR 目标通常为 main，
标题使用 Conventional Commits，按模板写清需求、行为变化、影响、验证和遗留项。
至少一名独立同事 review；作者不能自批。agent review 是审查证据，不替代 GitHub 成员批准。
仅一个 GitHub 账号时，由维护者明确审查策略，不伪造第二名成员。

合并前完成适用的构建、测试与检查：

| 改动 | 验证要求 |
| --- | --- |
| 文档／协作工具 | 内容／链接及协作检查；脚本／钩子修改补聚焦回归 |
| Go 服务端 | 格式、构建、go test、go vet；事务／迁移用真实一次性 PostgreSQL 回归 |
| Flutter／原生插件 | 受影响包的 analyze、test、目标平台构建；安全存储／Passkey 补设备验收 |
| API 契约 | 仓库完整规范校验及相关实现回归，不能只用 YAML 语法检查代替 |

命令以对应模块已有入口为准。功能代码 PR 须配套自动构建／测试，不能用协作 CI 代替产品 CI。
实际通过才记 PASS；缺环境记 BLOCKED／NOT_RUN，主动跳过记 SKIP。旧版本结果保留原 SHA。
功能改动按 AGENTS 同步已有验收台账和交接；纯协作变更不修改产品验收结论。
必要验证缺失时保持 draft。推荐 Squash Merge，最终提交标题与规范化 PR 标题一致。
得到合并授权且确认合并成功后，再按授权删除完成分支／本任务 worktree；先确认无待保存内容，不强制清理。

## 进度、README 与主线同步

每个需求都须维护可追溯的工作状态。开始任务、分支交付及确认合并是必要更新节点；
范围、阻塞或验证结论变化时及时更新，无须为每个 commit 重复修改 README。

| 位置 | 内容 |
| --- | --- |
| README | 项目整体阶段、模块能力摘要、主要在研工作与详细记录入口 |
| `docs/design/progress.md` | 详细工作状态：任务、分支／PR、实现范围、合并情况、验收情况、阻塞／下一步、更新时间 |
| HANDOFF | 当前接续入口、剩余工作及下一步 |
| 模块验收台账与测试交接 | 实际命令、被测版本、覆盖范围、结果、证据及未执行项 |

沿用已有记录和稳定任务／模块 ID，不为同一状态另建重复台账；缺少对应材料时明确登记缺口。
纯文档／协作任务在对应任务记录或 PR 中维护工作状态，不改写产品验收结论。
进度以工作项组织并保留任务／PR 引用，不能仅链接可能删除的临时分支。

1. **开始任务**：登记目标、范围、分支、完成标准和当前状态；尚无 PR 时先保留任务引用，创建后补齐。
2. **分支交付**：更新实现范围、验证结果、未完成项和合并情况。影响项目能力、整体阶段、使用方式或主要在研工作时同步 README；其他变更在 PR 说明 README 无须更新的原因。
3. **提交 PR**：相关文档与本需求一起送审。分支中新增的能力注明所属分支及适用范围；PR 合并前仍记录待合并，不提前宣告已进入 main。
4. **确认合并**：核对 main 的 README 和进度记录，确保相关文档已随 PR 合入，工作状态反映实际结果。需要补充合并事实、PR 链接或合并 SHA 时通过小型文档 PR 更新；不直接提交或推送 main。未合并、撤回或延期时记录真实状态和原因。

实现完成、已合并 main、验收通过和已发布分别记录，不能用一个“完成”覆盖全部状态。
main 的 README 可展示“某分支已实现／尚未合并”，但主线已有能力只描述已合并的成果；
测试与发布结论仍须有相应版本和证据。例如“已合并；Android 部分场景通过，iOS 待验收；未发布”。

上述文档同步属于交付检查，由作者与 reviewer 核对；现有协作 CI 不自动判断进度内容是否真实或完整。

## 自动检查的范围

[协作 workflow](.github/workflows/collaboration.yml)检查 PR 分支、PR 标题、新增提交标题，
各新增提交中的常见敏感文件／产物／高置信度凭据，以及最终差异的空白错误，并运行脚本回归。
检查每个提交可避免“先提交密钥后删除”漏检；普通同步上游的 merge commit 可用 Git 生成的标题，内容仍检查。
修改 PR 标题会重新检查；main push 仅作合并后复核，不授权直接推 main。

历史已合并提交不追溯；旧长期分支接入应单独迁移，不重写共享历史来刷绿。
当前 main 尚无产品源码，本次不添加空跑的 Go／Flutter job；引入源码的 PR 必须同步补齐产品 CI。
本地检查已提交的分支：

```sh
python tools/check-collaboration.py --base origin/main --head HEAD --branch codex/chore/collaboration-rules --pr-title "chore(workflow): 规范团队协作"
python -m unittest discover -s tools/tests -p test_collaboration.py -v
```

## GitHub 设置（需实际启用）

这些设置不会因提交 Markdown 或 workflow 自动启用。由有权限的维护者配置、验证：

1. main 要求 PR 合并，禁止 force push 和删除，限制包括管理员在内的绕过。
2. 账号条件允许时至少 1 名独立成员批准，推送新代码后撤销旧批准，解决 review 对话。
3. 将实际运行过的 policy job 设为必需检查；名称以 GitHub 显示为准，产品 CI 上线后追加对应稳定 job。
4. 推荐 Squash Merge，默认 squash 标题采用 PR 标题；允许自动删除合并后的 head 分支须由维护者授权配置。
5. 启用账号／仓库支持的 secret scanning 和 push protection。

规则文件和 workflow 合入不代表远端分支保护已开启，须以实际配置和验证结果为准。
依据：[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)、
[GitHub 分支保护](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)、
[Actions 事件](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)。
