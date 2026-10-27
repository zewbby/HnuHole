# COMMENT-SNAPSHOT-REDIS-01 合并与最终交接

2026-10-27，[PR #80](https://github.com/zewbby/HnuHole/pull/80) 已按用户明确授权 Squash 合入 main，合并提交为 `4e7b0fb7d05daa579eb37138d374bb495d4fea30`。已测 PR head 为 `a2e98eb6a1b749adf6a4e003ab1aa11c378e8947`，两者完整 Git tree 均为 `efe3c30773eb6504cb8279fbeab6b69dabe9d382`，合并没有产生产品差异。合并前 PR 为 ready、mergeable clean，main 未启用保护，现有检查均完成；使用带预期 head 的普通 Squash API，没有绕过保护。既有独立 agent 复核不等于 GitHub 成员批准，本文不声称取得成员批准。

## 已有验证及证明范围

- 最终 PR head 的15个不同 workflow、26项逻辑 job 成功；PR 元数据事件另4次 policy 成功，共30条 SUCCESS。1条预期 SKIP 是仅 workflow_dispatch 的 actual-process-acceptance。该 SKIP 不计为性能或30分钟整轮通过。精确检查链接见 [PR Checks](https://github.com/zewbby/HnuHole/pull/80/checks)。
- 唯一实际性能对照为 steady reply-expanded 新建快照，每侧300个配对样本、0请求错误。PG P95 495.2789ms、Redis P95 480.2467ms，相对 **-3.035098% PASS**，满足原≤5%阈值；时钟、Windows QPC及资源证据通过，360次 SETRANGE（含预热）证明 Publish 快路径实际命中。
- 原 **+7.5716285574% FAIL** 保留为旧版本/环境记录。新结果只证明上述场景，不能将不同版本/环境的绝对耗时变化全部归因于 Publish，不宣称阶段5全部 PASS。性能数据产生于迁移前；迁移后未重复性能采样。P5-D1及旧设备/30分钟/iOS等缺口按原版本和范围保留。
- 本次合并收尾只核对现有证据、Git tree、差异和文档，不重新运行产品测试、构建、设备验收或性能采样。正常合并及文档 PR 自动触发的协作 policy 检查单独记录，不冒充产品验收。

## 当前开发环境

用户已明确授权并完成同机开发后端的 Redis 启用：`createBackend=redis`、`readPostgres=true`、`readRedis=true`、TTL1800秒，保留 PG 旧游标读取。快照使用专用 Redis7、128MiB/noeviction/AOF everysec，与 C/V 限流分进程，runtime ACL 限定 dev 命名空间和具体命令，operator 分离。仓库缺省值和模板仍为 PG/readRedis=false；**生产未发布**，本轮没有额外部署或重新构建客户端。

启用后的既有3个真实 HTTP 请求验证测试账号登录、Redis 快照 ACTIVE/载荷、nonce 重放同一快照和固定绝对到期；该帖子无续页，因此不声称此冒烟覆盖续页或整机。C/V 健康、AOF状态、幂等启动 hook 均通过。实际运行二进制来自已测 head `a2e98eb`，与合并产品源码一致；合并不改变运行实例。

因宿主 E 盘写满曾发生 WSL emergency_ro，启用中断后已按用户授权将发行版迁到 `D:/HnuHole-WSL/Ubuntu-24.04`，先恢复原后端，再完成 Redis 切换。迁移前后数据库行摘要、序列、C28/V7及 Gate C10/V8一致，没有数据库 reset/recover/down/restore。原约133GB虚拟盘已由系统迁移命令移除。旧 E 目录只剩5430字节图标，自动审批拦截删除后，用户选择按已核对路径自行清理；它不影响服务或本次合并。

## 接续入口

- 运行配置及回退流程：[runtime-and-rollback.md](runtime-and-rollback.md)。当前开发环境继续保留双读；未来切回 PG 新建时仍须保留 Redis 旧游标至自然到期。
- 实现及原始失败记录：[publish-state-optimization-20261027.md](publish-state-optimization-20261027.md)。本文件的后续合并/启用状态覆盖其较早“待提交/未启用”时点。
- 脱敏机器记录：[merge-verification-20261027.json](merge-verification-20261027.json)。其他149条模块台账保持不变。
- 私有交付、采样、恢复和启用证据：[D盘交付记录](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/post-pr-publish-state-delivery-sol-20261027/delivery-report.md)。主线同步和本文档 PR 的最终 SHA/检查见[D盘合并回执](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/merge-closeout-sol-20261027/merge-report.md)，避免为记录自身合并递归创建文档 PR。

后续操作仍按具体新请求授权：本需求代码已合并，当前同机开发 Redis 已启用；生产发布、缺口验收和额外部署不能从本次收尾推导。
