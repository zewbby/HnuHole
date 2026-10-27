# 评论快照独立进程验收

只在 Linux 上创建本脚本归属的一次性 PostgreSQL、Redis 和实际 `services/api/cmd/api` 子进程。没有外部 DSN 参数，不使用现成数据库，不修改手机、不部署产品。运行目录必须在源码目录外，权限为 `0700`。

前置工具：仓库支持的 Go、PostgreSQL 16 的 `initdb/pg_ctl/psql`、Goose v3.22.1、Redis 7、Python 3 标准库。工具由调用环境提前提供；脚本不安装工具。Go 按锁文件编译，已有本任务缓存可复用；CI 缺失的 Go 模块通过配置的 GOPROXY 下载。

```sh
mkdir -m 700 /private/comment-snapshot-acceptance
python3 tools/comment-snapshot-process/campaign.py \
  --root /private/comment-snapshot-acceptance \
  --source /absolute/HnuHole \
  --redis /absolute/redis-server
```

`campaign.py` 先冻结一组二进制与生产源码摘要，顺序完成兼容双读、PG-only 与 Redis-only 两个完整性能批次，再进行功能/容量/故障，最后并行进行两套稀疏的实际30分钟阅读。前台性能压力不与其他压力或构建重叠。`run.py` 中旧的 full 流程保留历史复现，不作为本轮最终验收入口。

默认完整批次包含：

- 两个独立 API 命令进程共享快照、nonce 和账号额度，重启后继续读取；同进程两个 handler 不能替代此项。
- 10 页各 50 个主评论，500 个楼层均打开回复；额度填满后双进程并发拒绝；记录 INFO memory、MEMORY USAGE、名录及载荷内存。
- 独立故障 Redis 上的真实 API 权限、签名、载荷损坏、OOM、数据/名录丢失、断连、实际 Redis 重启；检查不自动初始化或退回 PostgreSQL。
- 两个真实 API、真实 PostgreSQL 限流元数据、两个独立 Redis，在快照 OOM 时保留跨进程限流拒绝与原代次。
- 评论增长至 10002 条后，原已提交 nonce 仍复用原名单和游标，新 nonce 保持单份超限拒绝；实时总评论数仍可变化。
- 性能批次均有11563条评论、10002条主评论负例和相同的1024项初始Redis占用；steady模式为PG镜像相同逻辑占用。占用由已提交SQL名单构造，仅作fixture，不代替501次实际读取验收。保持正式共享限流observe配置、原本地query240和worker2秒，不提高限额；以计时开始前的0.27秒最小间隔调度请求。
- 每来源预热30次，首次200、续页1000、预览/展开各300样本，并发1，固定seed按20对打乱AB/BA次序。兼容模式续页同进程；两个模式均中途交换进程绑定并重新预热。记录每次实际发送相对时间、进程代次和全部耗时/错误。每个模式均须四路径P95回退≤5%，失败后仍完成其余路径，不拼接通过项。
- 耗时从严格TLS连接建立后发送HTTP请求开始，到读完完整响应体结束；调度等待、TCP连接和TLS握手不计入该数值。两个来源始终使用同一范围，不将其表述为包含建连的总用户等待时间。
- 真正经过 30 分钟的 Redis 阅读、固定到期和显式刷新；保存初始签名期限、UTC/monotonic/Redis TIME/PTTL，漂移超过2秒判环境不稳定并保留失败。
- 第二套独立归属的兼容 fixture：停止最后一个 PG 写入进程后保持 V1/V2 兼容读取实际 30 分钟，再停用旧表访问并验证显式 PG 回退。

数据由私有 fixture 以 SQL 预置；仅预置事务临时关闭触发器，随后恢复原触发器和最小运行时权限。它不冒充评论发布接口、手机端到端或原生安全存储验收。所有测量请求走生产 HTTPS、Safety Gate、会话校验和 SQL 最终提交。

`campaign-summary.json`、`bin/binary-manifest.json`、各性能cohort的`normalized-performance.json`及functional下的`summary.json`、`capacity-performance.json`、`api-faults.json`、`api-admission-isolation.json`、`nonce-growth.json`、`api-rollback.json`、`long-read-result.json`、`api-drain.json`和`compatibility-summary.json`是无凭据结果。`*.private.*`、`material/`和PostgreSQL数据目录必须留在私有运行目录，不能上传或提交。退出只停止本脚本记录的进程及自己的私有PG数据目录；故障日志和私有材料不自动删除。

`normalized.py --diagnostic`启用额外事务/Redis客户端计时，每路径100对，只用于定位。客户端时间包含排队/传输，SQL/Gate/projection剩余时间不是纯SQL；Redis INFO的Lua执行累计值不等于逐请求排队时间。正式批次关闭观测日志。`native-probe.ps1`是指定真机和独立.commentsnapshot包的本地选择性入口，要求本任务持有lease；配合`integration_test/comment_snapshot_live_device_test.dart`验证Android真实TLS读取和九项fixture界面场景，不声称原生vault或整条生产UI端到端通过。

CI 的普通快照作业包含真实 Redis/SQL 及客户端回归；约 30 分钟的独立进程批次通过同一 workflow 的 `workflow_dispatch` 专门运行，不能把 workflow 文件存在当作远端执行通过。
