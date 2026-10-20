# 防止点赞收藏未知请求覆盖后续意图

工作项 FEED-INTERACTION-ORDER-01，2026-10-20，Asia/Shanghai。独立分支 `codex/fix/feed-interaction-order`；最新 main 基线 `444d25862a83d3a8d40168ef660e50da0712b71e`。状态 SCOPED_LOCAL_PASS，尚未合并、未部署。

新版列表联调确认的缺陷：无条件幂等 bool PUT 在未知网络结果后，GET／同值重试不能封死更早的未提交请求。原请求晚于反向操作提交时会覆盖最后用户意图。实际 PostgreSQL Snapshot 屏障保留旧语义复现，并以同样时序验证条件写失败412。

新增兼容的 `Interaction-Version`／`If-Interaction-Version` 头、0021私有账号／帖子写版本及最小授权。每次成功写入旋转，包括旧客户端和同值写；不依赖客户端时钟、临时内存、聚合计数或表示hash，避免ABA。严格 JSON DTO、旧接口、C/V边界与最终 Gate 不变。完整接线与未知恢复规则见[契约](../design/feed-backend-contract.md#feed-interaction-order-01未知结果与迟到请求)。

回归包括真实旧请求延迟复现、条件旧请求最后释放、跨账号标签、他人聚合往返、8并发同版本唯一成功、后续失败整笔回滚、同值旧写推进版本、精确HTTP与CORS、实际TLS和空库／0018／0019／0020升级、启动权限与正式注销清理。使用本次一次性SQL库，不连接共享联调库。56顶层／115含子项零失败零跳过，Go全包/build/vet、11份API与旧文字契约通过，见[机器证据](../design/feed-interaction-order-verification-20261020.json)。最终head远端CI待PR核对；无DSN宿主测试不代证SQL。

环境任务由同一负责人独立维护；共享环境仍为已合并444d258／C0020/V0004。此修复只提交PR，不自行合并或部署。前端／Android新条件写接线待合并后的联调；正式发布另需授权。需独立同事review，不以作者自审冒充批准。
