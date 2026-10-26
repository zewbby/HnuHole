# P5-D1 计时协议裁定

2026-10-26，GPT-6 Astra / xhigh，COMMENT-SNAPSHOT-REDIS-01。**裁定：当前环境仍阻断P5-D1；不批准把HTTP/服务端观测改为MONOTONIC。** 本轮唯一一次45秒、无HTTP同步观测中，Windows QPC与两种RAW读取路径相容，而MONOTONIC、REALTIME、gettimeofday相对QPC累计少走至少3.527秒。可支持的局部计时选择是**经QPC见证的RAW**；Lua分段及业务计时仍处于异常域，所以仅保留RAW不能让整个诊断有效。

本轮没有改系统时钟、NTP、TTL、限额或产品代码，没有重启WSL、挂载任务数据文件、启动API/Redis、运行campaign或回归。原steady展开+7.5716285574% FAIL和P5-D1测量0/60对、NOT_EVALUATED均保留。第5阶段未完成，第6阶段未启动。

## 1. 旧QPC证据实际对应什么区间

`run.py:40–60`先读RAW、启动一次PowerShell读取QPC/Windows UTC，返回后再读RAW。两次QPC读数的间隔被夹在：

`[final.rawBefore − initial.rawAfter, final.rawAfter − initial.rawBefore]`

这个区间包含进程启动与IPC不确定性。`hostClockSummary.stable`只检查QPC是否落在该RAW区间再加减1秒，以及Windows UTC是否与QPC相差不超过2秒；它从未比较QPC与Linux MONOTONIC，也没有给Linux UTC同区间端点。因此“QPC稳定”不能解释为“QPC证明MONOTONIC正确”。

| 旧预检 | QPC间隔 | QPC对应的精确RAW间隔范围 | 另行采样的Linux循环 |
|---|---:|---:|---|
| 初始 | 150.294396s | [150.000588, 152.167112]s | RAW150.000173、MONOTONIC150.000127、UTC153.662008s |
| 唯一修复后 | 31.769255s | [31.528979, 31.991418]s | RAW31.528486、MONOTONIC/UTC30.000113s |

修复后的QPC约31.77秒，已落在不额外放宽的RAW区间中。它没有显示外部仅经过30秒。但旧记录只有RAW包围QPC调用；循环与QPC的起止点并不完全重合，不能用31.769−30.000直接计算MONOTONIC的精确误差，也不能只凭这些数把某一域指定为绝对权威。这正是补一次同步观测的理由。

## 2. 唯一一次同步观测

固定45个QPC秒、名义0.1秒间隔、最多600组；实际414组，全部保留。一个持久PowerShell进程在READY后接受序号，每次返回QPC读数、频率及Windows UTC；每个QPC事件均被各Linux时钟的before/after包围，避免每次启动进程的宽窗口。额外读取直接`clock_gettime`系统调用，区分时钟域和库函数读取路径。没有HTTP、Redis请求或系统改钟。

前后均为同一boot `eb99cf06-30ef-4272-b979-df77f66cc91b`、`tsc`、timesyncd active/enabled。QPC实际45.0265374秒，Windows UTC45.026秒。各域的QPC夹取窗口最大均小于预先设定的10ms；没有负窗口，也没有丢弃任何组。RAW窗口中位数约0.382ms。

| Linux读取路径 | 对应首末QPC事件的耗时间隔范围 | 全部414组中最大QPC区间外偏差 |
|---|---:|---:|
| Python `clock_gettime_ns(RAW)` | [45.023311, 45.033582]s | 0 |
| 直接syscall RAW（对应Go显式分段路径） | [45.023340, 45.033496]s | 0 |
| Python `monotonic_ns()` | [41.489434, 41.499422]s | 3.527205s |
| 直接syscall MONOTONIC | [41.489468, 41.499320]s | 3.527305s |
| Python `time_ns()` / REALTIME | [41.489435, 41.499421]s | 3.527206s |
| 直接syscall REALTIME | [41.489474, 41.499312]s | 3.527311s |
| libc `gettimeofday`（对应Redis TIME来源） | [41.489487, 41.499295]s | 3.527324s |

每组的QPC耗时都处于两种RAW路径各自的累计区间内。另五条路径相互接近，但都偏离QPC；“两个钟一致”在这里不是独立验证。库函数和直接系统调用结论相同，排除了仅由Python浮点减法、Python封装或单一库函数路径造成这一差异的解释。

相邻采样没有可靠负增量，亦没有超过50ms的单步区间外偏差；观测表现为累计进度差异，不能写成已证实的某次MONOTONIC倒跳。尚未定位内核校时、虚拟化计时或宿主同步中的具体根因。本次观测在恢复后的tsc状态进行，不能冒充对旧Hyper-V状态的重新测量。

## 3. 计时来源及影响

