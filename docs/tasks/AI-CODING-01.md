# AI-CODING-01 — 双模式 AI Coding 工作流落地

- 模式：常规
- 负责人／状态维护人：当前开发 Session
- 分支／Worktree／PR：本轮 `codex/docs/workflow-efficiency`；原工作流与需求确认规则分别已由 [PR #90](https://github.com/zewbby/SpeechFUL/pull/90)、[PR #93](https://github.com/zewbby/SpeechFUL/pull/93) 合并，本轮 CI／合并结果见本分支对应 PR 和最终交付记录
- 授权依据与边界：用户明确要求将未落实的效率反思补到 AGENTS.md、CONTRIBUTING.md，精简重复规则，检查通过后直接推送、合并；本轮仅修改这两份规范与已有任务记录，不代替用户确认推荐／最新的产品选择。
- 基线：原始工作流基线 `31a05d9`；本次需求确认修订基线 `origin/main` `76501d1a13c13ab0fa4a0919110c3bd00a2eba1c`
- 更新日期：2026-10-30
- 状态：原工作流与需求确认规则已合并；本轮效率规则补充已实现，本地文档检查 PASS，远端 CI／合并以本分支对应 PR 实时状态为准；未发布

## 目标与范围

按用户 2026-10-29 的 V1.0 方案，在 SpeechFUL 仓库建立常规模式与显式 `$orchestrator` 指挥模式。交付精简的 AGENTS.md、操作性 CONTRIBUTING.md、仓库内 Orchestrator Skill、简短任务契约、统一任务记录格式和[原生形状的可编辑 PPTX 流程图](../design/speechful-ai-coding-workflow-v1.pptx)。

本次是协作规范与图示变更，不修改产品行为、现有功能验收结论或 GitHub 仓库设置。实际开发任务试运行与 V1.1 修订属于后续工作。

规则覆盖常规／指挥分支关系、临时 Worktree 清理、契约变更通知与按需版本确认、只读任务及相关小改的记录方式，以及提交前验证与最终代码的证据对应。

本轮根据“修复最新帖子排序”会话的返工过程，明确 `grill-with-docs` 的触发条件、Skill 查找和依赖读取、用户确认依据，以及由已确认场景推导的交互与数据验收。

## 接口与依赖

- 现有 `AGENTS.md`、`CONTRIBUTING.md` 和 PR 模板保持一致；既有认证、数据库、安全 Gate 与资源清理约束继续适用。
- 新任务状态以 `docs/tasks/<ID>.md` 为唯一权威入口；历史 `docs/design/HANDOFF.md`、`progress.md` 与 `docs/branches/` 保留原时点事实。
- 指挥 Skill 只在用户显式调用时启用，执行 Session 的分支和 Worktree 彼此隔离。

## 验收标准

- AGENTS.md 清楚定义默认常规模式、显式指挥模式、授权边界和工程底线。
- Skill 的五阶段流程、五项派单协议与交付门槛完整，且配置为仅显式调用。
- 首次派单、恢复或规则／契约变化时核对实际生效的规则与可读的任务契约版本，明确状态维护人；中断恢复先核对已有 Session、分支和未提交工作。
- 常规任务分支、集成分支与执行分支关系清楚；临时验证 Worktree 无需合并即可在成果已保存、无后续依赖且已有授权覆盖清理时移除。
- 契约变更通知受影响执行 Session；相同规则和契约下持续执行无需重复确认。只读任务免建文档，相关小改可复用同一任务记录。
- 本地提交前验证可记录基线 SHA＋明确差异，交付时核对最终代码；仅进度／证据文档更新不触发无关产品测试重跑。
- 业务含义、交互或模式关系未决时，先以 `grill-with-docs` 收敛并获得关键选择的用户确认，再修改受影响实现；已确认事项不重问，确定性小改不强制新增讨论。
- 任务模板及 PR 入口指向唯一任务状态；现有安全与测试真实性要求未丢失。
- PPTX 流程图的节点与连线均为可编辑原生对象，内容与 V1.0 方案一致。
- 文档链接、Skill 校验、仓库协作检查、PPTX 渲染检查通过，未执行的产品测试如实标注。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 文档与 Skill | 原始 V1 `30d6659`；反馈修订 `61f185c` | PASS：本地链接检查、UTF-8 下的 Skill quick_validate 和差异空白检查 |
| 通用规则与派单协议对齐 | `36afff3`；Windows Python 3.9.13 | PASS：执行 Session 的规则和契约版本复核、授权记录及状态维护人职责已写入；Skill quick_validate、差异空白和 staged 协作检查通过 |
| 五项优化 | 基线 `d252d83`＋本次提交的文档差异：AGENTS.md、CONTRIBUTING.md、Orchestrator Skill 与两个参考文件、任务／PR 模板及本记录；Windows Python 3.9.13 | PASS：五项规则一致性复核；20 个本地文件链接、UTF-8 下的 Skill quick_validate、`python tools/check-collaboration.py --staged` 及差异空白检查通过 |
| 需求确认规则修订 | 基线 `76501d1`＋本次六份文档差异：AGENTS.md、CONTRIBUTING.md、Orchestrator Skill、delivery-gates.md、任务模板及本记录 | PASS：对照原会话复核触发条件及确认依据；22 个本地文件链接、Skill quick_validate、staged 协作与差异空白检查通过。新会话实际行为尚未验证 |
| 效率反思落实与去重 | 实际分支基线 `1099fa2`＋本轮 AGENTS.md、CONTRIBUTING.md 及本记录差异 | PASS：文档一致性复核、13 个本地文件链接、差异空白及 staged 协作检查通过；未改产品或检查脚本，实际执行效果仍待真实任务检验 |
| 协作回归 | 反馈修订 `61f185c`，Windows Python 3.9.13 | PASS：19 项 `test_collaboration.py` 回归 |
| 规则版本接续 | 临时旧基线 Worktree `31a05d9`；规则与任务契约 `30d6659` | PASS：旧工作区可读指定任务文档；定向引入 `AGENTS.md`、`CONTRIBUTING.md` 后，两份工作树文件的 Git blob 与规则提交一致；临时 Worktree 已清理 |
| PPTX | 已提交版本 `30d6659` 的 `speechful-ai-coding-workflow-v1.pptx`；SHA-256 `d482fe930078cc5f0d566815eed4f006e0c2b478ec7c77df1548a5ea343b9893` | PASS：2 页已导入并渲染；原生形状与连接线，无图片替代；包与布局检查通过 |
| 产品构建／真机 | 无产品代码变更 | NOT_RUN：不适用本次任务 |
| 实际多 Session 试运行 | 尚未显式调用 `$orchestrator` 执行开发任务 | NOT_RUN：属于后续试运行，不以 Worktree 机制检查代替 |
| 远端 CI／合并 | [PR #90](https://github.com/zewbby/SpeechFUL/pull/90) 当前 head | 分支已推送；CI 与合并结果以该 PR 实时状态为准，不将创建 PR 记为检查或合并通过 |

## 阻碍与下一步

原工作流与需求确认规则已在 PR #90、#93 合并。本轮补齐关联交互的基本自验责任、昂贵验证的安排、简短进度沟通及 Git／PR 交付入口，合并重复条款；检查后按已有授权推送、合并，结果以对应 PR 实时状态及最终交付记录为准。规则对真实任务返工次数的影响尚待观察，实际多 Session 试运行和正式部署分别另行推进。
