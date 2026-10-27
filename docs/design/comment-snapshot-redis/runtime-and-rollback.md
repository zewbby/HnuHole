# 快照配置、初始化和回退

> **2026-10-27 PR84已合并，main默认Redis：** [PR #84](https://github.com/zewbby/HnuHole/pull/84)合并 `ad0c47ce98cc13093be9b00b48e5d8ea37443cdb`。默认Redis新建及PG/Redis双读，标准C模板接通；启用评论却缺快照配置时启动明确失败，显式PG回退保留。配置5项、build/vet、独立只读审查和12个适用自动workflow通过。现有开发Redis接线只读核对一致，运行环境未改；性能/真机/30分钟未追加验收，生产未发布。见[实现与验证](main-default-20261027.md)；下方默认PG/待合并状态保留原历史时点。

> **2026-10-27 PR80已合并 main：** 合并 `4e7b0fb7d05daa579eb37138d374bb495d4fea30` 与已测 head `a2e98eb` 完整tree一致，既有适用CI通过。一次指定性能场景PASS，历史FAIL及其他未验项保留；同机开发Redis已授权启用并保留PG旧游标读取，仓库默认仍PG，生产未发布。本次仅合并与文档收尾，无新产品测试、性能采样或部署。见[最终合并交接](merge-receipt-20261027.md)。下方待提交／未合并／未启用状态均保留原历史时点。

> **2026-10-26 当前交付限制：** 默认配置、缺省配置及交付模板均为 PostgreSQL 新建、readPostgres=true、readRedis=false。阶段6三项修复及有限复核已通过；steady 回复展开 P95 +7.5716285574% 原 FAIL 保留，性能待可靠环境验证／Redis 启用前待验。下列初始化、双读、Redis 新建和停止 PG 读取仅为未来发布步骤；可靠环境性能项处理并取得显式启用授权前不执行。本机性能尝试与环境搭建已停止，合并、部署、启用均未授权。

适用本需求第 3 阶段服务端，尚未发布。使用前同时保留共享限流 PR #73 的 runtime、SQL 围栏及永久回执，不回滚到此前二进制。本文命令中的路径为占位，不代表生产环境。

1. 准备专用 Redis 7 primary、非零 maxmemory、noeviction，与 C/V 限流 Redis 分进程。参考 `infra/commentsnapshot/redis.example.conf`；128 MiB 仅是开发候选，最终容量和持久化恢复须阶段 5 实测。runtime 账号仅限 `hnuhole:comment-snapshot:v2:<environment>:*`；operator 单独增加 SCAN。禁止 runtime CONFIG/FLUSH，禁止访问限流或 V 的 key。

   Publish 的单字节优化需要在原 runtime ACL 内增加具体命令 `+setrange +pexpiretime`，同时保留 `+set`。脚本先完整校验账本和待发布记录，仅在 header/control 水位与实际绝对到期时间相等时更新状态；水位/期限不等或缺少新增权限仍执行原 `SET PXAT`。撤销 SET 权限不能由 SETRANGE 绕过。该优化不改变 v2 布局、policy hash、epoch、SQL 后发布顺序或期限，不需要重新初始化现有 v2 域；旧 JSON 域仍不兼容。此处仅说明未来部署权限，本次未修改运行环境 ACL。
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
