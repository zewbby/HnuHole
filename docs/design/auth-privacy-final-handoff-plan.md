# AC06 最终交付与状态统一任务单

日期：2026-10-05。只在 `codex/auth-privacy-handoff`，基线 `cbc99b010ba23bba42f76e2523269e3952b14392`，保留 AC04／AC05 全部未提交改动。依据[匿名清单](auth-privacy-closure-checklist.md)、[HANDOFF](HANDOFF.md)与[模块交接](module-acceptance-handoff.md)。

1. 核对 AC01–AC05 记录、被测源码与证明范围，固定当前实现摘要；确认历史规格／验收记录没有被换绑为当前通过，列出尚未实现的消费者和缺设备／配置的验收。
2. 整理[最终交接报告](auth-privacy-final-handoff-report.md)，同步 HANDOFF／progress、模块台账与机器入口，修正总入口和过时下一步，补架构／独立评审入口的当前状态。分开登记本地交接完成、完整验收未闭合和远端发布待执行。
3. 执行现有交接检查、最终证据／文档摘要检查及补丁检查，保存[机器记录](../../services/api/authlab/final-handoff-verification.json)，核对临时目录已经清理。只保留源码、测试与小型记录；本任务不重建大型缓存或重跑 Go／SQL／Flutter／平台测试，不修改应用、迁移、凭据或生产配置。

AC06 的 PASS 只表示当前本地交接材料一致且可审阅，不代表 AC05、B02整模块、匿名验收或生产通过。提交／推送／部署仍按当次用户授权执行；本轮准备本地交付，既有 AC01–AC03 发布记录保留原范围。
