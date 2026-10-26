# 第5阶段定长名录实现与复验
> 2026-10-26 当前状态：固定三轮收尾后仍有兼容预览/展开P95 FAIL；限定根因诊断已完成，见[根因报告](stage-5-root-cause-diagnosis.md)。原系统配置已恢复并核验，本任务运行时全部清理。产品源码6fb0289c未改，限定真机及两项真实30分钟PASS保留。阶段5未完成，等待调度Sol/high针对性修正；下方为执行历史。

> **2026-10-25 授权后第5阶段复验进行中：** 已核实调度聊天中的用户授权，原配置和恢复办法已记录；临时Hyper-V时钟/NTP停用后的5分钟稳定预检PASS，最大偏差约5.4微秒。稳定环境受影响回归和Dart链路PASS，最终源码6fb0289c及冻结API 0139291c正在完整双模式P95/进程/两套实际30分钟campaign。保留共享负载观测，高负载批次不提升为有效验收；结束无论成败恢复原配置。真机锁屏待用户验收，不阻塞其他工作。未提交/合并/部署，第6阶段未开始。


任务 `COMMENT-SNAPSHOT-REDIS-01`，分支 `codex/feat/comment-snapshot-redis`，2026-10-25。

**授权前状态（历史）：COMPONENTS_PASS_FORMAL_NOT_ACCEPTED_AWAITING_STABLE_TIME；阶段5未完成。** 用户明确要求继续后已恢复实现，没有将指挥会话通知失败作为阻塞。定长首版正式验收仍有一项5.800% FAIL，真实时间测试识别出环境不稳定；后续等价优化的组件检查已通过，完整进程/P95/实际30分钟仍待稳定时钟环境重跑。真机仍锁屏。未提交、推送、合并或部署，第6阶段未开始。

当前优化版生产源码摘要 `6fb0289c2eefab59bdd766c0c19239b1959f6843fc813d97a00b9628bed88846`，工作区与Linux测试镜像相同。机器记录见[优化版证据](stage-5-packed-opt-evidence.json)。没有将旧候选的正式通过项拼接到此版本。

## 实现与一致性边界

采用 `ledgerFormat=2` 的一个 STRING 名录；头部68字节、每项206字节、大端无对齐填充。新命名空间 `hnuhole:comment-snapshot:v2:<environment>:`、运行身份 `community_comment_snapshot_v2`、新epoch；policy hash绑定格式和记录长度。旧JSON实现不再嵌入生产脚本；历史候选和失败证据保持冻结。

每次名录操作仍完整验证所有记录，重算全局字节和所需账号统计；拒绝重复UUID/请求键、错误长度、超过53位精确整数范围的时间戳、非法状态/flags/期限和预算溢出。nonce命中也不能跳过损坏的其他记录。Prepare追加、Publish/Abort修改状态、release拼接存活记录后，仍整体用一个SET PXAT原子保存，仍为O(N)。载荷MAC、公开V2游标、1800秒TTL、1024账号额度、64MiB模块预算、100ms调用期限及500ms操作预算均保持原值。

SQL/Safety Gate成功提交后才Publish，成功Publish后才发游标。不确定写入保守计账；ABORTING不可发布；所有物理DEL确认后才核销。Load继续验证control和载荷MAC，名录损坏不破坏仍完整的旧不可变数据读取。

优化版把uint64先拆成精确的两个uint32，检查高32位≤2097151后才组合，避免先发生double舍入；缓存常量/函数并以局部值累计完整扫描统计。保存时直接拼接头部和所需字节段，将追加/状态修改中多余的整份拷贝去掉；格式和提交协议不变。

后台Collect保留5秒上下文；每批DEL最多64键，最多min(8,poolSize−1)个工人，默认7个，预留一个前台连接。每个调用的期限从工人取到任务后开始；任一批失败则取消并保持配额，不核销不确定删除。请求内Abort仍顺序处理。运行配置检查ceil(ceil(maxEntries/batch)/workers)×deadline + 2×deadline + 500ms < 5s，拒绝无法满足包络的配置，不自动放宽参数。

