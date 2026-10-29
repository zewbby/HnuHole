# AI-CODING-01 — 双模式 AI Coding 工作流落地

- 模式：常规
- 负责人／状态维护人：当前开发 Session
- 分支／Worktree／PR：`codex/docs/ai-coding-workflow`；本地 Worktree；PR 未创建
- 授权依据与边界：用户授权在 SpeechFUL 本地分支写入方案，并要求先保留本地分支；本轮只修订协作规范与验证，不 Push、创建 PR、合并或部署。此处记录既有指令，不产生新授权。
- 基线：`origin/main` `31a05d9dfa13d4048157a4cf5658d357e5ae6426`
- 更新日期：2026-10-29
- 状态：实现已完成；本地验证 PASS；远端 CI NOT_RUN；未合并；未发布

## 目标与范围

按用户 2026-10-29 的 V1.0 方案，在 SpeechFUL 仓库建立常规模式与显式 `$orchestrator` 指挥模式。交付精简的 AGENTS.md、操作性 CONTRIBUTING.md、仓库内 Orchestrator Skill、简短任务契约、统一任务记录格式和[原生形状的可编辑 PPTX 流程图](../design/speechful-ai-coding-workflow-v1.pptx)。

本次是协作规范与图示变更，不修改产品行为、现有功能验收结论或 GitHub 仓库设置。实际开发任务试运行与 V1.1 修订属于后续工作。

## 接口与依赖

- 现有 `AGENTS.md`、`CONTRIBUTING.md` 和 PR 模板保持一致；既有认证、数据库、安全 Gate 与资源清理约束继续适用。
- 新任务状态以 `docs/tasks/<ID>.md` 为唯一权威入口；历史 `docs/design/HANDOFF.md`、`progress.md` 与 `docs/branches/` 保留原时点事实。
- 指挥 Skill 只在用户显式调用时启用，执行 Session 的分支和 Worktree 彼此隔离。

## 验收标准

- AGENTS.md 清楚定义默认常规模式、显式指挥模式、授权边界和工程底线。
- Skill 的五阶段流程、五项派单协议与交付门槛完整，且配置为仅显式调用。
- 派单前核对实际生效的规则与可读的任务契约版本，明确状态维护人；中断恢复先核对已有 Session、分支和未提交工作。
- 任务模板及 PR 入口指向唯一任务状态；现有安全与测试真实性要求未丢失。
- PPTX 流程图的节点与连线均为可编辑原生对象，内容与 V1.0 方案一致。
- 文档链接、Skill 校验、仓库协作检查、PPTX 渲染检查通过，未执行的产品测试如实标注。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 文档与 Skill | 原始 V1 `30d6659`；反馈修订 `61f185c` | PASS：本地链接检查、UTF-8 下的 Skill quick_validate 和差异空白检查 |
| 协作回归 | 反馈修订 `61f185c`，Windows Python 3.9.13 | PASS：19 项 `test_collaboration.py` 回归 |
| 规则版本接续 | 临时旧基线 Worktree `31a05d9`；规则与任务契约 `30d6659` | PASS：旧工作区可读指定任务文档；定向引入 `AGENTS.md`、`CONTRIBUTING.md` 后，两份工作树文件的 Git blob 与规则提交一致；临时 Worktree 已清理 |
| PPTX | 已提交版本 `30d6659` 的 `speechful-ai-coding-workflow-v1.pptx`；SHA-256 `d482fe930078cc5f0d566815eed4f006e0c2b478ec7c77df1548a5ea343b9893` | PASS：2 页已导入并渲染；原生形状与连接线，无图片替代；包与布局检查通过 |
| 产品构建／真机 | 无产品代码变更 | NOT_RUN：不适用本次任务 |
| 实际多 Session 试运行 | 尚未显式调用 `$orchestrator` 执行开发任务 | NOT_RUN：属于后续试运行，不以 Worktree 机制检查代替 |
| 远端 CI | PR 未创建 | NOT_RUN |

## 阻碍与下一步

本地协作规范修订完成。实际多 Session 试运行留待具体跨模块任务显式调用 `$orchestrator` 时进行。Push 与创建 PR 依用户授权和仓库规则推进；合并与正式部署需要明确授权。
