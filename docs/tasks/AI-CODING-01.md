# AI-CODING-01 — 双模式 AI Coding 工作流落地

- 模式：常规
- 负责人：当前开发 Session
- 分支／PR：`codex/docs/ai-coding-workflow`；PR 未创建
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
- 任务模板及 PR 入口指向唯一任务状态；现有安全与测试真实性要求未丢失。
- PPTX 流程图的节点与连线均为可编辑原生对象，内容与 V1.0 方案一致。
- 文档链接、Skill 校验、仓库协作检查、PPTX 渲染检查通过，未执行的产品测试如实标注。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 文档与 Skill | 本地任务分支 | PASS：本地链接检查、Skill quick_validate 和差异空白检查 |
| 协作回归 | 本地任务分支，Windows Python 3.12 | PASS：19 项 `test_collaboration.py` 回归 |
| PPTX | `speechful-ai-coding-workflow-v1.pptx`；SHA-256 `d482fe930078cc5f0d566815eed4f006e0c2b478ec7c77df1548a5ea343b9893` | PASS：2 页已导入并渲染；原生形状与连接线，无图片替代；包与布局检查通过 |
| 产品构建／真机 | 无产品代码变更 | NOT_RUN：不适用本次任务 |
| 远端 CI | PR 未创建 | NOT_RUN |

## 阻碍与下一步

本地交付完成。Push 与创建 PR 依用户授权和仓库规则推进；合并与正式部署需要明确授权。
