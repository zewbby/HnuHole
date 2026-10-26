# 快照配置、初始化和回退

> **2026-10-26 当前交付限制：** 默认配置、缺省配置及交付模板均为 PostgreSQL 新建、readPostgres=true、readRedis=false。阶段6三项修复及有限复核已通过；steady 回复展开 P95 +7.5716285574% 原 FAIL 保留，性能待可靠环境验证／Redis 启用前待验。下列初始化、双读、Redis 新建和停止 PG 读取仅为未来发布步骤；可靠环境性能项处理并取得显式启用授权前不执行。本机性能尝试与环境搭建已停止，合并、部署、启用均未授权。

适用本需求第 3 阶段服务端，尚未发布。使用前同时保留共享限流 PR #73 的 runtime、SQL 围栏及永久回执，不回滚到此前二进制。本文命令中的路径为占位，不代表生产环境。

1. 准备专用 Redis 7 primary、非零 maxmemory、noeviction，与 C/V 限流 Redis 分进程。参考 `infra/commentsnapshot/redis.example.conf`；128 MiB 仅是开发候选，最终容量和持久化恢复须阶段 5 实测。runtime 账号仅限 `hnuhole:comment-snapshot:v2:<environment>:*`；operator 单独增加 SCAN。禁止 runtime CONFIG/FLUSH，禁止访问限流或 V 的 key。
2. 将 `infra/commentsnapshot/snapshots.example.json` 作为完整 community runtime 的 `comments.snapshots` 对象。environment 与 namespace 对齐，runtime 用户固定 `community_comment_snapshot_v2`；替换示例 epoch 为此全新域的 UUID，所有 API 实例使用一致配置。runtime 密码、operator 密码和评论密钥分开保存在私有文件，POSIX 文件无 group/other 权限。不要输出内容或加入 Git。
3. 先构建同版本 `commentsnapshotctl`。仅在确实全新的空域，使用独立 operator 身份显式初始化一次：

```sh
commentsnapshotctl --config /private/community.json --initialize-new-namespace \
  --operator-username community_comment_snapshot_v2_operator \
  --operator-password-file /private/snapshot-operator-password
commentsnapshotctl --config /private/community.json --check
```

初始化不迁移 SQL、不删 key、不改变现有域；运行时不会自动初始化。operator 的连接身份不纳入 policy hash，runtime 仍用自己的凭据。namespace/epoch/policy/MAC 不匹配、控制元数据或未到期名录丢失时拒绝服务；不能通过反复初始化空账本掩盖问题。异常时保留证据，停止新建，按运维审批选择等待全部旧期限结束并用全新明确的配置域，或恢复一致数据；不要原地修改 epoch 后声称旧游标继续有效。

4. 滚动迁移顺序：所有实例先支持 V1/V2 双读，设置 `createBackend=postgres, readPostgres=true, readRedis=true`；全部兼容实例到位后统一改 `createBackend=redis`。记录最后 PG 新建时间，等待至少 30 分钟并确认没有旧实例写入，再改 `readPostgres=false`。旧表/schema/grants 保留用于明确回退，正常 Redis 路径无旧表读写/计数/清理。
5. 显式回退将新建改为 postgres 并保持两种来源可读；保留 Redis 实例直到其所有旧游标自然到期。不能以失败请求为触发自动回退 PG，不能在旧游标下重建名单，也不能直接切回不认识共享限流协议的旧版本。

默认候选：TTL 1800 秒；10000 ID；账号 1024 份；单份 196608 字节；模块保守预算 64 MiB（含 12 MiB 固定名录预留）；名录最多 8192 项/4 MiB；单 Redis 调用 100ms、累计存储操作 500ms、池 8；pending 30 秒、10 秒清理轮、DEL 每批 64。配置切换 read/create 开关不会改变现有 policy hash，额度/预算/epoch/MAC 改变会改变 hash，必须作为独立运维变更处理。

API 每 10 秒输出聚合指标。`created` 为成功 Prepare 新预留，`loaded` 为成功 Redis 载荷读取，`invalid` 为 Redis Load 的失效，`rejected` 为账号额度拒绝，`redis_errors` 为脚本调用失败次数，`duration_ns_total` 为累计脚本调用耗时；字节 gauge 是最近一次成功采样值。400 的签名错误可在进入 Store 前返回，因此该 invalid 并非全部 HTTP 400。生产完整监控、容量压测及 P95 判定仍待后续阶段。