commentsnapshotctl -drain要求单独operator凭据，完整校验后将READY转DRAINING；没有自动反向激活。禁止新的Prepare，已有pending仍可在原lease内Publish，旧Load/Lookup和清理保持可用。

## PG发出版本、迁移与回退

postgresCursorVersion默认0（等价1）发出V1；显式2才发出PG V2，已有V1续页继续V1。先以PG创建/V1发出部署双读版本，确认所有节点支持V2后才显式发V2/开启Redis创建。向V1-only回退前，停止所有V2创建者，等待最后PG V2的30分钟窗口及R排空。

旧JSON Redis仅用于本任务的一次性验收，尚未生产部署；首次生产从PG迁移到全新格式2域。不得就地解释或改写旧v1 JSON域，不为丢失状态自动换epoch、初始化或静默切PG。

如果将来存在真实旧JSON R域，必须先保留能读旧格式的完整版本、显式改PG创建并把旧R计入混合配额，排空旧域，等待最后允许的pending发布/高水位和物理回收确认。旧域存活时不得同时启用新R获取第二份1024账号额度或64MiB预算；确认旧域数据和预留均清空、全部节点具备新双读能力后才初始化新域。当前格式2程序不冒充JSON兼容读者。

## 优化版已完成的组件检查

- Go build/vet/host通过；host未配置SQL DSN，不据此声称真实SQL或设备通过。
- 快照/评论真实隔离回归31 PASS/0 FAIL/2既有fixture SKIP，包含13项真实Redis测试和16类损坏记录子场景，以及精确整数上界、PG V1桥接、并发额度、未知写入和排空检查。native分支明确未运行。
- 共享限流真实回归39 PASS/0 FAIL/1既有设备fixture SKIP，未扩大业务验收范围。
- 生产Dart读取器在真实TLS/SQL/Redis上live5/down2请求通过；客户端lib/integration共125份文件与已验证的当前源码相同。不声称native vault或整条生产UI端到端通过。
- 6000条合成ABORTING记录、每批DEL注入88ms延迟，功能回收通过；Go时钟计量1312ms。当前时钟异常下，该数值不能替代稳定环境的物理期限验收，也不是6000次成功创建。

最初SQL桥接测试错误要求最后一页存在nextCursor，修正测试后通过；原失败日志保留。真机重试在锁屏状态下未生成输出并超时，原失败保留；之后组件回归显式不运行native，不以外层历史通用console文案冒称设备通过。

## 隔离构造诊断

单独自有Redis、固定同一有效记录和时间，每版本预热10、100样本，固定seed交错先后次序；完整验证和本地追加/状态修改后返回字节校验值，不执行保存、SQL或数据发布。所有旧/新构造字节完全相同。以下为CLOCK_MONOTONIC_RAW客户端均值，包含TCP/auth传输，不能称纯服务器CPU或HTTP验收：

| 记录数 | 追加旧→新 ms | 降低 | 状态修改旧→新 ms | 降低 |
| --- | ---: | ---: | ---: | ---: |
| 1024 | 2.980 → 2.236 | 24.98% | 3.213 → 2.200 | 31.51% |
| 1900 | 5.175 → 3.828 | 26.03% | 5.646 → 3.772 | 33.19% |
| 6000 | 15.117 → 10.872 | 28.08% | 16.196 → 10.804 | 33.29% |

[完整诊断](stage-5-packed-opt-codec-profile.json)仅证明等价构造和该隔离成本下降，不替代≤5%的正式P95。

## 定长首版正式结果完整保留

首版摘要b359ad45b58388d05e9d674f976cd991078d95e47cbb9945e8cc9019eda1a158，唯一API二进制8d27efb65e4080243d462483c3b1b32b4a9ccb7af01a73f7a9ef53ec92be497d。

