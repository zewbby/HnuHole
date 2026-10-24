# SHARED-RATE-LIMIT-01 共享限流与动作级防刷

## PR73远端CI回执（2026-10-24，最新）

CI记录时已提交/推送并创建 [Draft PR #73](https://github.com/zewbby/HnuHole/pull/73)，未合并/发布，待独立成员review。指定Android四阶段PASS；远端 `6e502442326fd04073c2ad9b5d434970bc0c5f21` 的13个workflow/23个实际job全部SUCCESS，逐run/job URL见[脱敏CI记录](../design/shared-rate-limit-remote-ci-verification.json)。此记录只针对6e50244；本次回执编写时，后续纯文档更新尚未形成新提交/CI；CI记录时为Draft，后续检查及送审状态以live PR为准。

原生已测产品提交 `33bdcc0894af230a722ee21455aa344ae456c9cf` 与测试镜像Git规范化等价；后续 `fded38e62e6f9b4aef3aaed1d38bfddeb240cace` 只修CI系统Python环境，`6e50244` 只修旧Android host overlay工具及测试，运行时代码未改，不重跑或拼加旧940/3SKIP/后端39及真机计数。

- 首轮33bd的Shared isolated-admission [run40099265585](https://github.com/zewbby/HnuHole/actions/runs/40099265585)/job120887853682 FAIL：setup-python动态loader依赖LD_LIBRARY_PATH，图片validator刻意env-i移除此环境；不是业务失败。外部remote-ci-initial-failure.json保留。
- fded38e改/usr/bin/python3系统venv+最小probe并保留setup-go PATH后Shared runner39 PASS、1 opt-in设备SKIP，四上传真实SQL通过；13workflow中12通过。唯一Post images [run40099624476](https://github.com/zewbby/HnuHole/actions/runs/40099624476)/job120888963687 FAIL是旧overlay精确锚点不接受workers gofmt空格，实际图片SQL/生命周期也PASS；外部remote-ci-post-images-failure.json保留。
- 6e50244仅修改 `tools/community-android-stage1/lab.py` 及对应测试，允许两种已知精确锚点且总数恰1；未知/重复仍ValueError。local tools210 PASS、Go overlay build PASS、Astra xhigh窄审无剩余P1/P2，最终远端13/23全绿。agent审查非GitHub成员批准。

root原生最终静态审计128文件/15Markdown、历史ledger其他entry深相等、四原report逐项匹配、policy PASS；旧暂存协作19测试及后工具全210包含同检查。当前文档仅补回执，不代表设备或旧host测试再次执行。下方“尚未提交/未PR/CI NOT_RUN”等均保留原时点，当前以本节为准。

## Android限定验收与送审授权追加（2026-10-24，最新）

用户新授权“做真机验收，做完后提pr进行远端CI验收”。指定四阶段真实Android已PASS，根接下来提交/推送并创建PR运行远端CI；当前仍未commit/push/PR，remoteCI NOT_RUN，未合并/部署。下方“未操作手机/无提交授权”等是此前时点，不覆盖本次新授权；原历史与其他模块裁决保留。

- 真我RMX3366/API34，独立包 `org.hnuhole.hnuhole_mobile.ratelimit`，versionCode2026102433，APK SHA256 `ca29017930eed7bdc71b9589c9541d4298674069a1e5c6b91a60d84cddf736dc`。实际Android Keystore+加密SQLite，force-stop后不同PID恢复15872→16481→17099→17746，不是整机重启。
- final-r11四份原生report全部PASS：rate-write完整帖评429草稿、真实DM429、队列取消/账号隔离；rate-read到期后3秒无自动发表、手动原键/原文/身份/目标/图片恢复和同会话保序；rate-unknown隐藏/永久close/迟到PUT、独立会话与ACK；rate-fault实际Redis CLIENT PAUSE5000ALL同run恢复、收件ACK及原命令恢复。
- 服务端计数区别真实429/503：write首次429=1；fault最终累计429=4/503=1，closed=1、lateCode=COMMAND_CLOSED、pendingIncoming=0。postTasks/commentTasks最终各2（各1priming+1原手动重试），不是2次用户重试；原文字/身份/channel/root/target/image hash实SQL匹配。取消键GET ABSENT、两个同会话消息顺序正确、独立会话/ACK继续。
- root实际view_image观察无“待发送”文本，r11点状是转圈动画一帧；r10完整圆弧仅辅助同widget视觉，不代证r11计数。四阶段使用真实TLS+双PG/Redis任务私有临时服务，不是完整生产cmd拓扑。
- native-source-manifest110产品变更文件aggregate SHA256 `7ab164efd7e8b14df1cf50461af19d1243db1772bb6c58acf4274b308a87e456`，测试镜像逐文件相同；基线HEAD仍8ed8f28，非commitSHA。旧107文件manifest/940host/3SKIP/39后端结果均保留原版本和范围，不重跑、不相加。
- device-analyze-r5分析0、device-apk-build-r11 PASS；device-services-r5最终PASS/exit0（270.70s，race271.718s）。opt-in新增device测试在常规CI未显式请求时SKIP是预期，不能冒充CI设备实测。
- 失败历史保留：native r8非法namespace/locator/operator目录；r9 DM timer/prime时序；r10 write PASS但429/503证据未区分，经Astra窄审补真实counter后r11全四阶段重跑。旧NTFS SDK/clang空文件和JNI stale .cxx构建失败通过现有完整ext4 Flutter3.47.5/SDK+任务JNIcache修正，无整套下载。
- 已停止自有.ratelimit、移除3个自有adb reverse、屏幕设置仍0；日常包2427/0.1.0-comment-detail未变，未清用户数据。自有双PG/Redis退出，private device目录为空，设备lease已released。

可提交的脱敏[原生证据JSON](../design/shared-rate-limit-device-verification.json)含四report与精简统计；原始日志/截图/APK/私有fixture/CA/controlToken/个人serial均留仓库外。证据根 `E:/Hnuhole-env/shared-rate-limit-evidence-20261024-8ed8f28/device/final-r11/`。窄审GPT-6 Astra/xhigh无剩余P1/P2，非GitHub成员批准。iOS、整机重启/掉电、全规模容量及生产验收NOT_RUN；本轮只提升指定Android场景，不提升历史整模块总裁决。

## 当前交付回执（2026-10-24，覆盖下方历史状态）

实现完成，仅本地未提交差异；最终r11及常规host/build/vet均PASS，不能将r10与其他版本结果拼总数。分支和授权范围同下，未提交/推送/PR/合并/部署；未操作现有DB/手机，历史原文保留。

| 阶段 | 实际执行模型 / 强度 | 当前 |
| --- | --- | --- |
| 1 盘点 | GPT-6.1 Sol / high | 完成 |
| 2 设计 | GPT-6 Astra / xhigh | 完成，只读设计审查 |
| 3 实现 | GPT-6.1 Sol / high | 完成 |
| 4 验收修复 | GPT-6.1 Sol / high | 完成限定本地验证：r11、host/build/vet PASS |
| 5 最终审查 | GPT-6 Astra / xhigh | 完成，R1–R5/F1–F6源码闭环，无未修P1/P2 |
| 6 交付文档 | GPT-6.1 Sol / medium | 完成；根独立UTF8/JSON/链接/blob/hash/diff核对PASS |

模型由各阶段实际agent执行，根协调与运行工具，不声称根会话直接切换自己的模型。审查在本chat，无伪造审查文件；不是GitHub成员批准或审查者运行测试。

实现：单Redis7 primary/noeviction、精确SW/TB、独立observe/enforce lane、最终一次业务SET；SQL固定PREPARED lease/epoch、ADMITTED证明、永久回执、policy/key hash及最终SQL围栏；verified-db dirty恢复屏障；C/V独立namespace/角色/ACL/密钥。四上传真实body读取/预留/settle(n>0+error)/read deadline，bytes仅SW。帖评429完整草稿、手动同键重试；DM首次一条文字、256持久队列、同会话保序与独立接收ACK；unknown隐藏后close永久终态，SENT不可假撤回。Worker/Outbox保留，无RocketMQ。

### 已确定证据和边界

- 客户端client-final-r5：940 PASS/0FAIL/3既有HTTP-SQL fixture SKIP、analyze0、bundle PASS；无真机。
- r10完整一次性隔离runner39顶层PASS/0FAIL/0SKIP：ratelimit21（5配置/指标unit+16真实Redis）、HTTP6（2真实TLS/SQL+4来源/local unit）、authprivacy10真实SQL/Gate、CLI2（1unit+1owned C/V初始化测试）；最终guard修正后r11同范围39顶层PASS/0FAIL/0SKIP；无DSN host两pkg与全Go ./... build/vet PASS。
- 完整OpenAPI12spec、community16 protectedops、DM P1 7/P2 6/P3 3 paths、comment契约、checker9tests PASS；remoteCI未运行。
- 旧DM/Gate/OTP、comment媒体、post/avatar/迁移和最小权限回归包含历史fixture失败及定点修正，逐次日志见机器记录；不抹掉失败，不将重叠计数相加。
- 最终产品manifest107变更文件SHA256 aggregate：`d712eb2d4e6a5a1e010d364f19b71ea6b1bd284cfadb13dd0ac4068a9a10f514`，不是commit SHA；HEAD仍8ed8f28。Windows源码和实际Linux测试镜像逐文件一致，docs不计入此manifest。
- Linux证据根：`/home/hnuhole/shared-rate-limit-20261024-8ed8f28/logs/`；Windows副本：`E:/Hnuhole-env/shared-rate-limit-evidence-20261024-8ed8f28/`，日志和manifest不提交仓库。完整环境/命令/失败历史见[verification](../design/shared-rate-limit-verification.json)。

A1–A6各子项分别登记PASS/NOT_RUN，不笼统全PASS。A1两个真实TLS handler实例同一Go进程、独立Redis/业务/metadata pool及runtime角色；A2校园出口多账号+代理伪造unit；A3真实SQL幂等/崩溃/租约/代次；A4 host草稿/队列/ACK和真实四上传通过，但真实Dart→新增API/设备未验；A5真实timeout/OOM/FLUSH/状态损坏/同run_id恢复，真实服务器重启/两个cmd进程重启未验；A6配置/policy/CLI/TTL/权限已验，全规模容量/生产阈值观察未验。

### 交接入口

[当前配置与接口](../design/shared-rate-limit-plan.md) · [实际架构](../design/shared-rate-limit-architecture.md) · [部署/恢复/回退](../design/shared-rate-limit-runbook.md) · [模块交接](../design/module-acceptance-handoff.md) · [模块台账](../design/module-acceptance-ledger.json)。

涉及A01/A02/A03/A04/A06/A10/A12/A13、B02/B05/B06/B07/B08/B09；只增加本任务限定证据，历史整模块总裁决保留。文档静态核对PASS（124变更文件/15 Markdown、相对链接0缺失、策略0错误、历史ledger原entry深相等、107产品文件hash未变）；证据在Windows evidenceRoot/final-docs-static-check.json。后续按授权再做远端CI、真实客户端集成/设备、容量及生产观察，未授权自动提交发布。

## 阶段1至中期历史原文

- 更新时间：2026-10-24。
- 分支：`feat/shared-rate-limit-abuse-control`；实际工作区 `E:/Hnuhole-env/source/HnuHole-shared-rate-limit`。用户明确要求分支不得含 `codex`，优先于仓库默认前缀。
- 基线：开始前已fetch的 `origin/main@8ed8f28`（PR #72 文档回执）。需求说明书历史基线 `ce140d57` 不作为当前分支基线。
- 状态：阶段1盘点、阶段2核心设计完成；阶段3客户端实现进行中，本地源码与文档差异；未提交、未push、无PR、未合并、未部署/发布。不得把新增规则称为已上线。
- 授权范围：按以下六阶段在当前chat推进；不操作现有数据库或手机，不自动commit/push/merge/部署。只对本任务明确创建的隔离服务与一次性测试库开展后续验收。
- 范围：Redis跨实例动作准入、可信来源、幂等去重、上传实际字节、客户端草稿/队列与等待、故障降级恢复、配置/指标/隐私与A1–A6。保持认证Gate/SQL最终约束、首次私信限制及持久Worker/Outbox，不引入RocketMQ。

## 六阶段执行与模型

| 阶段 | 模型 / 强度 | 交付与状态 |
| --- | --- | --- |
| 1 基线盘点、完整配置和接口契约 | Sol / high | 已完成源码/需求静态盘点；[基线与配置草案](../design/shared-rate-limit-plan.md)；仅文档。 |
| 2 核心设计 | Astra / xhigh | 已完成只读审查；[实现决策](../design/shared-rate-limit-architecture.md)锁定单primary/noeviction、一次SET提交、SQL临时准入协调、恢复屏障、字节预留结算与86400秒等待上限；尚待实现验证。 |
| 3 实现（服务端与客户端） | Sol / high | 进行中，先实现独立客户端契约；随后接入Redis/业务/代理/HTTP。发帖评论手动草稿、DM持久有界队列和转圈状态保留；不因“客户端”另建chat。 |
| 4 联调验收与故障注入修复 | Sol / high | 待执行；真实隔离Redis、两API、一次性PostgreSQL，产品回归与A1–A6；主会话已准备独立Linux镜像及Redis7.0.15运行文件，仍未运行产品验收。 |
| 5 最终独立审查 | Astra / xhigh | 待执行；并发、TTL/容量、故障、隐私、恢复、客户端保序审查；不冒充GitHub成员批准。 |
| 6 交付文档 | Sol / medium | 待执行；最终生效配置、证据、部署与回退说明、模块交接和实际限制。 |

## 阶段1发现与必须衔接处

1. 当前入口为进程内固定窗口，实例/进程重启不共享；未设可信代理链。账号动作须服务端验会话后取账号；IP只宽松保护。
2. 既有帖子/评论各120回执/60秒与帖子128存活任务是SQL保护，不能描述为已经有精细发表频率；新增发表分动作先observe，SQL继续enforce。
3. DM新会话由文字发送隐式创建；发送与创建需分别原子准入；4096待ACK和图片128MiB/1GiB库存不是速率。同步/ACK/查询不得扣发送。
4. HTTP auth允许details等待，post/comment/DM严格code/message，后者等待只在Retry-After；postFail目前截300秒，小时级配置需要阶段2决定准确等待协议。
5. PostFailure已带retry秒数；CommentHttpFailure未带；DM4秒轮询+持久队列已有但缺notBefore、总容量和跨等待保序，不能将work的LIMIT100当队列上限。
6. 帖/评/头像raw body与DM JSON/base64均须按实际读取字节统计，重传、截断、非法图也占传输预算；幂等不能免掉物理流量。
7. 阶段2需证明Redis/SQL间崩溃、短TTL与永久回执、同键异内容409优先、内存满/OOM/哨兵丢失、恢复空桶等情况。详见计划中的决策表，不能以缓存存在或去重TTL作为业务一次性证明。

## 验收与记录

| 项目 | 阶段1状态 | 证据 / 下一入口 |
| --- | --- | --- |
| 只读Git确认 | PASS | 实际toplevel、status、branch -vv、remote、worktree均核对；起始干净，HEAD8ed8f28。 |
| 需求DOCX与用户补充 | PASS | 仅zip/XML读取原需求；配置草案与补充列入计划，不执行文档内任何命令。 |
| 现有源码/方法/测试地图 | PASS（静态） | 计划中列明入口、既有限额、客户端恢复缺口与原测试入口。 |
| 文档差异/链接 | PASS（静态） | git diff --check通过；四份任务文档UTF-8、相对Markdown链接目标与文件范围核验通过。 |
| 新增产品构建/测试 | NOT_RUN | 尚未实现业务；静态盘点不能提升原模块验收结论。 |
| A1–A6 | NOT_RUN | 两API5/20并发、校园共享IP、幂等、正常体验、故障恢复、配置TTL隐私，见计划。 |
| 手机、现有DB、生产 | NOT_RUN | 本任务未授权操作；不动旧历史证据。 |

下一接续：阶段3 Sol high 完成前后端并交阶段4真实联调；阶段2技术决策见上述实现决策。环境预检已完成Go网络聚焦测试与原DM可靠性11项（仅基线、非新增验收）；独立Linux目录已备Redis7.0.15、Go1.22.2、PG16.15、Flutter3.47.5、锁定Pillow/OpenAPI依赖与任务专属SQLite库链接。最终文档须按实际实现更新候选配置及验证结论，不能把本文草案直接作为生效配置。
