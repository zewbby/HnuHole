# 共享限流实现决策

任务 SHARED-RATE-LIMIT-01，基线 8ed8f28，分支 feat/shared-rate-limit-abuse-control。2026-10-24 阶段2由 GPT-6 Astra / xhigh 只读审查形成；本页记录实现约束，不代表功能或验收已经完成。完整需求与接口地图见 [阶段1计划](shared-rate-limit-plan.md)。

## 本期技术边界

- 单 Redis primary、专用实例或空间、noeviction；不宣称支持 Cluster、Sentinel 或自动切主。C/V 独立命名空间、密钥、数据库元数据，不新增跨域身份关联。
- 使用 github.com/redis/go-redis/v9 v9.7.3（该版本 go.mod 最低Go1.18，兼容本仓库Go1.22），有限连接池和请求期限，MaxRetries=-1、ContextTimeoutEnabled=true。写入超时不能盲目重放；NOSCRIPT再EVAL是安全的缺脚本回退。
- off跳过新增规则；observe只记录would-deny/error，不新增429或503，旧防刷继续生效；enforce执行真实拒绝与故障策略。
- Retry-After统一严格整数1–86400秒，配置最长窗口不超过24小时，返回真实最晚可准入时间。auth错误体保留details；post/comment/DM继续严格code/message，不缓存，不带成功续期头。
- 帖子/评论命令键是22字符canonical base64url、解码16字节，保留原规范；阶段1文档中32字节描述须在最终文档修正。

## Redis原子计数

新增internal/ratelimit，接收可信主体摘要、动作/费用、原操作摘要和内容指纹，不接触HTTP原文、会话令牌、正文或身份列表。

每个主体一份有界序列化字符串，存各动作窗口、令牌桶、热去重、字节预留及generation/incarnation。Lua在内存中校验和清理，先查同键同内容重放/异内容冲突，再检查全部动作/窗口/容量，最后只用一次SET ... PX提交新状态。不得依赖多次写命令异常时回滚，不设置allow-oom。Redis TIME、整数毫秒、窗口(now-window,now]；令牌桶定点数且回拨不补令牌。拒绝等待取全部命中窗口最大值，加权字节窗按累计释放足够容量的事件计算。

主体目录先保守预留容量，成功后才计费；目录失败最多占容量，不能部分扣动作。目录TTL不早于主体状态，应存在而缺失视为丢失。主体数、事件数、去重数、序列化字节及Redis内存均有硬上限，满容量503，不驱逐有效状态。热去重可限24小时，永久幂等由SQL协调及原回执保障。

建议接口：Admit(ctx,subject,charges,proof)、Probe、Confirm；proof含Operation/Fingerprint用途隔离摘要、Nonce、Generation、Incarnation、Deadline。入口无幂等计数另有接口，传输另有BeginTransfer/ReserveChunk/SettleChunk。

## 持久准入协调

增加C域临时表c_rate_limit.admissions，不新增永久总账。唯一(account_id,business_kind,key_digest)，存动作集合、指纹、nonce、generation/incarnation、状态、创建/准备期限/确认时间，无正文。

- PREPARED最长2分钟，ADMITTED且无最终业务回执最长24小时。
- 每账号最多16 PREPARED、256全部未终结标记；全域4096/65536。插入短事务用固定advisory锁核容量，不跨Redis持全域锁。
- 在原业务函数最外层依次执行事务，禁止已持账号锁的withPostSession里嵌套新事务。

流程：

1. 正常Gate事务授权、账号锁，先查原业务回执/内容冲突，无最终结果才创建PREPARED。
2. 第二个正常Gate事务重新授权、查回执和业务前置条件，执行Redis联合准入，成功确认ADMITTED并提交，不在此执行业务。
3. 原最终业务Gate事务再查回执、核对ADMITTED及完整业务条件，写原永久回执时同时删除协调标记。

Redis成功但SQL确认失败保留PREPARED，以相同nonce、指纹及incarnation核对/重放；PREPARED不能当免费通行证。明确DENY=429删除PREPARED，不写FAILED、sealed或NOT_ACCEPTED，原键以后仍可重试。

