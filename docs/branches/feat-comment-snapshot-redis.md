# COMMENT-SNAPSHOT-REDIS-01 评论分页快照 Redis 迁移

> **2026-10-27 PR84已合并，main默认Redis：** [PR #84](https://github.com/zewbby/HnuHole/pull/84)合并 `ad0c47ce98cc13093be9b00b48e5d8ea37443cdb`。默认Redis新建及PG/Redis双读，标准C模板接通；启用评论却缺快照配置时启动明确失败，显式PG回退保留。配置5项、build/vet、独立只读审查和12个适用自动workflow通过。现有开发Redis接线只读核对一致，运行环境未改；性能/真机/30分钟未追加验收，生产未发布。见[实现与验证](../design/comment-snapshot-redis/main-default-20261027.md)；下方默认PG/待合并状态保留原历史时点。

> **2026-10-27 PR80已合并 main：** 合并 `4e7b0fb7d05daa579eb37138d374bb495d4fea30` 与已测 head `a2e98eb` 完整tree一致，既有适用CI通过。一次指定性能场景PASS，历史FAIL及其他未验项保留；同机开发Redis已授权启用并保留PG旧游标读取，仓库默认仍PG，生产未发布。本次仅合并与文档收尾，无新产品测试、性能采样或部署。见[最终合并交接](../design/comment-snapshot-redis/merge-receipt-20261027.md)。下方待提交／未合并／未启用状态均保留原历史时点。

> **2026-10-27 Publish 局部写优化本地完成：** 按已审定方案增加严格条件下的单字节发布，原全量校验、SQL 后 Publish 及失败补偿保留；真实 Redis/AOF、两项真实 SQL、build/vet 定点检查通过。首次新测试 token 编码夹具失败已修正，仅复跑该子例，原日志保留。限定只读复核无阻断；本轮送审的最终 head 与适用 CI 以 [PR80 Checks](https://github.com/zewbby/HnuHole/pull/80/checks) 和[送审回执](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/post-pr-publish-state-delivery-sol-20261027/delivery-report.md)核对，不复用旧 head 结果；原端到端 +7.571629% FAIL 与启用前性能待验保留，默认 PG/关闭 Redis，未部署。见[实施记录](../design/comment-snapshot-redis/publish-state-optimization-20261027.md)。下方 PR/CI 为原版本历史。

> **2026-10-26 阶段7功能与PR/CI交付完成：** 已按具体授权提交并推送[PR #80](https://github.com/zewbby/HnuHole/pull/80)，任务分支已整合main c17a667。功能及CI修复版本的15个workflow/26项实际job检查通过；性能整轮job按设计SKIP，未作为性能通过。两次实际失败及修复、被测head、逐job证据见[阶段7回执](../design/comment-snapshot-redis/stage-7-pr-and-ci.md)及PR Checks；本回执后仅文档变更的最终head以PR实时检查和[D盘交付记录](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/stage-7-pr-delivery-20261026/README.md)核对。阶段5性能仍启用前待验，原P95 FAIL保留，默认PG/关闭Redis；未合并、部署或启用。下方等待授权/未提交/CI进行中为历史时点。

> **2026-10-26 阶段6完成，三项修复复核PASS：** R6-01～03均已闭环；仅复核六文件diff、直接上下文及既有定点证据，未发现新阻断，未重跑验收。六文件及九份日志摘要一致，其他1435个受保护文件和146条台账不变。性能仍为可靠环境／Redis启用前待验，原P95 FAIL保留，阶段5不记全PASS；默认PG/关闭Redis。下一轮GPT-6.1 Sol/high进入阶段7提交PR及适用CI；合并、部署、启用未授权。见[有限复核报告](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/stage-6-fix-review-20261026/review-report.md)。下方待修、待复核等描述保留原时点，不代表当前状态。

> **2026-10-26 阶段6终审完成，待3项P2修复：** 用户已同意停止本机性能试跑，性能改为“待可靠环境验证／启用Redis前待验”，原steady展开+7.571629% FAIL保留，阶段5不记全PASS。终审核对并发、授权、SQL后Publish、额度/预算、回收、限流隔离和兼容回退；发现手动重试丢失排序/刷新意图、示例默认启用Redis、定位接口声明未实现参数三项。下一轮Sol/high做最小修复及定点验证，再推进已授权PR；本轮未改产品或重跑验收。运行默认仍PG，但示例尚待改为PG/关闭Redis，不能称全部交付入口已安全收口。合并、部署、启用Redis未授权，不再搭性能环境或运行P5-D1。见[D盘完整审查](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/stage-6-final-review-20261026/review-report.md)。下方旧“第6阶段未开始”等均为历史。

> **2026-10-26 首次同步后稳态检查仍FAIL：** NTP报告已同步后，唯一45秒QPC观测429组全部保留；QPC45.085143秒，RAW一致，MONOTONIC/REALTIME/gettimeofday约43.01秒，偏差超过2.060秒。原0.2秒要求未通过，按调度停止自动尝试，P5-D1未启动、仍0/60；未重启/改钟/发业务HTTP。此前服务恢复PASS与620MB冷备份保留，原性能FAIL不改标。见[D盘稳态报告](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/approved-maintenance-20261026-r1/steady-check-report.md)。下方为历史。

> **2026-10-26 单次已授权WSL维护完成：** 三PG干净停机并完成约620MB私有冷备份，目标terminate仅1次，内核boot已更换；原C/V后端、PG/Redis/系统服务恢复，Windows原CA健康检查200，Gate代次与RECOVER审计不变。唯一449组观测中RAW/MONOTONIC与QPC45.037601秒相容，但REALTIME约49.27秒，窗口包含初次NTP校时，稳态未验证；P5-D1仍0对、原性能FAIL保留，无追加重启或采样。见[D盘执行回执](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/approved-maintenance-20261026-r1/execution-report.md)。下方为历史。

> **2026-10-26 计时协议裁定完成：** 唯一45秒同步观测414组全部保留，QPC45.026537秒与两种RAW路径相容；MONOTONIC/REALTIME/gettimeofday仅约41.49秒，区间外偏差至少3.527秒。不能改用MONOTONIC；RAW局部可用，但Lua分段、业务超时/worker及绝对时间条件仍受异常域影响，P5-D1继续环境阻断、0对NOT_EVALUATED。未改钟/NTP/产品，未运行HTTP或回归；原性能FAIL保留。见[裁定与证据](../design/comment-snapshot-redis/stage-5-clock-protocol-review.md)。下方为历史。

> **2026-10-26 P5-D1执行停止于时钟预检：** Sol/high已完成D盘观测副本、构建/vet、5项真实Redis/race回归及观测等价核对；初始最大计时域偏差3.661835秒，唯一临时修复后仍1.528373秒，均超过0.2秒。固定60对测量/预热/HTTP均0，80%/70%判据NOT_EVALUATED；按协议未重试。已独立核验恢复tsc/NTP及卸载。原+7.571629% FAIL保留，阶段5未完成。见[记录与证据](../design/comment-snapshot-redis/stage-5-p5d1-execution.md)。下方为历史。

> **2026-10-26 steady展开最小改动审查完成：** 原+7.571629% FAIL保持；离线确认两次Redis完整账本扫描及成功后两次Gate收尾，但尚无证据选定足以达标的安全产品修复。下一步由GPT-6.1 Sol/high实施一次新增Lua/PG写入分段的固定60对诊断，仅steady展开；公共授权和校验规则暂不改。诊断未运行，本轮产品/HTTP/系统改动均为0；阶段5未完成，第6阶段未启动。见[具体方案与判定规则](../design/comment-snapshot-redis/stage-5-steady-expanded-fix-review.md)。下方为历史。

> **2026-10-26 两项剩余性能定点验收完成：** 最终4b0eef09/API87095083在正常worker和真实LIVE条件下，compat续页1000对P95 +0.062251% PASS，steady展开300对 +7.571629% FAIL；2600条测量HTTP零错误，RAW/QPC/资源判据通过。唯一剩余阻断为最终版本steady展开性能：Gate尾部行锁跨度约20–26ms，Redis Prepare/Publish约5ms，传输残差约0.4ms；不据此认定单一因果。原时钟预检失败保留，唯一条件式修复后已恢复tsc/timesyncd active/enabled并独立核验，运行时0、D盘任务存储已卸载。其他验收未重跑，旧结果按版本复用。阶段5未完成，第6阶段未启动，未改产品/追加采样/提交/合并/部署。见[记录与证据](../design/comment-snapshot-redis/stage-5-performance-gaps-execution.md)。下方为历史。

> **2026-10-26 第5阶段最终证据审查完成：** 两条4b/API870的compat回复P95 PASS有效；旧功能/故障/容量/实际30分钟/真我限定证据按原版本复用。阶段5仍不能收口：compat主续页修正预热后缺完整达标证明；steady展开旧单轮+9.977%未由适用证据关闭。保留各轮FAIL，不采用事后三轮汇总或跨模式替代。第6阶段未启动；本轮仅离线审查，未改产品、追加采样或重跑验收，未提交/合并/部署。见[裁决与证据](../design/comment-snapshot-redis/stage-5-final-evidence-review.md)。下方为历史。

> **2026-10-26 两条回复P95定点完成：** 最终4b0eef09/API87095083在正常worker、真实HTTP登录生成且全程保留的LIVE占用下，compat预览−1.266%、展开+1.719%，各300对、1200请求零错误，RAW/QPC及资源判据PASS。首轮UTC跳变失败保留；获续权后仅一次临时修复与定点执行，原tsc/timesyncd active/enabled已恢复并独立核验，运行时为0，D盘任务存储已卸载。旧目录未迁移，新大产物直接写D。两项指定缺口已收口；历史单轮失败与未确认汇总口径的使用边界交独立审查，不自行标整体阶段5完成、不自动追加采样。第6阶段未开始，未提交/合并/部署。见[记录与证据](../design/comment-snapshot-redis/stage-5-replies-repaired-execution.md)。下方为历史。


> **2026-10-26 两条回复P95定点验证：** 已固定4b0eef09/API87095083及每路径300对、<=5%参数；只读预检第180秒WSL UTC相对RAW跳变+1.293秒，超过事先0.2秒门槛，停止于HTTP采样前。预览/展开各0样本，均NOT_RUN，不生成新P95或覆盖旧失败；无系统修改、无重试/扩样。用户更正后取消未完成迁移，原缓存/源码未移动删除；后续新缓存/大产物用D盘任务目录。第5阶段仍未完成、第6阶段未开始。见[记录与证据](../design/comment-snapshot-redis/stage-5-replies-targeted-execution.md)。下方为历史。


> **2026-10-26 第5阶段空worker最小修复完成：** CleanupSessionResults只在短预算内成功确认无LIVE候选时跳过；错误回原父上下文，实际清理保留原最终Gate/Abort。最终源码4b0eef09/API87095083的build、受影响vet及15项真实SQL/race定点测试PASS、0FAIL/0SKIP；确认空批次Gate三次接口调用降为0，非空安全路径不变。未重跑整轮/30分钟/真机；历史P95失败保持，新版本P95尚无完整结论，第5阶段仍未完成、第6阶段未开始。一次性夹具已收尾，系统设置未改，未提交/合并/部署。见[实施及证据](../design/comment-snapshot-redis/stage-5-worker-precheck-execution.md)。下方保留历史。


> **2026-10-26 第5阶段空worker预检审查完成：** CleanupSessionResults可按限定方案实施：仅成功查明无LIVE候选才跳过，真实清理保留原最终Gate/Abort；预检最多50ms且不超过父剩余预算10%，异常回原路径。并发到达按实际整轮调度重查，既有阻塞文件锁不支持绝对墙钟清理上界，未据此声称2秒清完。已列W1–W6必要单项验证，产品代码未改、测试未跑；第5阶段仍未完成，第6阶段未开始。见[限定审查](../design/comment-snapshot-redis/stage-5-worker-precheck-review.md)，下一步由调度切Sol/high实施；不重复未受影响验收，不重开整轮。下方为历史。


> **2026-10-26 第5阶段针对性修正完成，阶段仍未满足性能条件：** Sol/high修复TCP_NODELAY、中点预热及完整请求RAW分段计时；有效20请求对照把额外传输等待由约42ms降到约0.4ms。最终源码0481b785/API0c419619的build/vet/host/race、真实SQL/Redis31 PASS和共享限流39 PASS；既有fixture SKIP保留。用户撤回整轮后立即停止于兼容初页各129条，保存部分数据，未运行下一模式；旧回复P95失败不改标PASS。原tsc、timesyncd active/enabled实际恢复，运行时无残留。两项旧版本真实30分钟及真我限定证据准确复用；公共Gate/空worker竞争待调度审查最小方案，未改授权或worker语义。第6阶段未开始，未提交/合并/部署。见[本轮记录](../design/comment-snapshot-redis/stage-5-targeted-execution.md)。下方为历史。


## 2026-10-25 第5阶段第二次限定审查完成

**2026-10-25 COMMENT-SNAPSHOT-REDIS-01 第二次限定审查完成，阶段5未完成：** 同一冻结二进制正式兼容预览+7.312%/展开+8.169% FAIL，steady四路径PASS；容量/故障/限流隔离/回退及同二进制增长补跑PASS。PG兼容实际1805秒PASS；Redis阅读原轮58次后400导致harness FAIL，UTC/单调参考差44秒且初始expiry未记录，保留失败、不认定提前到期或30分钟PASS。JSON拆分约69–71%脚本原语耗时在解码/编码，支持定长STRING首修；完整状态/迁移/回退、清理上界与PG发出版本桥接方案已形成，未实施新格式。等待调度切Sol/high实现并完整复验，第6阶段未开始，未提交/合并/发布。见[审查](../design/comment-snapshot-redis/stage-5-second-limited-review.md)、[证据](../design/comment-snapshot-redis/stage-5-second-review-evidence.json)。


## 2026-10-25 第5阶段第二次限定审查进行中

**2026-10-25 COMMENT-SNAPSHOT-REDIS-01 第5阶段第二次限定审查进行中：** 调度指定Astra/xhigh，不是阶段6；同一冻结二进制正式兼容模式预览+7.312%/展开+8.169% FAIL，steady四路径PASS，均完整保留。容量/故障/限流隔离/回退PASS；增长脚本覆盖运行文件的准备错误已保留并以同一二进制补跑PASS。实际30分钟阅读/兼容仍不中断运行。拟评估完整扫描的定长STRING，尚未实施；审查同时发现清理高延迟上界和PG V1发出桥接需补证。阶段5未完成，未提交/合并/部署。见[审查](../design/comment-snapshot-redis/stage-5-second-limited-review.md)。


## 2026-10-25 第5阶段Sol统计复用执行中

**2026-10-25 COMMENT-SNAPSHOT-REDIS-01 第5阶段Sol执行中：** 保留单次编码并复用完整校验统计、合并维护采样；真实Redis12 PASS，最终快照/评论28 PASS/2既有fixture SKIP、共享限流39 PASS/1既有设备fixture SKIP，Go主机/build/vet PASS。独立Android2502真实TLS读取live5/down2及每阶段九项fixture界面PASS，lease已释放，整条生产UI/原生vault不提升。两种统一诊断均FAIL，仅诊断；同一冻结二进制的正式双模式四路径、进程容量/故障及真实时间campaign正在运行，第5阶段未完成，第6阶段未开始；未提交/合并/部署。见[执行记录](../design/comment-snapshot-redis/stage-5-stats-reuse-execution.md)及[机器证据](../design/comment-snapshot-redis/stage-5-stats-execution-evidence.json)。


## 2026-10-25 第5阶段限定审查完成，阶段未完成

冻结版本的双独立API、501阅读容量、1024额度与32并发拒绝、真实故障、实际1805秒Redis阅读及1803秒PG V1/V2兼容/旧表停用/显式回退已记录。正式P95四路径为+3.461%、+2.955%、预览+5.317% FAIL、-0.444%。单次JSON编码候选的11项真实Redis-race通过，四路径为-2.731%、主翻页+6.174% FAIL、+4.258%、-6.808%，不能拼接不同版本通过项。

[限定审查](../design/comment-snapshot-redis/stage-5-limited-consistency-performance-review.md)及[证据](../design/comment-snapshot-redis/stage-5-limited-review-evidence.json)分别保留两版本、真实时间范围和测量限制。候选未发现削弱列明不变量，但尚不够；等待调度切回Sol/high统一完整fixture/基线模式，定位重复名录维护和排队，执行修复与完整受影响复验。设备lease已释放，端到端真机仍待接续核实。第5阶段未完成，第6阶段未开始；本需求未提交、合并、部署。


## 2026-10-25 第 4 阶段完成回执（覆盖下方历史）

已完成客户端恢复与置顶衔接。单次250ms重试、首屏nonce复用、主/回复分别失效、成功刷新替换、局部手动重试、楼层内本人回复和ID去重、保留草稿/阅读锚点及刷新代次围栏已实现。最终全客户端964 PASS/0FAIL/3既有fixture SKIP，analyze0，ARM64 bundle/APK PASS；真实Dart/TLS/Redis/SQL live5请求/down2请求PASS。用户要求重试后，真我RMX3366/API34独立.commentsnapshot包2026102501的9项生产widget场景全部通过，页面/authority为fixture，真实网络证据另列；不将二者冒充同一条端到端手机链路。

[第4阶段详情](../design/comment-snapshot-redis/stage-4-client-recovery-and-pins.md) · [机器证据](../design/comment-snapshot-redis/stage-4-evidence.json) · [校验](../design/comment-snapshot-redis/stage-4-validation.json)。原安装Failure[-99]及待验记录保留，重试已成功覆盖该九项待验；日常2427未变，独立包停止、lease释放。阶段5–7等待后续调度，未commit/push/PR/合并/发布本需求。

## 下方为第 3 阶段及更早历史记录

## 2026-10-25 第 3 阶段完成回执（覆盖下方历史状态）

GPT-6.1 Sol / high 调度；正式依赖 PR #73 的 main 合并提交 `c05198155543b8d1a259dc41fdeb860126dee7d0` 已通过 fast-forward 集成，原有差异先完整备份后重放，无新 commit，无候选源码复制。快照服务端及 runtime/CLI/契约/CI 已实现，固定 30 分钟 TTL、配额和预算、SQL 后发布、失败补偿、V1/V2 双读及显式 PG 回退、回复和定位路径均有对应代码。

最终快照/评论隔离回归23顶层PASS/0FAIL/2SKIP；正式共享限流39顶层PASS/0FAIL/1设备夹具SKIP；全后端host/build/vet和完整契约PASS。新真实TLS/Redis/SQL链路、混合配额、旧表停用、实际SQL COMMIT失败补偿和Gate冻结已验。未将跳过的Dart/设备夹具、两个API命令进程、实际30分钟阅读、容量/P95、客户端或远端CI记作完成。

[第 3 阶段详情](../design/comment-snapshot-redis/stage-3-backend-and-integration.md) · [机器证据](../design/comment-snapshot-redis/stage-3-evidence.json) · [最终核验](../design/comment-snapshot-redis/stage-3-validation.json) · [配置与回退](../design/comment-snapshot-redis/runtime-and-rollback.md)。阶段4–7等待后续调度；本需求未commit/push/PR/合并/发布。真机验收待用户于2026-10-25验收，后续能独立操控则自行完成。

## 以下为阶段 1–2 历史记录

更新时间：2026-10-24。分支 `codex/feat/comment-snapshot-redis`，独立工作区 `E:/Hnuhole-env/source/HnuHole-comment-snapshot-redis`，固定基线 `8ed8f2870b1724de2837ea40a6e3764c008780f7`。

按 [需求 V1.1](../design/comment-snapshot-redis/requirements-v1.1.md) 与 [七阶段计划](../design/comment-snapshot-redis/execution-plan.md) 串行推进。第 1 阶段盘点和第 2 阶段设计完成，仅本地文档与抽象设计验证，无产品实现、提交、PR、合并或发布。

| 阶段 | 状态 | 入口 |
| --- | --- | --- |
| 1 固定基线和复用接口 | 完成静态盘点；调度指定 Sol / high | [阶段记录](../design/comment-snapshot-redis/stage-1-baseline-and-interfaces.md)、[机器证据](../design/comment-snapshot-redis/stage-1-evidence.json)、[静态验证](../design/comment-snapshot-redis/stage-1-validation.json) |
| 2 一致性及发布设计 | 完成；调度指定 Astra / xhigh | [设计](../design/comment-snapshot-redis/stage-2-consistency-and-rollout.md)、[设计验证](../design/comment-snapshot-redis/stage-2-validation.json)、[ADR](../design/comment-snapshot-redis/adr/0001-isolated-instance-and-conservative-reservations.md) |
| 3 服务端迁移 | 等待调度，未开始 | 正式共享限流依赖需复核后接入，不复制其未提交实现。 |
| 4–7 客户端、联调、审查和交付 | 未开始 | 按阶段继续，不自动越级。 |

共享限流候选位于 `feat/shared-rate-limit-abuse-control`，尚未提交/合并，本轮没有复制或修改其源码。后续实施须集成其正式交付；本阶段已记录可复用接点，未将其 CI 或测试结论提升为本任务验收。

手机无需用户现在配合。后续可自行操控则验收，否则明确记录“真机验收待用户于 2026-10-25 验收”，继续非设备工作。
