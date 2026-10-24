# 共享限流：实际配置与接口地图

> **2026-10-24送审追加：** CI记录时[Draft PR73](https://github.com/zewbby/HnuHole/pull/73)已提交推送，指定Android PASS、6e50244远端13workflow/23job SUCCESS，见[CI记录](shared-rate-limit-remote-ci-verification.json)。runtime沿原生已测33bdcc0；CI记录时为Draft，本次回执编写时后续纯文档head CI待查PR；后续检查/送审状态以live PR为准，未合并部署。下方未提交/CI NOT_RUN保留原时点。

> **2026-10-24 Android追加：** 此前下文未真机是原host交付时点。现final-r11独立Android包四阶段实际TLS/双PG/Redis限定PASS，见[原生证据](shared-rate-limit-device-verification.json)；原940/3SKIP保持。最新native源码manifest110文件，旧107文件为历史；用户授权提PR/远端CI，当前PR未建、CI NOT_RUN，未合并部署。

任务 `SHARED-RATE-LIMIT-01`，2026-10-24；分支 `feat/shared-rate-limit-abuse-control`，基线 `origin/main@8ed8f28`。新增能力仅在本地，未提交/推送/PR/合并/部署。[阶段1历史原文](shared-rate-limit-stage1-history.md)中的候选TTL、旧键长度和待实现描述不作为当前事实。机制见[架构](shared-rate-limit-architecture.md)，操作见[runbook](shared-rate-limit-runbook.md)，结果和失败历史见[机器记录](shared-rate-limit-verification.json)。

## 配置来源与模式

实际装配样例为 [C runtime](../../infra/ratelimit/community-observe.example.json)、[V runtime](../../infra/ratelimit/verifier-observe.example.json) 及各自operator JSON；[TrialConfig](../../services/api/internal/ratelimit/defaults.go)、[Config.Validate/ValidateFor](../../services/api/internal/ratelimit/redis.go)为最终源码依据。样例新增规则全部observe，是试运行假设，无生产流量观测，不代表已部署配置。原SQL/入口/Gate继续。

- off跳过新增计数；observe仅记录would-deny/错误，普通Redis故障不新增429/503；enforce执行准入及故障策略。观察和执行使用独立subject state/directory lane，观察容量不能影响enforce。
- 配置启动时冻结，无文件热修改。计费策略/主体密钥变化须operator显式重新配置generation；旧off/observe实例也受最终SQL policy hash围栏。
- C/V各自namespace、主体HMAC密钥、Redis ACL/密码、DB角色和元数据，不共享全量日志。C不接收V邮箱。只支持Redis7单primary/noeviction，不支持Cluster/Sentinel自动切主。
- trustedProxies默认空；非可信直连忽略转发头，可信链从右向左剥离可信代理并限制长度/跳数。IPv4单地址、IPv6 /64。账号来自已验证会话，身份共用账号额度。

## 完整试运行阈值

SW为精确滑窗 `(now-window,now]`，TB为定点令牌桶。以下新增规则在样例中均observe。

| 服务 / action | 主体 / 单位 | 阈值 | enforce时组件故障 |
| --- | --- | --- | --- |
| C/V entry.query | 来源网络 / 请求，含ACK/read/close入口 | TB10000，166/s | local-read |
| C/V entry.mutation | 来源网络 / 请求 | TB6000，100/s | reject；仅已验证SQL路径受控降级 |
| C login.ip | 来源网络 / 尝试 | SW300/60s | reject |
| C login.source | 合法标识摘要×来源 / 尝试 | SW10/60s | reject |
| C login.failure | 标识×来源 / 失败 | SW5/300s；成功不清尝试窗 | reject |
| V otp.request / otp.verify | 来源网络 / 请求、校验 | SW120/60s、300/60s | verified-db |
| C post.create | 账号 / CREATE或实际RETRY发表 | SW5/60s+30/3600s | verified-db |
| C comment.publish | 账号 / CREATE或RETRY评论 | SW12/60s+120/3600s | verified-db |
| C dm.send | 账号 / 文字或单图，多图逐张 | TB30，2/s | reject |
| C dm.conversation.create | 账号 / 实际新身份对 | SW10/600s+40/3600s | reject |
| C upload.attempt | 账号 / 四类body，每次重传另计 | SW60/600s | reject |
| C upload.bytes | 账号 / 实际wire body字节 | SW125829120/600s+536870912/3600s | reject；只允许SW |
| C read.account | 已验证账号 / 普通读取 | TB180，6/s | local-read |
| C read.control | 已验证账号 / ACK/read/命令核对 | TB300，10/s，独立发送 | local-read |

entry.query本机降级TB为10000/166s⁻¹，其他local-read为100/5s⁻¹；map最多4096项，空闲一分钟可回收，满容量拒绝新项，不随机驱逐有效状态。不保证故障期跨实例精确。

## TTL、容量与恢复窗

不沿用旧草案每动作65s/605s/60s TTL或全局去重131072。每主体每lane一份有界JSON含多个动作；directory分lane。以 [redis.go](../../services/api/internal/ratelimit/redis.go) / [atomic.lua](../../services/api/internal/ratelimit/atomic.lua)为准。

| 参数 | 样例 | 边界 / 语义 |
| --- | --- | --- |
| deadlineMilliseconds / poolSize | 100 / 8 | 10..1000ms / 1..64；go-redis v9.7.3、MaxRetries=-1、ContextTimeoutEnabled |
| maxSubjects | 32768 | 1..65536，每lane有效directory主体 |
| maxEvents | 16384 | 1..16384，每subject全部SW事件总数；各窗口分别保留事件 |
| maxDedup | 256 | 1..4096，每subject热去重 |
| maxReserves | 32 | 1..64，每subject预留项 |
| maxStateBytes | 1048576 | 1024..1048576，单subject JSON |
| dedupSeconds / readSeconds | 86400 / 30 | 1..86400 / 1..60；持久准入enforce额外要求正prepare lease |
| SW / TB / rules | 见上表 | 每规则最多4窗；SW最长86400-readSeconds-1秒；TB补满≤86399秒；闭合action集1..32规则 |

`RecoveryWindow=max(非off SW窗+ReadSeconds,非off TB补满时间,1ms)+固定1秒`。1秒覆盖旧实例最大在途Redis deadline。state TTL=`max(dedupSeconds,RecoveryWindow)`，成功提交刷新；directory member到期对应state，directory key TTL再加1秒。SW事件按窗口过期，dedup独立过期/Confirm清除；未知bytes预留覆盖允许读取期限+最长bytes窗。默认24h热state不要求停24h；样例C恢复基准3631秒、V91秒，old/new和dirty/barrier可要求更晚。

[Redis样例](../../infra/ratelimit/redis-community.example.conf)为256MiB/noeviction。目录/事件/预留/JSON/Redis内存任一到界即组件不可用，不逐出有效计费状态。最大主体数×最大state不是256MiB容量保证；全规模压力/MEMORY USAGE及生产阈值观察未验。

## 源码与接口

- 核心：`services/api/internal/ratelimit/`；C迁移27、V迁移7；`cmd/ratelimitctl`；业务协调/清理为`authprivacy/community_rate_{admission,cleanup,subject}.go`。
- HTTP：`authprivacyhttp/shared_limits.go`、`source.go`及四上传endpoint；可信会话/grant主体、真实body字节/read deadline，最终业务再授权。
- 帖/评：原SQL各120新回执/60秒和帖子128存活任务继续；429完整草稿、手动同键重试，不自动发表。
- DM：首次回复前仅一条文字无图；send/实际new-create联合准入；本地256持久队列，同会话保序、独立接收ACK；未确认只转圈，无“待发送”文字。
- `POST /api/v1/dm/commands/{id}/close`只传attempt，在原账号锁和commands表写永久FAILED/COMMAND_CLOSED跨attempt锚；SENT原样返回。SQL120新锚/60秒，不扣send/create/upload，close独立cooldown不停ACK；不撤回已发消息。
- 登录在合法标识解析后、昂贵运算前准入，dummy路径保留；V原邮箱SQL额度/冷却/错码/一次性继续。沿用Worker/Outbox，无RocketMQ。

帖/评外部键22字符canonical base64url→16字节，内部key_digest是32字节摘要；DM仍UUID。429为RATE_LIMITED、严格Retry-After 1..86400/no-store；auth允许details，帖/评/DM error内严格code/message。已验证共享组件503为SHARED_RATE_UNAVAILABLE，通用Gate503继续fail closed。

## 验证边界

最终r11隔离runner 39顶层PASS/0FAIL/0SKIP（21 ratelimit、6 HTTP、10 SQL、2 CLI，含unit与真实fixture），常规无DSN host两pkg及全Go build/vet PASS；host中的数据库条件SKIP不算SQL证据。r10为上一fixture版本历史。客户端最新940 PASS/0FAIL/3既有HTTP-SQL fixture SKIP、analyze0、bundle PASS。A1–A6按子项和缺口记录，不笼统全部PASS。两个真实TLS handler实例同Go测试进程，不能称两个cmd进程。真机/iOS/生产/remoteCI NOT_RUN，历史模块总裁决不变。