| 模式 | 首次 | 续页 | 预览 | 展开 |
| --- | ---: | ---: | ---: | ---: |
| compatibility | +4.921% PASS | +1.633% PASS | +3.868% PASS | −1.332% PASS |
| steady | −4.623% PASS | −4.561% PASS | −1.088% PASS | +5.800% FAIL |

两个模式均固定200/1000/300/300样本、每来源预热30、中点交换绑定、平衡随机请求次序；整个批次FAIL。独立进程/重启、501容量/1024额度、故障、限流隔离、增长、快速回退均PASS，证明范围仅属首版。新优化版的实际双API及完整正式批次尚未运行。

首版R实际时间脚本58次有效续页、到期400和显式刷新成功，单调计时1805.400秒，但最大UTC/单调差60.989秒，正确判ENVIRONMENT_UNSTABLE，不记稳定30分钟PASS。独立PG窗口也因时钟漂移失败，未执行其后续的到期/旧表撤除步骤；快速回退单列通过，不能替代真实窗口。原fixture完整运行至自身结局、正常清理，没有为重跑缩短。

见[首版最终证据](stage-5-packed-r1-final-evidence.json)。所有原始无凭据结果另存外层stage-5-evidence/packed-r1-*；私钥/password/bearer及private日志均不复制进仓库。

## 环境与下一执行入口

只读交叉观测显示Windows UTC/QPC基本一致，WSL UTC、MONOTONIC和RAW存在明显速率/跳变差异。5分钟预检最大偏差6.443秒，UTC/RAW最大约4.680秒；[预检](stage-5-packed-opt-clock-preflight.json)、[跨域观测](stage-5-packed-clock-domain-probe.json)完整保留。当前clocksource仍tsc、Ubuntu timesyncd仍active，没有修改系统时钟值或系统配置。

后续驱动已改用CLOCK_MONOTONIC_RAW测HTTP耗时，并逐请求保留UTC/monotonic/raw差值；两套真实时间记录签名expiry、Redis TIME/PTTL、双Linux时钟，支持独立Windows QPC见证。任何超限漂移都阻止验收，不能吞掉400、改变TTL、用新计时器覆盖旧FAIL。

已准备临时切Hyper-V时钟源/暂停Ubuntu NTP、结束后恢复的脚本，尚未执行；涉及整个WSL系统级状态，已向用户请求确认。只有稳定预检通过后才冻结新候选、完整重跑双模式四路径、所有进程故障/容量及实际R/PG各30分钟。脚本会拒绝在本任务fixture仍存活时激活，不重启WSL、不设置时间数值、不改变产品限额，恢复原tsc和active timesyncd；若不允许则需要其他稳定的执行环境。

真机RMX3366仍keyguard showing/input restricted，本任务lease已释放，独立.commentsnapshot包和临时输入/映射已收尾，日常包未改。用户解锁后才能完成当前候选的真机重验。

本页不提升既有模块总裁决。模块台账146项历史内容逐项深比较未改变。远端CI、提交、合并和发布均未执行。

批准执行的临时修复以Windows父进程try/finally托管，完整验收无论成功失败都会调用原配置恢复并记录结果。共享采样预先固定判据：CPU busy≥65%、IO wait≥25%、外部构建CPU合计≥300%（单核心100%）或发现外部压测工具即视为压力；每模式采样前要求连续20秒静默，等待最多600秒。采样期间异常负载保留全部样本并使整轮失效，不择样丢弃或停止他人任务。当前master与负载监控均为本次同步验收进程，不是调度自动任务。

用户在执行聊天明确回复已解锁后，当前6fb0289c源码的真机检查已重跑PASS：Android真实读取live5/down2，两个阶段各9项fixture widget通过。Go测试二进制运行生产handler、独立SQL/Redis与pinned TLS；不是把它称为正式cmd/api二进制0139291c的手机实测，也不提升native vault/整条生产UI。此次只在正式P95全部结束后与稀疏真实时间测试短暂重叠，记录用户明确重试指令；没有干扰性能采样。设备lease再次释放，独立包/私有输入/本轮USB映射清理，日常包不变。见[真机证据](stage-5-stable-native-evidence.json)。
