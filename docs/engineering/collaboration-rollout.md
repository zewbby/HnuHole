# 协作规范落地记录

日期：2026-10-15。范围仅为协作规则、文档、模板、忽略规则和协作检查，不修改产品行为或验收结论。

## 准备阶段检查快照

- 聊天入口目录 `C:\Users\24237\Documents\ChatGPT\Hnuhole` 是无提交、无远端的外层仓库，存在三份未跟踪交接文件，本次未修改。
- 实际项目位于 `E:\Hnuhole-env\source\HnuHole`，origin 为 `zewbby/HnuHole`。
- 原工作区在 `codex/auth-privacy-handoff`，HEAD 为 `d859cb0`，只有 README.md 的未提交改动；本次保留其分支、暂存区和文件内容。
- 抓取的 main 为 `8a6dabf30a4df228f3e3681cf772d504781c3ba4`，仅有设计与工程文档。认证分支在它之后有 58 个提交，不能混进本次规范变更。
- 认证分支已有 AGENTS 的验收／清理约束；main 尚无 AGENTS、PR 模板、钩子或 Actions workflow。
- 原工程指南仍描述未绑定远端、初始化提交和直接推 main，已被统一贡献规范取代。

## 方案与边界

从 origin/main 建立 `codex/chore/collaboration-rules`，工作目录为
`E:\Hnuhole-env\source\HnuHole-collaboration`，不切换原工作区，不修改 main。

采用 AGENTS 核心约束 + CONTRIBUTING 完整细则 + PR 模板 + 可选钩子 + 协作 CI，暂不制作 Skill。
保留认证分支已有的测试如实记录、SQL／设备边界与清理约束；不把历史固定开发分支变成所有新任务的入口。
准备阶段未执行项目 commit、push、PR 创建、合并、分支删除、部署或 GitHub 设置变更，也未更改共享 hooksPath。
回归测试仅在一次性仓库中创建合成提交及本地 bare remote，不接触项目历史或远端。

选择这些边界的原因：

- session 是需求默认入口，同一 session 内的修正不必另开分支；agent 同事关系不自动授权委派。
- agent review 与 GitHub 成员批准分别记录，只有一个账号时不虚构独立批准。
- 钩子配置会影响所有共享 worktree，因此提供临时启用方式，避免干扰既有认证工作。
- 检查读取 index／提交对象，逐个检查 PR 新增提交，覆盖已删除的历史密钥和合并时新加的内容。
- 只报告可疑文件位置，不输出命中的凭据或 diff 内容；PR 标题作为 JSON 数据读取，不插入 shell。
- 公共证书不按私钥一概封禁；扫描只覆盖少数高置信度格式，仍需人工审查和可用的 secret scanning。
- main 尚无产品源码，本次协作 CI 不虚设产品测试。引入代码的 PR 须同步补齐对应自动构建／测试。

## 进度同步规则补充（2026-10-15）

按用户确认补充 AGENTS、CONTRIBUTING 和 PR 模板：每个需求在开始、交付和确认合并时同步工作状态；
README 展示整体阶段与能力摘要，详细状态沿用 progress，接续与证据分别沿用 HANDOFF 和验收台账。
实现、合并、验收、发布分别登记，未合并成果注明分支归属。相关文档随功能 PR 送审，合并后核对 main，
需要补充时通过文档 PR 更新。纯文档／协作任务在任务记录或 PR 中登记，不改写产品验收结论。

本次仅补充规则和人工自检项，未新增自动检查，也未执行分支进度盘点或更改产品状态。
规则补充完成时保留为本地可审阅差异，未提交、推送或合并；后续交付安排见下方。
README 本次无须更新：本补充不改变项目能力、整体阶段、使用方式或主要在研工作。
四份变更文档及已有暂存文件的协作策略、本地链接和差异空白检查通过，原暂存区内容保持不变。

## 本地验证

- Windows Python 3.9：19 项回归 PASS。
- WSL Linux Python：相同 19 项回归 PASS，实际执行 commit-msg、pre-commit、pre-push 钩子。
- 覆盖正常／异常分支和标题、锁文件与模板保留、常见产物和凭据、超过 10 MiB 的文件、暂存区与工作区不一致、历史密钥已删除、合并新内容、正常 merge、空白错误、PR 元数据、main push 事件和保护分支推送目标。
- workflow 本地 YAML 结构检查 PASS：只读权限、完整历史、标题修改触发、无 pull_request_target；这不等于 GitHub Actions 实跑。
- 最终内容另经暂存文件检查、差异空白检查和新增文档本地链接核对。

## 交付与待接入事项

2026-10-15 用户已授权将本协作规范分支通过 PR 合并 main，包含必要的提交、推送与 PR 创建。
合并前重新执行 Windows 下全部 19 项协作回归，均 PASS；复核范围仅为规则、钩子、workflow 与检查工具。
独立 agent 审查作为审查证据记录在交付说明中，不冒充 GitHub 成员批准。
最终合并状态、提交 SHA 和 GitHub Actions 结果以本需求关联 PR 及对应运行记录为准。
main 合并后核对规则、模板、workflow 与进度同步细则是否完整进入主线；本任务不代表产品验收或生产发布。

GitHub 分支保护／必需检查未在本任务中配置，不宣称远端已强制执行。
由维护者按 CONTRIBUTING 配置并验证仓库设置；共享 hooksPath 保持原设置。
其他分支须同步规则才会采用新 AGENTS；认证长期分支将来合并时需保留其专门验收要求，处理 AGENTS 的 add/add 冲突，单独安排历史提交规范的迁移，不重写共享历史。