| 使用位置 | 实际来源 | 当前影响 |
|---|---|---|
| 驱动`latencyMs`、`elapsed_clock()` | Python libc `clock_gettime(CLOCK_MONOTONIC_RAW)` | 本次RAW与QPC相容；可以报告该窗口内的物理经过时间，但仍须持续见证 |
| `serverTiming`及`readtiming.Span` | `x/sys/unix.ClockGettime(RAW)`直接syscall | 与Python RAW属于同域但读取路径不同；本次分别验证均与QPC相容 |
| Go `time.Since`、预算扣减、context超时、worker ticker | Go runtime的MONOTONIC | 相对宿主经过时间可延后预算耗尽/调度；不能只换观测时钟就声称运行环境正常 |
| `CommentReadTiming`旧字段、Store累计Duration、`BudgetElapsed` | Go `time.Now`附带的单调分量 | 与RAW详细分段不同域，不能直接相减来认定纯SQL或排队耗时 |
| 诊断Lua `TIME`差、业务Lua `now` | Redis7.0.15 `timeCommand`调用`gettimeofday` | 脚本分段和总时长可共同少计；“脚本时长≤RAW RPC”是单向检查，无法排除少计 |
| Gate TrustedAt、签名游标/快照绝对到期、Redis PXAT/PTTL | Guest REALTIME经授权校验/绝对时间存储与比较 | 物理寿命可能不同于1800个真实秒；漂移或跳变还会影响lease、时钟偏差检查和冻结判断 |

本机Python3.12.3的`get_clock_info`确认monotonic为CLOCK_MONOTONIC、time为CLOCK_REALTIME。本机Go1.22的`runtime/sys_linux_amd64.s`与`time_linux_amd64.s`分别读取MONOTONIC，以及REALTIME+MONOTONIC；已安装`x/sys`的ClockGettime则明确走SYS_CLOCK_GETTIME。产品预算代码见`commentsnapshot/types.go:173–198`，Gate在`authorization_gate.go`调用`g.clock().UTC()`。Go的UTC/Truncate会移除单调分量，不能把这些绝对业务时间当作RAW或单调计时。[Go时间语义](https://go.dev/pkg/time/?m=old)

Redis TIME采用实时钟；PXAT保存绝对Unix毫秒，PTTL以到期值减去实时毫秒。Lua中的键过期判定可采用脚本起始时刻快照，**这不意味着TIME命令的两次调用使用冻结的同一值**。见[Redis7.0.15时间与命令统计实现](https://github.com/redis/redis/blob/7.0.15/src/server.c)、[过期判断](https://github.com/redis/redis/blob/7.0.15/src/db.c)、[PTTL实现](https://github.com/redis/redis/blob/7.0.15/src/expire.c)。INFO命令耗时还取决于Redis实际采用的时钟类型：源码允许硬件单调计时或ustime回退；本轮未启动Redis确认运行时类型，不能拿旧INFO均值当独立可信时钟。

Windows Stopwatch基于QPC，适用于同机时间间隔，而不是UTC绝对时间授权。这里使用的是QPC事件被guest读取包围的区间证据，没有假设两系统时间原点相同。[Microsoft QPC说明](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)

## 4. 可接续的协议裁定

1. **保留RAW作为HTTP和Go详细分段的候选耗时源，配合同一持久QPC见证器。** 后续若重开诊断，应记录所有被使用域的同步夹取区间，直接计算区间外偏差；不要继续把旧`hostClockSummary.stable`解释成跨钟全部通过，也不要依靠每次启动PowerShell的宽窗口。
2. **本环境不批准切为“QPC见证的MONOTONIC”。** 本次见证恰好否定了这个候选。也不以事后比例缩放MONOTONIC/REALTIME、将其统一乘45.026/41.49，或只选择对P95有利的计时域。
3. **完整P5-D1当前仍阻断。** Lua分段来自REALTIME，产品deadline/worker来自MONOTONIC；即使RAW自身可用，当前测量仍不能按预定正常运行条件解释。完整校验占比可能在统一匀速缩放时抵消，但没有证据证明每个短脚本内所有阶段共享同一缩放，不能据此采信80%/70%判据。
4. 重新进入P5-D1的必要条件，是在同一运行配置下使RAW、MONOTONIC及REALTIME/gettimeofday都与QPC见证的经过时间满足原计时域一致性要求，并保留全程监测、脚本非负和嵌套闭合检查。原0.2秒预检界限及5%产品P95门槛均保持；预检通过仍不是毫秒级脚本测量的充分证明。TTL的实际30分钟结论还必须同时满足绝对到期行为与独立经过时间证据，不能用QPC替代产品授权时间。

下一步应处理环境计时一致性，再由Sol按新调度复用已验证的观测副本。本轮不安排第二次观测或系统修复。既有失败不改标，旧通过结论保持原版本和当时证据范围。

原始同步记录：`D:/HnuHole-task-storage/comment-snapshot-redis-20261024/p5d1-clock-review-observation.json`；一次性观测程序：`tools/comment-snapshot-process/p5d1_clock_observe.py`。离线重算、来源及校验见[机器证据](stage-5-clock-protocol-review-evidence.json)。
