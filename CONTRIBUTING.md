# 参与 SpeechFUL 开发

本仓库使用 Feature Branch、Conventional Commits 和 Pull Request。[AGENTS.md](AGENTS.md) 规定模式入口、需求确认和工程底线；本文保存具体操作。[PR 模板](.github/pull_request_template.md)用于送审。

## 任务入口

任务记录的适用范围按 AGENTS.md 执行，使用[模板](docs/tasks/TEMPLATE.md)填写相关字段。PR、Issue、提交和验证证据链接到已有记录，避免复制同一结论。

需求是否需要收敛按 [AGENTS.md 的需求确认规则](AGENTS.md#需求确认)判断。使用 `grill-with-docs` 时读取该 Skill 及其依赖的 `grilling`、`domain-modeling` 指南，按其流程提问和记录，不能仅声明使用却静默替换。技能列表未列出时，先在仓库或用户技能目录查找同名 `SKILL.md`；确实不可用时说明限制。需求结论与确认依据写入已有任务记录；领域术语发生变化时更新适用词汇表，ADR 仅用于有实际取舍且难以逆转的决策，不为每次修复额外创建文档。

开始时在实际源码仓库核对位置和已有工作：

```sh
git rev-parse --show-toplevel
git status --short --branch
git branch -vv
git remote -v
git worktree list
```

保留已有暂存、未暂存和未跟踪文件，不擅自 stash、reset、clean、覆盖或提交。历史 `docs/design/HANDOFF.md`、`docs/design/progress.md` 和 `docs/branches/` 保留原时点事实；只有产品契约或既有验收结论确实改变时才更新相应材料，不为同步状态重复改写它们。

## 分支与 Worktree

常规模式使用一个任务分支；指挥模式使用一个集成分支，以及各执行 Session 的独立分支与 Worktree。常规任务分支与集成分支通常从最新 `origin/main` 建立，执行分支从已约定的集成版本或依赖版本建立；依赖未合并功能时记录实际基线。Codex 分支格式为 `codex/<type>/<slug>`；type 为 `feat|fix|refactor|docs|test|chore|ci|build|perf|revert`，slug 使用小写英文、数字和连字符。人工分支可省略 `codex/`。不在 `main`／`master` 开发，也不直接推送或强推共享分支。

并行写入必须使用不同分支和 Worktree，不让多个执行 Session 改同一工作区。独立需求分别送审；同一需求的模块由负责人在集成分支核对接口、测试和差异后整合。依赖尚未合并的功能分支时，在任务记录与 PR 写清基线、依赖和合并顺序。

指挥模式的版本传递、契约变更通知和中断恢复按[派单协议](.agents/skills/orchestrator/references/dispatch.md)执行。首次接单、恢复或规则／契约变化时复核并回报；同一 Session 使用同一版本持续执行时无需重复确认。

```sh
git fetch origin refs/heads/main:refs/remotes/origin/main
git worktree add -b codex/feat/example ../SpeechFUL-example origin/main
```

这不会切换原工作区。失败时先确认引用与目标目录，不强制覆盖。清理前核对归属、提交及未提交／未跟踪内容，保存需保留的成果，确认无后续依赖且已有授权覆盖清理。本任务创建的临时验证 Worktree 满足这些条件即可移除，无需合并；功能分支还需确认已合并，或用户已明确放弃／授权移除。已有授权覆盖正常清理时无需重复申请。

## 提交与文件

提交和 PR 标题采用 `type(scope)!: 描述`；scope 和 `!` 可选，破坏性变更在正文说明影响。一个提交表达一个逻辑完整的目的，相关实现、测试和必要文档可以一起提交。提交前审查差异，明确暂存路径，再检查暂存区：

```sh
git diff
git add <本任务的明确路径>
git diff --cached
python tools/check-collaboration.py --staged
```

禁止未经检查使用 `git add .`。在用户已授权的开发范围内，可以作必要的本地提交；Push、创建 PR 和合并分别以用户授权与仓库规则为准，不把一次授权延伸到部署或其他任务。

只提交源码、必要资源、测试、迁移、依赖与锁文件、脱敏配置模板和文档。禁止提交真实密钥、环境文件、个人 IDE 状态、缓存、日志和构建产物。单个新增／修改文件超过 10 MiB 时使用 Git LFS 并说明用途。`.gitignore` 不会移除已跟踪文件；发现凭据泄漏须撤销或轮换。公共证书可以是必要测试资源，但绝不能与私钥混淆。

可按操作临时使用 `.githooks`：

```sh
git -c core.hooksPath=.githooks commit -m "docs(workflow): 更新协作规范"
```

长期修改 `core.hooksPath` 会影响共享仓库的 Worktree，先核对现有配置。钩子不能替代 CI 或服务器端保护。

## 实现与验证

把已确认场景落实为验收预期，再实现最小可运行链路。涉及列表模式时，按改动范围自验“切换 → 选中态 → 数据／刷新 → 分页 → 返回”等相关路径；其他交互选择对应的完整路径，不要求所有任务跑同一清单。给用户试用前先自行完成可执行的路径检查；无法验证的部分明确标记，不能把用户试用当作首次交互自验。

先用可用的最小链路与聚焦检查发现问题，再批量安排完整回归、构建和装机，减少每补一个局部表现就重打包。后端链路所需的真实数据库检查与必要安全 Gate 按风险执行；工具或测试失败先定位原因，再复跑受影响项。请求发出、单个控件测试或构建成功只证明对应范围，测试预期不得仅从实现本身推导。

| 改动 | 适用验证 |
| --- | --- |
| 文档、Skill、协作工具 | 内容与链接、Skill 格式、差异空白及协作检查；脚本或钩子变更加聚焦回归 |
| Go 服务端 | 格式、构建、`go test`、`go vet`；事务与迁移用明确归属的一次性真实 PostgreSQL |
| Flutter／原生插件 | 受影响包的 analyze、test 和目标平台构建；安全存储、Passkey 等按场景补设备验收 |
| API 契约 | 仓库完整规范校验及相关实现回归，不能只用 YAML 语法检查代替 |
| 跨模块或发布候选 | 实际端到端链路、必要的性能／真机／独立审查及适用 CI |

验证记录绑定实际被测内容：已提交代码记录提交 SHA；本地提交前可记录基线 SHA＋明确的被测差异，并通过已有差异记录、补丁或随后承载同一内容的提交定位，另记环境、命令、覆盖范围与证据。交付时核对最终代码与证据是否对应；相关实现、测试或环境变化后聚焦复验。仅任务进度／证据文档更新不使原产品测试证据失效，注明其适用范围即可；当前 PR head 的适用 CI 仍须满足。

结果标记按 AGENTS.md 执行；旧结果保留原版本和证明范围。无 DSN 的测试、内存替身、编译检查、测试 APK 或文件 marker 不证明真实 SQL、原生存储、整机或生产验收，缺必要验证时保持待验或 draft。

功能代码 PR 需要对应产品构建和测试 CI；[协作 workflow](.github/workflows/collaboration.yml)只检查协作规范。修改共享授权、迁移、会话或存储边界时，重新打开受影响模块的回归项。纯文档或协作任务无需运行产品全套验收，也不改写产品验收结论。

### 认证、数据库与测试资源

受保护业务保留 C Safety Gate 的最终业务事务、会话状态／代次和资源归属检查；V 独立 Gate、原生 Passkey、iOS 和生产缺口分别记录。延期验收不等于授权扩大功能范围。原 AC01–AC06、B03／B05 等暂停或延期项，仅按当次指定任务执行。

会 reset schema 的 authlab fixture 只能连接明确归属的一次性开发／升级库，不能连接未知库、正式库或真实用户库。相关 Windows 服务端、POSIX runner 和 Gate 文件沿用 WSL2 Linux 文件系统要求。测试结束后先检查下游任务对数据库、证书、设备、进程及其他资源的依赖，再清理本任务创建的资源；不执行全局 prune，不删除用户数据、现成 SDK／AVD 或未知 Docker 卷，也不因缺工具自动恢复大型缓存。

## PR、审查与交付

按[统一模板](.github/pull_request_template.md)说明目标、差异、依赖、验证、遗留问题及任务记录。适用检查通过后送审；需要的独立审查要记录审查人和范围。AI 审查不能计为 GitHub 成员批准，作者不能自批。只有一个 GitHub 账号时，如实说明维护者的审查安排。

Push 仅推已授权任务范围内的分支，包括指挥模式的集成或执行分支；沿用本任务已有授权，不逐阶段重复申请。合并前核对当前 PR head 的 CI 与测试证据，正式发布前完成相关安全与运营验收。推荐 Squash Merge，最终标题仍遵循提交格式。任务记录区分实现、验证和发布，引用对应 PR 的实时 CI／合并状态；仅为同步这些状态无需另建文档 PR。合并、部署的授权边界仍以 AGENTS.md 为准。

相关规则修订集中审查，以 Git 提交和 PR 作为版本与交付入口；只有审阅者无法访问所需内容时才导出必要审阅包，不逐轮生成 ZIP、补丁与源码指纹清单。进度沟通突出用户可见的行为变化、实际阻碍和下一步，省略常规命令流水账。

README 保留项目介绍和主要入口。仅在项目能力、使用方式或重要入口改变时更新；单个任务的状态留在 `docs/tasks/`。原有历史进度文档无需批量迁移。

## 自动检查与仓库设置

协作 workflow 检查 PR 分支、标题、新增提交、常见敏感文件与凭据、构建产物及差异空白，并运行协作脚本回归。这些检查不等于产品测试或完整密钥扫描。可本地运行：

```sh
python -m unittest discover -s tools/tests -p test_collaboration.py -v
python tools/check-collaboration.py --staged
```

仓库维护者须在 GitHub 实际配置并验证 main 的 PR 保护、适用必需检查、禁止强推／删除、独立成员批准策略，以及可用的 secret scanning 和 push protection。提交规则文件不会自动启用这些设置。
