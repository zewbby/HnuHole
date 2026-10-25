# 共享限流实际架构与安全边界

> **2026-10-25合并回执：** [PR73](https://github.com/zewbby/HnuHole/pull/73) 已Squash合入main c051981；最终5ef371d与合并完整树一致，13workflow/23job全SUCCESS，指定Android四阶段限定PASS，见[机器回执](shared-rate-limit-merge-verification.json)。下方未提交/Draft/未合并属于原时点；未部署/生产发布，runbook步骤未在生产执行。

> **2026-10-24送审追加：** [Draft PR73](https://github.com/zewbby/HnuHole/pull/73)，原生产品33bdcc0之后仅CI和旧overlay host工具修复；6e50244远端13workflow/23job SUCCESS，见[CI记录](shared-rate-limit-remote-ci-verification.json)。本次回执编写时纯文档后续head CI尚未执行；CI记录时为Draft，后续检查/送审状态以live PR为准，未合并部署。

> **2026-10-24 Android追加：** 实际Keystore/加密SQLite+force-stop原键恢复、close和独立ACK、真实Redis CLIENT PAUSE故障恢复已在独立包四阶段限定PASS，见[原生证据](shared-rate-limit-device-verification.json)。不是整机重启或生产cmd拓扑，iOS/生产/全规模容量仍未验；原host结论保留。

SHARED-RATE-LIMIT-01，2026-10-24，分支feat/shared-rate-limit-abuse-control，基线8ed8f28。按冻结源码更新，[阶段2原文](shared-rate-limit-stage2-history.md)保留历史。[配置](shared-rate-limit-plan.md)、[runbook](shared-rate-limit-runbook.md)、[证据](shared-rate-limit-verification.json)分别维护参数/操作/验收。仅本地实现，最终r11隔离runner、无DSN host及全Go build/vet PASS（限定范围见机器记录），未合并部署。

## Redis与独立lane

单Redis7 primary/noeviction，C/V独立namespace/ACL/密钥；不支持Cluster/Sentinel自动切主。go-redis v9.7.3，池/超时有界、不盲重试写，NOSCRIPT可EVAL回退。Redis7 shebang no-cluster保留正常OOM拒写，不启用allow-oom。

Lua核namespace sentinel、类型/TTL、subject incarnation/directory；Redis TIME、整数毫秒、定点TB；SW边界(now-window,now]，加权bytes按累计释放量算等待，多窗取最大。内存先核全部动作/容量/指纹，最终业务state仅一个SET PX；directory先保守登记，失败可占容量但不半扣业务。不依赖Lua错误回滚。observe/enforce独立subject/directory lane；观察容量不影响enforce。off跳过计数但最终SQL policy围栏继续。

## SQL协调与最终业务事实

c_rate_limit.admissions为临时表，非永久总账。每账号16 PREPARED/256总项，全域4096/65536；短事务容量锁不跨Redis。kind为post/comment/dm-text/dm-image；原永久回执保留。

1. 正常Gate/账号锁先查原回执、冲突和业务条件；PREPARED固定generation/nonce/created_at/deadline，lease=min(120秒,dedupSeconds-5秒)，enforce要求正lease；重试不续租或重绑代次。帖评外部16字节键内部摘要32字节。
2. 第二个Gate事务重核，以固定proof联合Redis准入，确认ADMITTED同代/incarnation；deadline固定created_at+24h。Redis成功SQL确认失败保留PREPARED，同nonce重放，不免费放行或二扣。
3. 原最终事务再核Gate/资源/首次联系、namespace policy及同代ADMITTED；写原永久回执同时删协调项。SQL已完成重放先于计费；旧ADMITTED只终结旧键，不Probe重置健康新域。

准入前429不写永久FAILED/NOT_ACCEPTED/sealed，原键原内容等待后可重试；新429不证明旧在途未执行。GET/Worker在账号锁和正常Gate内处理过期/旧代项：有永久回执则返回，无则写原业务确定未受理锚并清协调项，迟到不能越过。原业务ACCEPTED交Worker不因准入租约结束取消。

DM旧FAILED attempt重试用同内容证明、不二扣；异内容冲突。身份对锁内判断实际新会话，send/new-create联合准入；另一方先建可保守不退，不重复建。图片纯格式/base64合法性检查先于逻辑扣费；已读物理字节不退。

## 四上传路径

帖子grant核摘要/到期/task/media/version/账号/Gate；评论/头像/DM核真实会话/资源。帖子/评论/头像raw body及DM JSON/base64按实际wire n计费，含重传/截断/非法图；Content-Length/byteLength/解码大小不能代替事实。

attempt+首块最多64KiB预留先通过；后续Reserve→ReadFull→Settle。n>0伴error/EOF仍结算，结算不随客户端取消；未知结算停传并保守留预留。剩余不足64KiB可批正数小块。真实HTTP SetReadDeadline限制读；晚actual按接收时刻计入，旧预留事件过期不能漏费。bytes只支持SW；读期限及未知预留有界。业务拒绝不退字节，逻辑send/create独立。

## policy、故障与恢复

持久namespace存generation/run_id/policy_hash/recovery_window_ms/state/barrier_until/dirty_until，新域operator显式初始化。run_id变化、哨兵丢失、应有状态缺失、异常TTL/类型/eviction进入RECOVERING，不把丢失当空桶。

- 读/ACK可有界local-read；仅post/comment/OTP已验证最终SQL可verified-db降级，不保证新增动作阈值。DM/上传/昂贵登录不凭库存或幂等表降级，Gate不放松。
- 降级最终事务原子写dirty_until；同run_id也须等。屏障期间禁止继续DB写降级，不解冻Gate。
- 恢复先FOR UPDATE，获锁后采样时间，与最终事务namespace锁排序。屏障覆盖old/new最长有效窗、SW读期限、固定最大在途deadline1秒、dirty_until；24h热dedup与计费恢复窗分离。
- policy_hash含规则/模式/费用、容量/dedup/read、主体密钥不可逆fingerprint。operator begin-recovery显式generation++；旧/off/observe实例最终SQL hash围栏拒写，无隐式热修改。

已测timeout/OOM/FLUSH/损坏状态/同run_id恢复；真实服务器重启、两个cmd进程重启、全规模容量与生产阈值观察未验。

## 客户端与close

帖评429保完整材料/身份/目标/图片任务和等待，到期用户手动同键重试；未知不换键补发。严格Retry-After1..86400/no-store，auth可details，帖评DM error内code/message。仅已验证组件SHARED_RATE_UNAVAILABLE分可恢复通道，通用Gate503整体fail closed。

DM加密持久队列默认256，批次100非上限；notBefore/cooldown跨重启保存，同会话前项挡后项，其他会话/接收落盘ACK独立。首次回复前一条文字无图，WAITING_FOR_REPLY不自动重发。未确认只转圈无待发送文本。

queued可确定取消；unknown隐藏后仍需close终态。POST /api/v1/dm/commands/{id}/close只传attempt，原账号锁与迟到text/image排序：SENT原样返回；不存在/失败写原commands永久FAILED/COMMAND_CLOSED，跨attempt阻迟到。SQL每账号120新锚/60秒，不扣send/create/upload，独立close cooldown不停ACK；不撤回已发，原两分钟撤回独立。Worker/Outbox保留，无RocketMQ。

## 指标、隐私、审查

runtime每30秒私有shared_rate_limit_metrics日志，固定action/mode及requests/allowed/denied/would_deny/redis_errors/fallbacks/duration_ns_total，无公开metrics入口或主体/正文label；草案完整error_class分类指标未实现，不外推。Redis仅用途隔离摘要/费用/证明，无token/密码/验证码/正文/全身份表。真实C/V独立cluster及runtime/owner权限审计见证据，生产外部隔离审计仍待。

阶段2/5由GPT-6 Astra xhigh独立只读审查，本chat记录；R1–R5与F1–F6源码闭环，最终无未修P1/P2，不是GitHub成员批准，也不表示审查者实跑测试。根协调执行工具；失败历史和未验边界保留。