未知或丢失不能证实，或期限结束时，GET/清理Worker在正常Gate和账号锁下查最终回执：有则清标记返回原结果；无则写入原业务确定未受理终态后清标记（帖/评NOT_ACCEPTED，DM FAILED+ADMISSION_EXPIRED）。该旧键永久关闭，不自动换键，需用户明确发起新命令再准入。迟到执行再次查最终回执/标记，不能关闭后执行。已经有ACCEPTED并交Worker的任务不得因协调租约终止。所有协调状态必须有可查询恢复或确定结束路径，不留永久未知任务。

## 业务接入位置

- ExecutePostCommand：CREATE/实际RETRY发布计post.create；ExecuteCommentCommand：CREATE/RETRY计comment.publish。保留SQL120回执/60秒及帖子live128；429不走业务拒绝落永久回执分支。
- SendDMText：真实身份对锁内查会话是否存在，联合dm.send与实际新dm.conversation.create，双方同时发起共用同身份对锁。不能靠客户端conversationId为空判新会话；最终事务再查唯一性。准入后另一方创建可保守不退款。
- SendDMImage：先原回执/冲突、业务前置，再逻辑send准入；物理传输单独计费。
- GetDMCommand/PullDM/AcknowledgeDM、pending/controls/operations：read/control保护，不扣发送。
- communitySessionPublic：严格解析合法标识后、昂贵密码运算前，IP与标识×来源保护；不存在账号保留dummy密码路径，失败链只影响该来源组合，成功不清尝试窗。
- V OTP入口：共享IP保护，原SQL邮箱额度/冷却/错码规则不变，邮箱仅V域。

## 上传真实字节

读body前验证可信主体：post grant解析必须核实摘要、到期、任务/媒体/version、账号状态和Gate（新增ResolvePostUploadSubject）；评论/头像/DM验证真实会话和适用资源归属。最终业务仍再授权，不把grant/token存Redis。

最大64KiB分块：attempt+首块预留联合通过才读；每块先预留容量、ReadFull、原子结算实际n并释放未读部分，n>0伴EOF/error同样结算；下块无预留即停。每次重传新transferID，全部实际wire body计费，包括DM JSON/base64。不以Content-Length/声明byteLength/解码大小替代事实。预留不是实际消费，未知结算停止并503，保守预留至允许读取期限+最长窗，指标区分实际与未知预留；并发传输数、预留数、读期限有界。

物理attempt/bytes先处理；内容验证后才对逻辑send/实际新create联合准入。后续业务拒绝不退已消耗字节，未知内容前不先扣发送额度。

## 故障及恢复

每域数据库一行持久namespace元数据：generation、run ID、状态、恢复屏障。新环境明确初始化，不由首个API把缺哨兵当空状态。连接核run ID，脚本核哨兵/generation，主体核incarnation、TTL和目录。重启/哨兵丢失/应有主体缺失/异常TTL类型进入持久RECOVERING。

timeout、断连、OOM、脚本、状态丢失分开计指标；非超限不返回429。普通读/ACK/查询有界本机降级；仅已验证SQL最终限额覆盖的帖子/评论/OTP路径可按声明受控降级；DM/上传/昂贵登录不能据库存上限放行。恢复用新generation隔离及最长有效窗守候；屏障期间暂停高成本写入的DB降级，否则新消耗使守候无效。屏障结束自动恢复共享，不解冻业务Gate。

可信代理显式CIDR，非可信直连忽略转发头；可信链从右到左剥离可信代理，限制头长度和跳数，IPv4单地址/IPv6网络规则保持。

## 验收实现要求

新增authlab/run-shared-rate-limit-isolated.sh，仅创建本任务Redis/一次性PG。两个API实例、20新操作限5、重启切身份不增；同键并发/异内容/已完成回执；DM联合准入不半扣；所有协调崩溃点、429不被租约封闭；RedisOOM/断连/超时/FLUSHDB/单状态丢失/重启恢复；上传截断/取消/非法/重传/并发预留；共享IP/伪造代理/模式/容量/TTL/隐私/ACK独立。相关Go、真实Redis/SQL/TLS、Flutter与契约检查进入CI。只以实际执行结果更新PASS。
