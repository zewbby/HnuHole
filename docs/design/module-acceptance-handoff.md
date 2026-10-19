# 分模块验收与测试交接

> **2026-10-19 评论开发已合并交付并结束。** 用户明确授权“完成合并交付，结束评论开发”；[核心 #17](https://github.com/zewbby/HnuHole/pull/17)（`3e0cc02`）→[业务接通 #19](https://github.com/zewbby/HnuHole/pull/19)（`2da7cdf`）已依次 Squash 合入 main。#19 普通整合 #17 实际 main 后，完整文件树与已实测 `d1b83c5` 一致；送合 head `ad0a9c0` 的全部适用 CI 通过，57项产品输入指纹保持一致。详见[合并回执](comments-main-merge-20261019.json)、[接通报告](comments-connected-report-20261019.md)及[独立审查](comments-connected-review-20261019.json)。页面、原生已提交任务持久化、单图、点赞、删除、失败恢复和真实失败通知数据源均已进入主线，迁移链为0001..0017。Android限定验收结论保持；B07全平台/生产仍为PARTIAL，iOS、跨设备Passkey及新增评论实体TalkBack/多机型矩阵留后续独立授权，未发布。当前评论开发任务关闭，下方各阶段记录保留原版本历史。


> **2026-10-18 评论文字后端增量：BACKEND_TEXT_SCOPED_PASS。**[Draft PR #19](https://github.com/zewbby/HnuHole/pull/19) 堆叠于核心 #17；已正常整合 main `1b78f42` 的真实治理0015，正式评论0016及空库/升级/Down拒绝、真实PG/受限角色/TLS HTTP/重试放弃/封口/生命周期针对性检查通过。被测后端 `07911ab`，完整B07仍BLOCKED、通知provider未接入；本轮不推进客户端/图片/原生日志/设备。见[报告](comments-backend-text-report-20261018.md)、[机器记录](comments-backend-text-verification-20261018.json)与[后端任务](../branches/feat-comments-backend-text.md)。独立成员审查与最终head CI待PR核对，未合并/未发布；下方“0015尚未合入”等为原日期历史快照。
> **2026-10-19 已确认合并 main：**[PR #16](https://github.com/zewbby/HnuHole/pull/16) 经本session用户明确授权转正式送审并普通 Squash Merge，提交 `32cb87b73e2feb518e1c5ec75ea11bb4d3414df1`（上海时间10:13:17）。文件树与已测最终head `a6f8f60` 完全一致，八项最新检查全SUCCESS；独立agent审查无阻断，无GitHub成员批准，不伪造批准或绕过规则。候选构建、同机隔离恢复/回滚与vivo S18最小文字/单PNG限定证据已进入主线；未正式发布，P03/P05完整生产结论不升级。手机窗口已结束，不再ADB；跨设备Passkey、iOS及报告列出的未验范围继续保留。见[合并回执](../release/android-prerelease-main-merge-20261019.json)及[任务详情](../branches/ci-android-prerelease.md)。以下待合并/draft/NOT_RUN条目保留为各自版本和时点的历史快照。

> **2026-10-19 手机实测完成：**8691eb4测试包在vivo S18 / Android15 API35通过本轮11项限定检查：正常UI合成注册/恢复码确认、中文身份输入、文字及单PNG发布/读回、大图/Gal原字节保存、跨进程会话保留、退出后密码重登。输入截短导致的一次错误登录及旧个人路由失效观察如实保留；未改认证/业务代码。用户明确授权后才移除旧签名同包及本机数据。自有临时媒体、两条reverse、ADB5049及后端均已收回，窗口已结束，不再ADB。详见[手机报告](../release/android-device-validation-20261019.md)及[机器记录](../release/android-device-validation-20261019.json)。不升级完整原生安全/Passkey/多图/TalkBack/生产结论，iOS及跨设备Passkey继续延期；PR #16仍未合并/发布。

> **2026-10-19 较早准备快照（下列NOT_RUN属于实测前）：**8691eb4独立SDK/签名/pinned-CA debug包构建验签PASS，绑定14f5096的lab-09（schema15）C52045/V37073；用户当前不能测。没有ADB/手机操作，安装和原生/业务链路保持NOT_RUN。准确APK/证书摘要及CA到期见[发布记录](../release/android-prerelease.md)。

> **2026-10-18 预发布主线同步：**核对PR #18已实际合入main `1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`，正式迁移新增0015。下方schema14及PR #18合并前状态保留原版本；本任务14f5096的schema15新环境已通过13项/75摘要/五实例停机，手机包构建验签PASS；受影响CI仍按最终head核对，不沿用旧结果作为新版本PASS。未连接手机。

> **2026-10-18 手机包准备补充：**用户当前仅能先准备vivo S18 / OriginOS 5测试包，不具备设备窗口。专属debug构建沿用原包名和认证逻辑、独立测试签名与pinned CA，移除历史诊断/DAL声明；不运行ADB。安装、原生插件及APK服务链路仍NOT_RUN，现有生产模块结论不变，见[发布记录](../release/android-prerelease.md)。

> **2026-10-18 P03/P05开发交付补充：**[PR #16](https://github.com/zewbby/HnuHole/pull/16) 新增Android候选CI和隔离预发布；本地0d10719完整11项实际演练/60份表与sequence恢复摘要、独立CLI启停和Linux6项工具回归PASS，独立CI后台和测试签名release候选6b2927c PASS，APK/证书摘要已归档；安装和APK实际服务链路NOT_RUN。见[发布记录/命令/机器回执](../release/android-prerelease.md)。这只补同机开发恢复/应用切换证据，不将P03生产灾备或P05完整发布标PASS；正式签名、固定生产端点、手机/iOS及生产主体独立仍未验。所有历史设备证据保留原SHA与范围。

## B11／B08：举报、审核与最小系统通知阶段1（2026-10-18）

任务为 `codex/feat/report-moderation`，[PR #18](https://github.com/zewbby/HnuHole/pull/18)，见[任务详情](../branches/feat-report-moderation.md)与[阶段契约](report-notification-contract.md)。
基于实际 main `986477b` 的产品候选 `aab9a647d9c8310e344bbc767abb5cbdc1045f73` 已提交、推送，无未提交产品源码，agent 安全复核无阻断；状态为 PHASE1_SCOPED_PASS。
帖子举报、电脑网页审核、必要申诉和最小系统通知已交付候选，最终真实SQL／HTTPS／浏览器链及产品候选CI已通过，最终命令、输入和结果由[验收报告](report-moderation-validation-report.md)及[机器记录](report-moderation-verification.json)固定。B11／B08均保持PARTIAL，不将实现或局部结果记为完整验收PASS。

已记录宿主范围为 Flutter439项／analyze0／bundle、9份OpenAPI、Node12项及Go host／build／vet全部PASS。最终aab候选4工作流／7任务通过，聚焦47项零FAIL/SKIP、完整继承321项PASS和两个既有独立Flutter入口SKIP；交付文档head另核对相同产品输入及CI。

| 范围 | 当前实现与必须复核的场景 | 源码／测试入口与当前验证状态 |
| --- | --- | --- |
| 原举报与合案 | 6类、200字／6图；未知先查原键，同键材料冲突；相同 post＋snapshot 跨原因归并，各份原因保留；重复提交／多审核员不重复处罚 | `authprivacy/community_reports.go`、`community_reports_test.go`、`authprivacyhttp/moderation_postgres_test.go`；最终真实SQL回归PASS |
| 管理与隐私 | 同源 HTTPS `/admin`，真实既有登录；审核员／管理员、原处理人回避、版本竞争、最后管理员保护、只允许六位编号最小 DTO；无邮箱／内部映射／其他面具／举报人 | [工作台](../../apps/admin/README.md)、`authprivacy/community_moderation*.go`；Node12项PASS，agent安全复核aab无阻断；`live-api-smoke.mjs`实际Go网页链PASS |
| 处罚与生命周期 | 下架／资料重置／独立禁言与封禁；有效限制取最大截止；作者删除终结未完成案件，既有处罚保留；撤销只解除对应处罚，误判恢复不复活作者删除或其他有效下架 | `community_moderation_restrictions.go`、`community_posts_lifecycle.go`、`community_reports_test.go`；权限／冻结／并发／恢复真实 SQL 回归 PASS_SCOPED |
| 申诉与材料 | 每项处罚三轮、同时一轮待复核；首次500字／6图，追加每次500字／3图且不加次数；到期继续复核；详情首份／首批，后续一组一页升序追加并保留旧组，明确未加载状态 | `community_moderation_appeals.go`、`community_moderation_materials.go`；[审核契约](../../packages/openapi/moderation-api.yaml)、[移动测试](../../apps/mobile/test/governance_test.dart)；最终SQL／客户端回归PASS |
| 通知与受限入口 | 账号通知与当前身份单一时间流；列表不标已读、详情单条已读；路由复核本人归属；受限访问仅本人处罚／申诉，不恢复社区会话；待核对材料按账号隔离 | [移动实现](../../apps/mobile/lib/src/system_notifications/governance_controller.dart)、[HTTP测试](../../apps/mobile/test/governance_http_test.dart)、[本地材料测试](../../apps/mobile/test/governance_material_store_test.dart)；真实Dart→C HTTPS→SQL及实际Go网页浏览器链PASS |
| 迁移与发布边界 | main `986477b` 迁移至0014，0015不依赖评论表；最小权限与通用C启动生命周期核验、旧／新处罚独立账目；不覆盖既有迁移，迁移升级与拒绝静默回滚需真实库验证 | `0015_reports_moderation.sql`、`grant-moderation.sql`、`moderation_upgrade_test.go`；从 `services/api` 运行 `sh authlab/run-moderation-isolated.sh`；最终真实SQL／race PASS，精确计数与SKIP范围见固定报告 |

管理授权初验、逐份举报类别、旧配置生命周期启动检查和旧处罚兼容问题均已修复；aab的agent安全复核无阻断，不冒充GitHub独立成员批准。宿主检查与最终真实SQL／CI证据分开记录；无DSN的SKIP不代证SQL PASS。
上述报告已固定最终SQL／Dart HTTPS／实际Go网页与产品CI结果；交付文档head回执在PR核对产品指纹、实时main及CI。阶段1限定范围PASS，后续按评论合入依赖接阶段2。
本轮重新打开 A01／A03／A06／A08／A10／A12、B02／B05／B06及跨模块生命周期／账号隔离回归，不覆盖其既往证据。

阶段2待评论任务合入后接评论举报和真实 `CommentFailureProvider`：评论核心、图片、失败保存／重试／放弃归评论任务，通知层只投影明确失败，不处理未知结果或复制发送状态机。
完整互动收件箱、私信／聊天证据和系统推送未实现；跨设备 Passkey NI-X02、iOS、当前候选原生设备与生产独立证据仍未验／延期。未合并、未发布，不据此关闭 B08／B11 其余业务。
下方旧任务记录保留各自日期与范围。

> **2026-10-18 通知依赖核对增量：**已读取治理已提交契约 `60e5df4`，评论原身份／任务／状态／动作与 `IDENTITY`、`LOCAL_TASK`、`COMMENT_FAILURE/taskId` 路由映射已记录在[评论接线契约](comments-replies-contract.md)。完整事件包装／时间／已读／去重、未受理失败入口及实际 provider 尚未实现；0015 未合入，B07 和 COMMENT-FAIL-ENTRY-01 继续未通过。未合入整条治理分支。

> **2026-10-18 评论与回复首阶段：独立核心宿主范围 PASS，完整 B07 未完成。**[Draft PR #17](https://github.com/zewbby/HnuHole/pull/17)，分支 `codex/feat/comments-replies`，被测实现 `cd45a89`；已正常整合 main `986477b`（含 PR #13），保留图片、认证和无障碍成果。Go 不可变任务／固定身份目标／排序、Dart 临时输入／未知与权威未受理／恢复接口、专属 codec 的12黄金向量及严格契约已实现；Flutter445／分析0／bundle、Go评论50含子项／91%覆盖／全服务宿主build+vet、7份OpenAPI与Python207（3平台跳过）通过。尚无评论 SQL/HTTP/worker/真实加密journal/页面/单图上传读取/通知接线，未生成评论功能APK、未操作手机；内存适配器不代证重开持久化。治理0015尚未进main，评论暂定0016，不造前置或跳号；`COMMENT-FAIL-ENTRY-01`为NOT_RUN_NOT_CONNECTED，B07保持BLOCKED。见[阶段报告](comments-core-report-20261018.md)、[机器证据](comments-core-verification-20261018.json)、[接线契约](comments-replies-contract.md)及[任务边界](../branches/feat-comments-replies.md)。未合并／未发布；NI-X02与iOS继续延期。下方历史快照保留原范围。

> **2026-10-18 已确认合并 main：**[PR #13](https://github.com/zewbby/HnuHole/pull/13) 按维护者本次指令普通 Squash Merge，合并提交 `359c180a53a674e308e1496bed31da33b9ab8524`。远端main已核对；完整文件树与已测 `06a7ada` 一致，宿主/真实SQL/构建及三项产品CI通过证据继续适用。旧分支/历史协作policy失败与无独立成员批准如实保留，未改保护规则、使用绕过选项或强推。跨设备Passkey NI-X02继续延期；旧设备结果仅限原APK，新整合候选原生设备仍NOT_RUN，iOS/生产/完整App未验。见[合并回执](community-pr13-main-merge-20261018.json)。下方待合并/draft等条目保留为合并前快照。

> **2026-10-18 PR #13 主线冲突整合：宿主/真实SQL/构建范围PASS。**社区 `2abda59` 正常整合main `8fa9cbc`，保留图片/B5闭号擦除与社区无障碍修复。76冲突收口；全mobile395/分析0、R05/F4、server/权限/runtime/vet、图片SQL和组件、Android构建均有本轮证据。原生插件/SQL/锁与main一致；未操作手机，旧设备证据仍限原APK，NI-X02跨设备Passkey继续延期。旧分支名/79条继承提交与main新协作policy不兼容，未改policy或强推，PR保持draft待审查。见[整合报告](community-pr13-main-integration-20261018.md)/[机器记录](community-pr13-main-integration-20261018.json)。以下记录按原时点与范围保留。

> **2026-10-18 OEM 双实体实测收口：NI-X01 限定路径 PASS。**官方搬家 vivo→真我，只传唯一 HnuHole Stage4/100 MB/成功1项失败0项；源已登录、目标访客对照后，目标重开仍访客，源登录及 Stage4Local 保持，两侧 no_backup 文件哈希与服务端会话/计数不变。仅选应用、未选应用数据，不外推到强制私有数据导入或所有OEM。7项本轮限定检查PASS，源码/其他分支未改；自有连接已收尾，设置未改，最后有效会话在vivo。恢复码双实体8项历史限定PASS保留；Android原四任务仅NI-X02跨设备Passkey仍按用户要求延期，iOS/生产仍独立。见[OEM报告](community-android-oem-transfer-20261018.md)/[机器记录](community-android-oem-transfer-20261018.json)。以下旧日期/同日较早状态按当时范围保留。

> **2026-10-18 恢复码双实体范围完成：8项限定PASS。**vivo→真我实际恢复码重设/隐藏后完整确认/无自动登录、旧密码与旧码401、同一活跃旧会话撤销、双向单移动会话接替、两机原生重开及源草稿标记隔离均有本轮UI/HTTPS/SQL证据。真我仅恢复当前用户的原签名隔离包；有效会话最后留在真我。产品代码/依赖/协议/其他分支未改，主机旧记录不计本轮；只更新脱敏交接。Passkey NI-X02按用户要求单独延期，真我当前ROM缺凭据feature/service且官方OTA无新版；NI-X01 OEM仍NOT_RUN，直接安装不代证搬家，iOS/生产仍独立。见[本轮报告](community-android-recovery-code-dual-device-20261018.md)/[机器记录](community-android-recovery-code-dual-device-20261018.json)。旧日期记录按原范围保留。

> **2026-10-16 第三项三处缺口已收口：PASS_APPROVED_SINGLE_ANDROID_SCOPE。**坏签名与未关联包均拿到当前Google26.39.33的明确50152/终态错误/匹配校验栈且无网络错误，未拿泛化取消代证；真实工具标识后Windows/Linux严格直接HTTPS及精确原文件PASS，无网站安全降级；用户主动关闭的native取消及无C提交PASS；同一活跃旧token在真实重设提交前有效、提交后被拒绝，HTTPS与Passkey服务端SQL均补证。最终七阶段全PASS、mobile334/分析0，Windows159＋3POSIX SKIP／Linux162。见[补验报告](community-android-stage3-closure-20261016.md)/[机器记录](community-android-stage3-closure-20261016.json)。手机约18分钟后结束，vivo设置逐字恢复，正常App及三包摘要不变，无安装/卸载/清数据；不再调用ADB。任务1/2/3限定PASS、第四项双实体及iOS/生产未验，完整模块/App不升级PASS；昨天PARTIAL及失败证据保留原范围。

> **2026-10-15 第三项实测：PARTIAL。**独立RP获准发布；真实vivo系统Passkey创建、可发现恢复、绑定丢响应后跨进程原键核对、新凭据完整确认/无自动登录及重开恢复PASS。最终七阶段全部PASS（mobile334/分析0、R05、F4八项、server、受限权限、实际runtime25断言、vet），被测产品9dda242、205输入指纹5bc83b4d…677631；没有改产品/SQL/锁。Google两项正向关联现均linked=true，但严格默认HTTPS仍403/1010；坏签名超时、未关联包取消均无明确关联拒绝，第一次恢复超时保留。因此CA-A13和第三项不记整体PASS。见[实测报告](community-android-stage3-device-validation-20261015.md)/[机器记录](community-android-stage3-device-validation-20261015.json)/[已应用公开关联](community-android-stage3-applied-20261015/proposal.json)。手机窗口已结束，三个新包与未决材料保留，无后续ADB；任务1/2限定通过保留，任务4双实体、iOS、生产及完整App仍待验。下方旧日期准备/未授权/NOT_RUN记录均为原版本历史。

> **2026-10-15 普通网络读屏遗漏已补齐：**实际断开一次列表GET后发现错误不自动朗读，已修复；同包同证书复验中用户确认自动提醒、重新加载恢复、无需重登和原草稿保持均正常。最终mobile334／分析0／R05／F4八项PASS，覆盖最终205输入；TalkBack已代关、转发与业务计数核对恢复。见[补验报告](community-android-talkback-network-retry-20261015.md)/[记录](community-android-talkback-network-retry-20261015.json)。原333项及“列表重试朗读未验”保留为前一版本历史；第三项Passkey、第四项双设备、iOS和生产仍待验，不升级完整模块/App为PASS。

> **2026-10-15 TalkBack补充：PASS_APPROVED_TALKBACK_SCOPE。**通道重复、我的/返回英文、身份选中语义、必填提示自动朗读和中文数字语义语言已修复并由本轮单机限定清单复验；最终mobile333、导航语义4、分析0、R05和F4八项PASS，205输入指纹见[实测报告](community-android-talkback-validation-20261015.md)/[机器记录](community-android-talkback-validation-20261015.json)。一次GET503触发现有登录恢复保护，未误计普通列表重载朗读；原转发恢复、SQL写计数不变，按用户明确请求关闭TalkBack并核对。任务3系统Passkey、任务4双实体、iOS和生产仍独立未验；以下历史“TalkBack关闭未验”保留原版本范围。

> **2026-10-15 当前任务2单机范围通过：**原生35项＋3组进程中断、实际SQLite跨进程/用户整机重启/本地闭号清理PASS；正常App合成A重新正常登录后强停/重启的草稿、身份通道与会话由用户确认。先前旧会话因获准Gate恢复推进代次被拒绝，保留负向观察，不冒充恢复PASS。Windows155＋3 POSIX SKIP／Linux158。见[实测报告](community-android-stage2-device-validation-20261015.md)及[机器记录](community-android-stage2-device-validation-20261015.json)。产品/native/manifest/SQL/锁未改；默认USB隔离守卫保留，仅本轮显式批准既有身份。TalkBack关闭未验；任务3系统Passkey、任务4双实体、iOS和生产仍待验，模块/App不升级整体PASS。以下历史条目保留原日期范围。

> **2026-10-15 当前任务1实测完成：八自动点PASS＋人工IME USER_CONFIRMED。**真实vivo S18/Android15，中文/换行/emoji与草稿重开由用户对明确清单综合答“一切正确”；原自动PARTIAL记录未改，汇总另存。最终mobile327、分析0，Python Windows144＋3 POSIX SKIP／Linux147；历史失败及修复全过程保留。见[实测报告](community-android-device-validation-20261015.md)与[机器记录](community-android-device-validation-20261015.json)。normal/A会话、当前server/reverse/fixture与专用材料保留。任务2–4、iOS和生产仍独立未验；并行stage3准备保留原范围。

> **2026-10-17 B5 主线增量已合并：**[PR #9](https://github.com/zewbby/HnuHole/pull/9) 已通过 Squash Merge 进入 main，合并提交 `eff7461`。闭号状态与图片擦除修复、B5 材料和夹具适配已交付；受影响宿主测试、真实 SQL/C/V、Android 构建、独立审查及最终 head GitHub 检查通过。见[整合报告](auth-privacy-b5-main-integration-report.md)、[机器记录](auth-privacy-b5-main-integration-verification.json)和[分支记录](../branches/fix-b5-main-integration.md)。历史24/24仅证明原认证版本；当前 APK 原生设备验收仍 NOT_RUN，iOS、完整产品及生产批准不在本轮范围。未部署或发布。

> **历史认证证据独立保留：**B5 来源为 `ea5cc52840f009b02106f928c444e423c6e61b3e`，产品基线仍是 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。历史 B6 为 **22 PASS／0 FAIL／2 BLOCKED**；B5 双实体首轮为 **23 PASS／1 FAIL**（NI-X02），随后 Bitwarden 原生路线仍 **BLOCKED**；B5-sync 后续为 **24／24 PASS**。原四次 hybrid 失败、同步成功后夹具失败、用户报告未出现选择／验证页的第六次失败及后续重试均保留在原[首轮报告](auth-privacy-b5-validation-report.md)、[同步报告](auth-privacy-b5-sync-validation-report.md)和三份机器证据中。历史 `nonIOSDevelopmentAcceptancePassed=true` 仅属于原 B5-sync 输入及设备链，不是本候选通过；iOS、生产及未来业务边界不扩张。

> **候选证据规则：**两个 B5 checker 仍在固定 `ea5cc528` 历史副本验证，完整 B6 checker 在固定 `d859cb05` 副本验证；不改历史摘要或降低门槛。候选须记录全部历史 runtime 输入的差异及集合以外新增 runtime 文件，另记三份 B5 夹具由 `_HnuholeApp` 适配 `HnuholeApp` 后的摘要及运行时根组件发现回归。旧 APK／旧夹具结果不代证新候选；当前原生设备回归为 **NOT_RUN**，Dart mock、分析和构建不能替代原生存储与设备验收。

本轮重新打开 A07／A12／N01／N03 及受账号生命周期影响的 A08／B02／B05／B06／B10 回归：恢复与错误处理、注销／封禁／删身份后停止发布、切账号、仅清 originalAccountId、认证与业务 namespace／alias 隔离。主线模块结论保留；B5 历史字段放入机器台账 historicalAuthB5Integration，候选验证独立放入 candidateIntegration，均不提升整个模块验收状态。

> **2026-10-16 已合并 main：**PM01/IV01 帖子图片任务经 [PR #2](https://github.com/zewbby/HnuHole/pull/2) 合并，主线提交 `4fc19baf8655da4b012a0a6dd2c8c9a7b2bab398`，送审提交 `2f46700`，来源 `codex/post-image-integration`（f30e8ae）。本任务的独立组件、帖子选图上传、真实前后端联调和 S18 Android 约定范围已交付；本任务功能范围剩余 iOS（原始选图未实现、入口关闭，macOS/Xcode/iPhone 原生与设备验收待完成）。GitHub Flutter 分析0/组件112项/受影响mobile130项/bundle、Go test/build/vet、协作检查均实际PASS；仅宿主CI，不扩充原SQL/手机证据范围。独立agent复审无阻断，不伪造GitHub成员批准。未发布或部署，详情见[合并回执](post-image-main-delivery-20261016.json)。下方旧日期记录保留原时点状态。

## PM01 / IV01 / B05 / B06 / B10：本轮主App Android约定范围

2026-10-15，`codex/post-image-integration`，起点c1b26ea，修复实现fd2e4c04f48b29ddda0142660188988c4a655f5f。单台vivo S18/Android15/API35，独立真实主App包20263115→20263116及probe20263115；用户已释放窗口并实际完成中文输入、Picker和长图手势。原图存储、九图公开/补传、失败同任务RETRY、读取/原格式保存/真实Gallery回放、删除/退出/切账号与迟到隔离的本轮结果见[报告](post-image-android-device-report.md)及[机器记录](post-image-android-device-verification.json)。当前为PASS_SCOPED_ANDROID_BUSINESS_DEVICE，PMA01–14逐项有范围；不更新整模块为全通过。

实际修复：PostController的旧错误提示绑定command，权威核对并持久保存后清除；仍未知及后来其他操作错误保留。新增3项回归，最后修改后相关3文件69项、分析0、bundle、Debug原生构建/验签和修复包上机复验PASS，准备守卫15项PASS。旧完整mobile375/后端244等保留原SHA和宿主范围，本轮未重复计数。认证插件/Go/SQL/锁/图片引擎未修改，X05仅当前帖子图片链路，不升级认证和其他社区模块证据。

手机窗口已结束；字体/方向/无障碍恢复，自己的测试包与C/V/watch/PG停止，仅撤销自建映射。Linux专用库/私钥已删除；Windows清理两次被自动审批拒绝（blocked by policy），SDK/cache、APK及受限目录中的合成秘密仍保留并登记，未冒称清理完成。手机测试包/合成图按SOP保留；没有删除手机媒体或操作其他会话。

待开发/未验：iOS原始资源选图库仍未实现，需macOS/Xcode/iOS实机后补；最大九图资源、生产SQL存储配额/WAL/备份、正式库存升级和部署仍独立；评论/私信图片消费者未开发。原生写入已派发后的关闭、临时文件故意消失，以及旧组件TalkBack/大字沿用未改组件旧范围，不写成本轮主App重测；本轮没有重验vivo9.4.6.13已知播放器缺陷。下一任务不能复用已结束手机窗口、已清理Linux库或旧空库恢复命令。


> **2026-10-15 主App帖子图片真机验收的非手机准备已完成：**实现 `2eeb19ce87542aed9e0c57874e8d6b3478df946d`，本任务独立kit `E:/Hnuhole-post-media-android-20261015`。新主App/probe两个API29+包构建与验签、分析0、原图宿主10项、离线守卫15项/设备命令守卫4项、专用真实C/V/Goose/受限空PG重启及Windows HTTPS均PASS；自己的后端已停。没有调用ADB或操作手机，PMA01–14全部NOT_RUN，等待另一会话释放；旧组件TalkBack不重测。按用户要求暂留独立APK/签名/空库/工具供直接配合，过期先核就绪清单。见[准备报告](post-image-android-preparation-report.md)、[机器记录](post-image-android-preparation-verification.json)、[集中SOP](../../tools/post-media-android/README.md)。下方旧结果保留原源码和范围。

> **2026-10-15 帖子图片真实前后端联调完成：**联合分支 `codex/post-image-integration`，源码 `31e82df6ad0f8345471705cf78e6e0f463beecfb`（前端075b567＋后端d893378）。真实C/V进程、Goose/受限PG、Flutter生产页面/API/原图草稿/补传/读取/保存resolver，19检查点全部PASS；修复旧上传暂停状态污染新RETRY。当前分析0、完整宿主375（零排除）、后端SQL/race244、Python4/OpenAPI6、编译/vet、Windows bundle与Android原生构建/验签PASS。没有手机或其他会话服务操作；原生业务真机、iOS原始选图、总预算/生产与评论私信另列。见[联合报告](post-image-joint-report.md)和[机器记录](post-image-joint-verification.json)。下方各分支旧记录保留原版本与范围。

> **2026-10-15 帖子选图上传前端已补齐：**实现 `5cd5fdb8f3766bb5ae5840fa7546eda6739fd98c`，最多9图/排序/移除、加密原图草稿、媒体摘要、逐项补传和重启核对已接现有写帖页。最终分析0、完整mobile374项（零排除，含修复后的控制器43项）、bundle及Android API29+原生构建/验签PASS。后端仍固定d893378独立分支，真实C/V/SQL联调和业务手机未验；本轮未操作手机/服务。iOS选图库会重编码原图，原格式选图尚未实现、入口保持关闭，不能只写待验；评论私信/总资源预算另列。见[本轮报告](post-image-composer-report.md)和[机器记录](post-image-composer-verification.json)。下方旧结果保留原版本，不代证当前。

> **2026-10-15 真实帖子图片读取已接线：**前端固定源码 `b5ab3969870daa43b9d40919311d68f1d4cdca61` 对接后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587` 契约；main/通道/我的→详情已装配受保护读取、最长60秒租约、逐个内存缓存释放与原格式保存resolver。分析0、聚焦76项、其余315项及bundle PASS；完整Windows控制器文件43项保留已复现SQLite清理故障，未计PASS。两个源分支未合并/部署，本轮没有手机或服务操作；完整C进程/SQL联调、业务原生构建/真机未验，上传UI/原图草稿/补传恢复与评论私信未开发，iOS独立。见[读取接线报告](image-viewer-post-media-read-report.md)和[机器记录](image-viewer-post-media-read-verification.json)。下方旧钩子/组件记录按原版本与范围保留。

> **2026-10-15 图片前端接入阶段1：**独立 `codex/image-viewer-business-integration`，从已提交社区e0c1280接入原图片包bd7458a；现有通道/我的→帖子详情已接图片loader钩子、等尺寸预览和独立查看路由，撤销/删除/迟到与返回位置有宿主证据。生产尚无真实图片接口，评论/私信未开发，MIV14仅部分实现。新会话负责帖子图片业务，不编辑社区验收目录/服务/手机；见[阶段1报告](image-viewer-business-stage1-report.md)、[机器记录](image-viewer-business-stage1-verification.json)和[新会话prompt](image-viewer-media-next-session.md)。分析、聚焦34项、其余290项回归、bundle通过；完整Windows回归的SQLite清理errno32已在未改动基线复现，未冒称全套通过。下方历史各按原版本与范围理解。
> **2026-10-15 帖子图片后端独立交付：**分支 `codex/post-image-media`，从已提交社区 `e0c128033682923d519ea99546d72503b085a99e` 在独立 clone 实现真实 SQL 原字节存储、最多九张不可变清单、单项短期补传能力、完整验证后原子公开、受保护清单/原图读取与撤销/清理。Go 72个顶层／含子项244 PASS、Python合成图4 PASS、OpenAPI6份、全包编译/vet PASS；宿主替身与真实TLS/SQL/文件系统范围分列，不代表实际cmd/Goose升级/Flutter/设备/iOS/生产通过。只读参考前端 `a696742f943c1cfe6a5005024dccaf40be752d8f`，未修改或合并其工作区；接线前须处理 imageCount/空正文、新媒体摘要、60秒终止租约。PM01/B05/B06仍为后端已实现／宿主与平台待实现或验收，评论/私信只登记未来契约。见[契约与方案](post-image-media-contract.md)、[脱敏证据](post-image-media-verification-20261015.json)；源码固定提交 efccade441bfc5d453751a3fac74211b090e8129 已正常推送并核对远端；见[交付回执](post-image-media-delivery-20261015.json)，不部署、不发布。下方社区与认证证据保留原版本与范围。

> **2026-10-15 手机窗口当前阻断：BLOCKED_KEY_ISOLATION。**用户已确认 vivo S18、30–45分钟窗口、认证会话释放、隔离包和专用USB key；原stage1实际等待90秒后exit1，未发现目标设备，未安装/启动App、注册或业务写入。Windows环境变量不能证明专用key隔离，已给stage1/2添加不可凭授权flag绕过的前置守卫；CA-A01–13全部NOT_RUN，stage2也阻断。Windows136 PASS＋3 POSIX SKIP、Linux139 PASS仅为host；自有60761 server已按exe/start/port核实后停止，既存5037未动；用户已结束本轮窗口，后续须重新确认。见[本轮报告](community-android-device-blocked-20261015.md)与[脱敏记录](community-android-device-blocked-20261015.json)。历史准备/指纹/APK证据保留原范围；先证明真正独立profile或验证专用key目录的ADB，再由原服务归属方安全释放USB并重验摘要/ready/空库。新增OS账户/安全配置或共享key例外须用户明确变更授权。

> **2026-10-15 CA-T02非手机准备完成：**涉及N01/A12/A08，task1全部450输入与制品/待验空库未变。新增实际vault/PostStore跨进程探针、原生business7/vault16/codec9+errors3与3组认证中断的runner、3隔离新包和手机SOP；mobile322、分析0、Linux136／Windows133＋3POSIX跳过、199项镜像/签名/manifest/DEX/SQLite核对通过。证据见[报告](community-android-stage2-preparation-20261015.md)、[记录](community-android-stage2-preparation-20261015.json)。主机新检查覆盖最终测试/工具，原生35项/实际进程/重启/实际账号/IME/读屏均NOT_RUN，用户未提供手机窗口；原生本地合成清理不代证权威服务端CLOSED。模块/完整App未升级PASS，后续按[四阶段任务单](community-android-unified-acceptance-plan-20261014.md)及[手机SOP](../../tools/community-android-stage2/README.md)继续。

> **2026-10-15 第一项非手机准备完成：**修复 DELETE 首次核对失败后遗漏 poll 集合，以及 C 确认取消注销后的 UI 完成入口。最后产品修改后 mobile322/R05/F4 通过，真实 server/权限/runtime/vet 通过；新增整段 host 八检查点和最终隔离 Debug/标准未签名 Release 构建通过，实际设备与 IME 仍 NOT_RUN。见[准备报告](community-android-stage1-preparation-20261015.md)和[机器记录](community-android-stage1-preparation-20261015.json)。按用户要求保留专用环境、手机新空库和 APK；未调用 ADB 或创建真实账号/USB key。后续确认设备窗口、隔离包/USB 授权并补真实输入法，任务2–4、iOS和生产分别待验。

> **2026-10-14 当前统一任务单：**用户将双实体Android验证追加到原三项工作之后，顺序为①单机文字社区流程②原生存储与生命周期③系统Passkey及单机回归④双设备NI-X01/NI-X02。见[四阶段统一任务单](community-android-unified-acceptance-plan-20261014.md)。当前只更新计划/交接，没有新增测试或设备操作；单机窗口仍延期，第二设备与两机窗口尚未确认，RP/package/signature关联须另行准备审批。20261013主机/构建证据和其“排除第二设备”保留为原范围历史；新任务整体须四阶段全部收口才通过，iOS/生产和未实现业务仍独立。

> **Git与清理回执：**整合后源码提交`28cee4656edd710d60676a81794c20cd49f45351`（父提交为上述社区保存SHA和固定认证SHA）已正常推送且远端核对一致。此后交接回执仅改文档/台账，443项运行输入未变。三处canonical任务根经owner与进程核对后清理PASS，约11.07GiB逻辑文件、SDK副本/缓存/APK/合成CA及调试私钥均删除，源码、测试、脱敏记录与外部复验脚本保留；不做VHD压缩或全局清理。见[交付回执](community-auth-integration-delivery-20261013.json)。设备仍按用户指令延期，后续须重建独立材料并获得窗口，不能把已删除APK/签名当作可直接安装的制品。

> **2026-10-13 当前联合结果：主机回归及Android构建PASS，设备验收由用户明确延期，任务为部分完成。**整合前20份任务文件已保存并正常推送为`7452dadefb52e7b695cdd1079d21083fcb6cae02`；以用户指定的已提交认证`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`三方整合，保留既定文字页、关闭清理、业务vault、SQL0013/最小授权及锁。联合源码新执行checks（分析0／mobile320）、R05、F4主机8项、server六包race、posts权限9顶层/4生命周期、实际cmd/正式迁移R03的25断言及最终vet均PASS；原生标准Debug/Release ARM64、两测试APK和隔离设备候选构建PASS，实际设备用例全部NOT_RUN。最后4项runner/宿主夹具修改未改变App/Go产品/SQL/协议，受影响检查已重跑；最终443项输入指纹`599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7`。旧311及认证22/0/2不计联合结果。见[联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)、[固定SHA差异](community-flutter-f4-auth-integration-diff-20261012.md)、[单台Android复验清单](community-single-android-acceptance-20261013.md)。仅正常提交/推送本分支；第二实体Android、iOS、完整模块及生产未验，未用ADB/手机。以下旧日期记录保留原范围，不代表当前交付状态。

> **2026-10-12 F4 当前固定基线主机范围：PASS，等待最终认证整合。** 用户批准最小 `c_posts` 授权修复后，最终六stage全部重新执行：mobile 分析0问题／20文件311项 PASS、R05 PASS、F4-H01–H08 8项 PASS、Go/SQL/race 6测试包及内置／最终 vet PASS、`posts-privileges` 9个顶层／4个生命周期子用例 PASS，其中真实非 owner C runtime 权限检查 PASS。全部覆盖最后授权修改后的282份未提交运行源码，摘要 `186915148fa007eaa5fd2692744adf1af05f500df02b54388270f922d68e7d46`。详见[本轮报告](community-flutter-f4-validation-report-20261012.md)、[机器记录](community-flutter-f4-validation-20261012.json)、[源码指纹](community-flutter-f4-source-fingerprint-20261012.json)及[固定提交认证差异清单](community-flutter-f4-auth-integration-diff-20261012.md)。授权前FAIL已解决并保留历史证据；最终认证整合 SHA 未指定，F4 final／FP14仍 **BLOCKED_DEPENDENCY**。完整模块、实际部署／旧库升级、原生／手机／iOS及生产未验；本轮不记完整App验收通过。旧308／旧8项及当时R05/vet未执行只保留历史范围，不计入本轮。

## 2026-10-12 当前模块证据与剩余边界

本轮独立 clone 为 `E:/HnuHole-community-f4-20261012/repo`；实际起始与最终 HEAD 均为 `4d58116bdde2c1d2d406b965590bc1625a5c7955`，20份任务文件全部未提交，未推送、合并或部署。运行源码包含既有设置“账号与安全”入口、等价修复的 F4 fixture 两处 lint、runner 隔离修正及5项必要回归；未重新设计 F1–F3 页面、未修改认证协议或新增业务。用户明确批准 `infra/postgres/grant-community.sql` 的最小29行 `c_posts` 授权块，来源为固定后端 `514a944560988e3d8d599e6f9fe9d5d99fe07f88`，原认证授权前缀未变。最终批次为 `2026-10-12T10:33:27Z–10:41:13Z`（上海18:33:27–18:41:13），六stage均在最后代码修改后重跑；每项源码摘要与镜像核对见机器记录。以后修改运行源码须更新指纹并重跑受影响检查。

本轮 runner 在专用 SDK、HOME/缓存、日志、端口和新一次性数据库中执行 `checks`、`auth-regression`、`integration`、`server`、`posts-privileges`、`vet`。完整实际 wrapper 命令和退出码在报告／机器记录，脱敏日志位于 `E:/HnuHole-community-f4-20261012/logs`。没有连接认证数据库、操作设备/ADB或使用认证账号/签名/CA。311项与8项均为最终批次新执行的共享证据，不是每模块重复执行，也未借用旧记录；server 的 mobile opt-in／受限 posts runtime SKIP 分别由 R05/integration 和 `posts-privileges` 独立执行，最终全部PASS。真实 `TestPostSchemaRestrictedRuntimePrivilegesPostgres` 为PASS（0.78秒）；PostSchema9个顶层／4个生命周期子用例均PASS、FAIL0。

授权前 `posts-privileges` 曾因缺 `c_posts` 授权退出1（`community_posts_schema_test.go:234`），历史PARTIAL机器JSON、源码指纹 `4cee5bd2ce8aa660ebc57e04a625b8f74560750137bd69dc87cbbc174c676a6c` 及FAIL日志固定在 `E:/HnuHole-community-f4-20261012/logs/pre-approved-grant-rerun/`。台账保留该失败与修复来源／用户批准；当前 `logs/posts-privileges.log` 属最终PASS批次，不作为旧FAIL证据。此处权限通过证明新库真实受限runtime及business/recovery负权限，不外推为完整实际cmd、Goose旧库升级或生产批准。

| 模块／联动 | 本轮实际证明与源码／测试入口 | 当前未完成及下一验收 |
|---|---|---|
| A00 | 全 mobile analyze0／311；Go6测试包 SQL/race、内置及最终 vet；runner16条合成 guard（含非canonical根拒绝前无写入）。`apps/mobile/test`、F4两份 fixture、`tools/tests/test-community-f4-runner-isolation.sh` | guard使用 stub，只证明隔离调度；最终认证及平台未收口，A00完整模块维持 BLOCKED |
| A01／A02 | fresh PG迁移／schema／TLS handler与生产根接入；实际非owner C runtime正向及business/recovery负权限PASS，PostSchema9顶层／4生命周期子用例PASS。`services/api/internal/authprivacy/community_posts_schema_test.go`、`internal/authprivacyhttp/f4_main_mobile_postgres_test.go`、批准后的 `infra/postgres/grant-community.sql` | 最小复验入口为同独立环境运行 `tools/run-community-flutter-f4-linux.sh posts-privileges`；本次全部六stage已在最后授权修改后重跑。实际部署cmd全角色、Goose旧库前向升级及生产证据仍NOT_RUN，不由fresh schema/handler fixture代证 |
| A03／A06／A07／A12 | R05真实Dart→TLS C/V handler→PG；F4-H01/03/04/06/07，冻结、代次恢复、旧会话接替和A→B；controller迟到feed/CREATE/DELETE围栏。`auth_public_https_postgres_test.dart`、`post_controller_test.dart`、F4两份fixture | 主机vault为替身；F4-H06的retry是会话核对，不代证帖子RETRY。未来认证main/flows/HTTP整合后重新打开相关回归；完整模块维持BLOCKED |
| B05／B02；A12 | 新CREATE409原command/digest核对无第二key（客户端故障注入）；新增已受理RETRY丢响应重开，保持原identity/channel/attempt；真实SQL原回执、明确失败重试绑定。`post_controller_test.dart`、`community_posts_test.go`；F4-H03/04实际CREATE=1 | F4固定当前认证基线；认证候选尚未指定最终SHA，原生持久、完整身份消费者与未实现功能不算通过 |
| B03／B06／B10 | F4-H02/05/07：实际入口、文字列表/详情/本人内容、DELETE丢回包原命令核对，持久DELETED先于清正文返回；controller重开/迟到围栏。`post_controller_test.dart`、`post_screens_test.dart`、F4两份fixture；实际DELETE=1 | scoped证据不提升整模块NOT_RUN；评论/私信/图片/搜索/推送等仍NOT_IMPLEMENTED，布局不重做；native main与生产自动poll未验 |
| A08／N01／B02／B10；X06/X07部分 | F4-H08真实闭号B清本地SQLite、保留A；新增controller清原rows/index及关闭墓碑，保留后来B会话/草稿/视图；新增SQL `TestPostFormalClosureErasesUnpublishedPayloadsAndPreservesOtherAccountPostgres` 走正式申请→终结→清理，擦未公开title/body、原回执去私有关联、另一账号不变、清理幂等；公开内容按规范保留并显示ACCOUNT_CLOSED | controller清理授权状态夹具先持久移除session，真实AuthFlows由F4-H08另证。主机替身不证明原生key/file删除；永久post/task/binding事实不因闭号全删。X06/X07整场景未PASS；Android业务7项/进程/备份及iOS仍NOT_RUN |

认证比较仅限已提交快照：社区 C=`4d58116bdde2c1d2d406b965590bc1625a5c7955`；共同祖先 B=`0eff47a21cd4f4ab1636b4468f7d5df9769a264f`；发布实现候选 A1=`4c40f9015095ebd84dc2b17e30e6ef7ef159321f`；远端交接候选 A=`976c0048aaa40d9b7f589cb735f3bf9c47571486`。A1/A均没有被明确指定为最终社区整合SHA，本轮只读差异，不合并、不复制未提交认证代码。差异清单覆盖main/settings/AuthFlows/session/HTTP/closure/vault/passkey/manifest/SQL与权限；整合须成组保留原命令、原账号关闭清理、原生业务namespace与锁文件。

下一步等待认证会话明确40位整合SHA及其最终证据，固定实际整合源码后重跑所有相关入口。手机／模拟器／ADB本任务未执行；Android复验需同版源码构建、运行 `AndroidBusinessStorageTest` 七项，再验跨engine/进程、重启/备份、实际main/自动poll、IME/TalkBack/大字/系统字体/命中；iOS需macOS完整Xcode及明确Team/Bundle/签名/目标，复验构建、Keychain/安装marker/业务purge、AuthenticationServices/AASA与物理UX。真实部署cmd全权限、Goose旧库升级与生产独立审计仍单列。台账各模块原BLOCKED/NOT_RUN保持；验收口径为 **当前固定基线在主机范围可复验，等待最终认证整合**，F4最终仍BLOCKED_DEPENDENCY。

## 以下为原日期与版本的历史记录

> **2026-10-10 F4换机交接：**源码`68d35af`已完成固定后端接入，生产根路由真实HTTPS／独立PG／文件SQLite的8项主机检查PASS，补设置“账号与安全”入口。见[报告](community-flutter-f4-report.md)、[机器记录](community-flutter-f4-verification.json)和[换机入口](community-flutter-f4-machine-handoff.md)。F4最终认证候选／FP14仍BLOCKED；早期mobile0问题／308PASS不代证最终全量，最终checks／R05／vet因WSL emergency_ro未完成。F5原生／设备／iOS未跑。一次性PG与进程已结束，但本任务Linux缓存删除errno30、清理BLOCKED；不带缓存换机，不动其他会话。旧F3及认证记录保留原版本与范围。

> **2026-10-09 F3 当前交付：**文字页面、主导航、controller与加密SQLite状态已完成，源码`eb6c914`；[实现报告](community-flutter-f3-report.md)、[机器记录](community-flutter-f3-verification.json)和[实际Flutter复审](ui-reviews/community-flutter-f3-ui-review.md)固定当前证据。完整mobile分析0问题、308项PASS（SQLite30／controller34／screens23含14帧）；F1正式图未改。补未来版本拒绝、旧retry随机迁移、删除丢响应／切账号围栏及Android闭号多engine临界区。真实C/V／SQL整合、Android原生7项／构建／跨进程／设备、iOS及物理UX仍NOT_RUN；下一阶段F4固定最终认证候选，F5另行平台验收。scoped PASS不代证整模块或生产通过；下方F2及认证旧结果均为历史版本。

> **2026-10-09 F2契约／存储设计完成：**见[F2设计](community-flutter-f2-design.md)、[版本锁](community-flutter-f2-lock.json)及[静态记录](community-flutter-f2-verification.json)。基于已发布后端514a944固定14操作、命令/任务/客户端未知三层状态、精确摘要与seal/cancel/retry/delete语义；保持Drift/加密SQLite三表v1、独立业务key和环境/账号scope原字节规则。正式F1资产未改；本轮未导入业务代码、未执行Flutter/SQL/设备验收，不把后端未提交T4或历史PASS移入本分支。F3按锁选择复用源码，补未来schema拒写及删除核对回归，F4仍待最终认证候选。

> **2026-10-13 B6与单台Android范围完成：**完整R01 SQL/race/vet、R03实际C/V的19项检查、R05真实Dart→HTTPS→SQL、三个Flutter包分析、移动端188项与Passkey Dart 9项、标准Android Debug／Release构建、原生vault 16项／Passkey codec及错误分类12项、三组实际跨进程读写和已安装Release 13项边界均PASS。Windows／Linux各108项宿主守卫、诊断构建8项、JVM策略24项及四份OpenAPI通过。固定24项维持22 PASS／0 FAIL／2 BLOCKED；原14阶段及各设备版本保留，原SDK-only三项FAIL与历史UNKNOWN未改写。**不需要第二实体Android的非iOS匿名基础工作已完成，唯一固定缺口为NI-X01／X02；完整非iOS、iOS、生产与未来业务仍未获通过。**原手机三包摘要、原provider／autofill、账号与草稿保留；本轮独立模拟器停止，专用AVD／构建副本／临时APK及原始日志已清理，现成环境与缓存保留。HnuHole仅准备本地可审阅候选，未提交／推送／部署。见[B6报告](auth-privacy-b6-validation-report.md)及[最终分层记录](../../services/api/authlab/b6-single-android-20261013-verification.json)。

下方记录保留原日期、被测版本与证明范围；本轮结论以上述B6入口为准。

> **2026-10-13 B3＋B4固定11项已收口：**原8项保持原版本；本次NI-D01／D02／D03均取得实际Google `50152 RP ID cannot be validated`及RP validator栈。D01客户端固定RP无原生启动、错误RP的HTTPS hostname拒绝、正确RP真实创建后C422、原五分钟期限20次结果核对均有独立证据；D02仅改变签名的同载荷包、D03批准证书的未关联包名均明确拒绝且无证明提交／无新增凭据，相关Google校验流程没有网络错误。批准控制真实C204仍有效。**原SDK-only App脚本三项FAIL原样保留**：vivo回调仍是通用取消，关联计数仍0；本次固定项PASS依据为实际App事实＋Google直接拒绝＋独立SQL，未把通用取消冒充关联诊断，未修改原始结果或放宽接受条件。新增只读证据核验6项、安装守卫26项PASS；守卫仅排除已脱离task／display且finished的last-paused旧指针，仍拒绝活动窗口／UNKNOWN。批准签名测试包和原vivo凭据／autofill设置已恢复，原两个APK摘要未变；历史UNKNOWN保留。累计11／11，固定24项22 PASS／0 FAIL／2 BLOCKED（缺第二实体Android），B6／iOS／生产未通过，HnuHole未提交／推送。见[本轮分层证据](../../services/api/authlab/android-b3b4-native-negatives-20261013-verification.json)。

> **2026-10-13 修复后单次真机重试PASS：**Astra／Ultra只读分析定位Google GMS校验所需的DAL `handle_all_urls`缺失；仅为批准的acceptance20261012包补齐该关系，原两条关联不改，站点提交152a2b0、部署38268212768成功，Google检查已更新为true。生成工具同步补齐两种关系，聚焦5项检查通过；产品APK未变。原vivo S18本次仅发起一次批准控制：PID27847原生成功，用户完成验证，C真实204，SQL Passkey从0增至1，独立App／设备／SQL均PASS。旧两轮失败和PID14444的UNKNOWN均保留，不重放证明。暂停后的原服务按原材料恢复到OPEN第4代；初始严格恢复检查因V过期OTP预算元数据1→0而报FAIL，保留原回执，随后只读核对及实际产品控制通过，未reset／rekey／迁移。此次只完成正向前置，NI-D01／D02错误签名／D03未关联包负向尚未执行，累计仍8／11，固定24项仍19 PASS／3 FAIL／2 BLOCKED，B6／iOS／生产未通过。HnuHole未提交／推送。见[本轮记录](../../services/api/authlab/android-b3b4-fresh-20261012-verification.json)。

> **2026-10-12 单次重试结果：**用户明确要求只重试一次、失败后停止；已用原安装产品包完成一次新的NI-D02批准控制请求，PID21565，实际结果FAIL，未提交C证明、SQL Passkey仍0。上次PID14444的UNKNOWN及credentialMayExist和全部原证据保留于attempt-product-control-01；新请求没有重放旧证明。用户确认点击继续，手机重试已停止。随后用户明确要求GPT-6 Astra／Ultra分析已有证据，当前只读分析进行中。累计仍8／11，三项负向未执行。见[本轮记录](../../services/api/authlab/android-b3b4-fresh-20261012-verification.json)。

> **2026-10-12 原 vivo 接续正在进行：**归档解密密钥已遗失，旧8项保留原APK／源码／设备／SQL证明。新独立C／V／SQL及获批测试DAL已就绪；独立Google准备通过，首次真实窗口超时的UNKNOWN原样保留，用户切换VPN后的唯一新诊断重试明确返回`DATA_ERR(30)`，没有C证明，静态选项审查未证实请求格式缺陷。完整批准Flutter产品包已正常构建、签名及安装（68,199,652字节），实际原生ELF已去调试符号，错误签名包与批准包的558个非签名条目完全一致；Google凭据提供方已核对，旧两个APK未变。产品边界检查通过但未重建Release APK。首次产品控制启动在原生认证前发现WSL运行服务已停止；恢复01已完成并保留独立回执；再次中断后按原材料完成恢复02，C／V均从FROZEN第2代／证据版本121正常恢复到OPEN第3代／证据版本122，恢复时SQL业务表及代理计数仍为0。Windows观察器已加上精确守卫，本地超时／取消及后来的回调均不能将UNKNOWN变为可清理；25项安装守卫和4项观察器守卫测试通过，APK／原生插件／原源码准入未变。首次真实批准产品控制已结束：App PID14444发起1次原生调用后本地超时（nativeTimeout1、nativeErrored1），观察器正确拒绝自动返回，产品原生结果仍UNKNOWN、系统凭据可能存在。SQL实际1个测试账号／0个Passkey，代理bindingOptions1／bindingSubmits0，未向C提交证明；独立观察器记录外层vivo选择器，主任务观察到内部Google注册窗口。人工返回后只按HOME导航到桌面，捕获时后台仍有3行已知原生活动，不能宣称任务消失或UNKNOWN解除。批准控制未通过，负向未执行，提供方因UNKNOWN尚未恢复；本轮相关日志只读审查已结束、根因未定：主脱敏报告与独立报告一致，已分别核对主报告13个源文件及68条引用行、独立报告10个源文件及7条引用行的完整性；这些核对不代替验收。同一Google UI进程注册流程日志约53.15秒后出现`TIMED_OUT`，未建立请求／challenge关联或产品回调，也未确定端点、状态码或网络根因。稍后采集的已验证VPN551覆盖GMS UID10172，但允许绕过，不能证明仪式当时每条连接的路由或服务端点可达。用户只读确认Google密码管理工具正常且无异常提示、Play商店显示设备已通过认证；这些人报不代替独立attestation或凭据创建证明。原产品UNKNOWN／credentialMayExist及禁止盲重试、恢复提供方、重装的守卫继续保留。新NI-D01／D02／D03仍未取得产品PASS。B3＋B4仍8 PASS／3项历史FAIL，固定24项仍19 PASS／3 FAIL／2 BLOCKED，B6／iOS／生产未通过。顺序为D02批准控制→D01→D02错误签名→D03未关联包。见[本轮脱敏记录](../../services/api/authlab/android-b3b4-fresh-20261012-verification.json)。

> **2026-10-11 换机交接最终回执：**实现、测试和排错源码已推送 4c40f90；7 个加密归档／22 个分片已逐资产核对远端 SHA-256，并通过本地认证解密和文件内容核对。已删除五个任务 WSL 根、12 个专用容器、8 个卷、4 个网络；Windows 缓存／交接暂存副本删除被自动审批拒绝，仍保留，不能宣称全部清空。B3＋B4仍8 PASS／3 FAIL，固定24项19 PASS／3 FAIL／2 BLOCKED；B6／iOS／生产未通过。新机器先读[换机交接](auth-privacy-machine-transfer-20261010.md)及[最终交付和清理实录](../../services/api/authlab/auth-privacy-machine-transfer-verification.json)，解密密钥单独交付。

> **2026-10-10 ultra排错阶段历史快照：**B3＋B4保持8／11 PASS、3项原执行FAIL。用户确认本轮点“继续”，全局代理下Google批准正向仍未取得证明；原生7次失败与一次系统清理器在原生开始前强停分别保留。只读审手机实际vivo选择器v15.0：provider非RESULT_OK返回和内部失败会被统一上报selector取消，原错误信息未传到App。此机制已由安装APK静态代码证实，但Google上游失败根因和本轮精确分支仍未证实；27字符消息摘要仅作佐证，旧JDI原型未区分参数／堆对象，不作为验收证据。ultra子审触及用量上限后由主任务续审。新有界观察器源码已保留并编译，未发起新ceremony；产品APK未改、已通过8项不重验。当前Google凭据／自动填充设置临时保留，等待人工只查看密码管理工具设置，不清数据或登出；验收后须按原备份恢复，Clash全局模式须由用户恢复。固定24项仍19 PASS／3 FAIL／2 BLOCKED，B6／iOS未执行，未提交／推送。见[具体诊断记录](../../services/api/authlab/android-passkey-selector-diagnosis-verification.json)。

> **2026-10-10 Google 提供方初轮历史结论（本轮接续见顶部）：**B3＋B4仍为8／11 PASS、3项原执行FAIL。v17修正隔离账号的正常产品登录续办，分析／三包构建／四种签名核对通过；手机批准签名Google正向控制4次均在证明返回前取得原生取消，未新增绑定，新的Google三项负向未执行。系统Google账号存在，用户确认Chrome同步和实时搜索可用；Google远端关联检查批准签名为true、错误签名及未关联包名为false，这些不代证手机拒绝原因。具体根因未确认，不归咎用户，也不把通用取消计为关联拒绝。已恢复原vivo通行密钥及自动填充设置，主包v16与数据保留、隔离包v17保留，可复用环境不清理。固定24项仍19 PASS／3 FAIL／2 BLOCKED；B6和iOS未执行，未提交／推送。下一次须先取得具体原生原因或可用实际提供方的正向控制，禁止原样盲重试。见[Google对照记录](../../services/api/authlab/android-b3b4-google-provider-verification.json)。


> **2026-10-10 v16批次历史结束记录（Google重试见顶部）：**B3关闭组4／4通过，B4关联与存储组4／7通过，合计8／11 PASS、3 FAIL、0 NOT_RUN。C01／C03／C04和D05已在v16真实App通过，早期选择超时是历史记录；D05另一凭据保留由未变v15实际SQL证据补充，不宣称vivo双凭据创建。D01客户端固定RP、实际服务端422及原五分钟期限核对通过，原生错误RP与D02错误签名／D03未关联包名均只有OEM通用取消，不能归因为关联拒绝。批准控制组实际C204，负向未新增凭据；三项完整验收仍FAIL。批准隔离签名已恢复，主App／账号／草稿／环境保留，人工窗口已结束，不再自动弹安装、认证或追加关闭。固定24项累计19 PASS／3 FAIL／2缺第二实体Android而BLOCKED；B6未执行，iOS／完整非iOS／生产未通过，未提交／推送。当前细节见[本批脱敏记录](../../services/api/authlab/android-b3b4-batch-20261010-verification.json)。


> **2026-10-10 B3＋B4 逐项结果：**固定11项当前接受8项（NI-D04、NI-C01、NI-C03、NI-C04、NI-C02、NI-D05、NI-K01、NI-K02）。每项保留独立App／设备／SQL和启动版本；夹具失败与原成功前置记录保留，不重放证明。本轮11项均已执行；未通过项为NI-D01、NI-D02、NI-D03，具体缺口见本批记录。B1＋B2原11项PASS不改写。用户确认卸载后的旧本机状态不能续用，历史证据及可复用环境保留；完整非iOS／iOS／生产未通过，HnuHole未提交／推送。见[任务单](auth-privacy-b3-b4-plan.md)及矩阵JSON的`b3b4Verification`。


> **2026-10-10 B3＋B4 v16早期凭据选择失败历史快照（已被本批结果替代）：**本轮剩余七项新增PASS为0，固定11项累计仍4项原版本PASS／7项FAIL。主包v16已更新并保留账号／草稿；12项原生测试、13项Release边界、当前分析和四包签名构建通过，共享188项及SQL249项沿用v15未变源码的原范围。调试名称已同时设置user.name／displayName，实际账号handle／签名检查未改。用户截图曾出现唯一合成标签，但实际目标断言未完成；同名列表查找和60秒窗口导致超时，失败原版本与原请求保留。定位脚本已改用专用临时XML、按唯一标签有限滚动，不自动选择／认证；尚未取得成功真实定位证据。停止本轮人工窗口，不再自动弹安装或认证，不再推进关闭。先通过实际可辨认目标和同一ID断言预检，才恢复固定项集中验收。环境、手机数据和历史证据保留；未提交／推送。见[当前自动准备范围](../../services/api/authlab/android-b3b4-v16-preparation-verification.json)。

> **2026-10-10 B3＋B4 v15集中验收准备：**当前Flutter分析／188项测试、实际PostgreSQL249项race／vet（无跳过）、模拟器原生12项、独立Release13项、四包签名与公开关联前置核验PASS；这些不代证剩余七项实体验收。C02／D04／K01／K02保留各自原版本PASS，累计仍4／11。正常可发现断言保持真实userHandle／ID检查；合成显示标签只属于受保护调试入口，Release禁用。移除后的旧断言／会话／恢复码在实体测，另一条凭据保留另由实际SQL事务证据覆盖，不宣称vivo连续创建两条。仅允许cycle10草稿／cycle11身份完整关闭，且均须实际断言预检先通过；测试构建96天上限，现有约70天偏移未推进，SQL截止／手机时间不改。用户已授权集中人工窗口；主包更新一次后连续执行，签名／包名对照按固定隔离包切换。环境和历史证据保留；未提交／推送。见[当前自动验证记录](../../services/api/authlab/android-b3b4-v15-preparation-verification.json)。


> **2026-10-10 B3＋B4 v14批次实测历史结论：**固定11项累计4项PASS（C02／D04／K01／K02）、7项FAIL，0项NOT_RUN；各项保持自己的版本，整批未通过。批准签名控制组实际绑定C204；错误签名／未关联package只取得通用取消，关联拒绝原因未证实。错误RP客户端拒绝成立，但服务器RP哈希负向未收到证明。移除组第一条真实绑定成功，第二条原生创建失败，尚未执行移除及旧断言。v13关闭／V释放及同邮箱草稿隔离前置完成，但旧断言codec拒绝的具体字段仍未查明，完整C01／C03／C04未通过。SQL已关闭10／待关闭0，已关闭资料／凭据／有效会话残留0。当前分析、模拟器原生9项及独立Release12项PASS；188项保留原范围，不代证实体固定项。批准隔离签名已恢复，主包及环境保留，无新指纹／安装／注销任务。B1＋B2原11项PASS不改写；24项累计15项PASS，7项FAIL，2项缺第二实体Android而BLOCKED。未提交／推送。见[本批脱敏结果](../../services/api/authlab/android-b3b4-batch-20261010-verification.json)。


> **2026-10-10 B3＋B4 最后固定批次历史计划：**按用户最新“一次性做完”继续剩余七项，已通过C02／D04／K01／K02保留原版本。用户卸载后须新安装v13和新账号；两次完整关闭明确限于cycle8草稿、cycle9身份／旧凭据，测试构建上限80天，既有偏移不回退，SQL七天截止不改。原8轮及失败记录全部保留，不追加关闭重试。旧代理内存请求已结束并独立归档，累计计数／CA／端点／数据库保持，不能声称旧控制器迟到成功。v13分析188项、原生8项、Release12项保留各自PASS范围；安装尚未开始，实体剩余七项尚未通过。环境保留；未提交／推送。


> **2026-10-10 B3＋B4 用户确认卸载：**用户已确认手动卸载App，前述“原因待核实”状态已结束。本机旧会话、草稿和UID钥匙不能续用；已保存的服务端／宿主设备历史证据、测试源码和环境仍保留，C02／D04／K01／K02四项原版本PASS不撤销。其余七项没有因此完成；C01／C03／C04完整旧回调轮次仍FAIL，D01／D05未执行，D02／D03此前通用原生错误仍不能算关联拒绝。v13分析188项／构建／原生8项／Release12项已通过各自范围。后续设备执行须新安装已审阅候选并使用新合成测试账号，不能声称恢复卸载前待办或同进程迟到控制器。8轮关闭预算不再自动增加；当前无安装或系统认证任务，不要求人工指纹。未提交／推送。


> **2026-10-10 B3＋B4 当前安装状态阻塞：**接受4／11（NI-C02、NI-D04、NI-K01、NI-K02），均保留自己的实际App／设备／SQL和版本。v13独立指定公开ID的调试验收入口修复已通过Flutter分析、共享188项、三种ARM64包＋仅签名对照、模拟器原生8项及独立Release12项；正常可发现恢复继续拒绝allowCredentials，Release拒绝新验收入口，模拟器与构建不代证vivo固定项。C01／C03／C04前次完整迟到轮次失败保留，8轮关闭额度已用完，不再自动增加。准备更新v13时，vivo连接正常但包管理器找不到主App与隔离App（用户0），只剩原生探针；更新尚未开始，原因正在向用户核实，不推断为主动卸载或清理。B4的D01／D02／D03／D05实际续验等待设备状态确认。环境、数据库、缓存、各版本和历史证据保留；未提交／推送。


> **2026-10-10 B3＋B4 逐项结果历史检查点：**固定11项当前接受4项（NI-D04、NI-C02、NI-K01、NI-K02）。每项保留独立App／设备／SQL和启动版本；夹具失败与原成功前置记录保留，不重放证明。剩余固定项继续执行，B1＋B2原11项PASS不改写。服务端证据及可复用环境保留；本机数据按顶部卸载确认理解；完整非iOS／iOS／生产未通过，HnuHole未提交／推送。见[任务单](auth-privacy-b3-b4-plan.md)及矩阵JSON的`b3b4Verification`。


> **2026-10-10 B3＋B4 当前独立原生入口修正：**NI-C02已以v12实际同进程首次绑定UNKNOWN、cycle7正常关闭／V释放、同邮箱新注册、迟到原响应及原键查询完整通过，固定项接受4／11（C02、D04、K01、K02）。v12主组cycle5草稿关闭／新注册和cycle6真实绑定／身份关闭已完成，但旧证明选项被产品可发现恢复codec按规则拒绝，未调用系统；C01／C03／C04仍FAIL，旧迟到控制器已结束，不冒称完整通过。8轮测试时钟额度已用完，不再自动增加关闭轮次。当前只修复调试验收的独立指定公开ID入口，产品恢复仍拒绝allowCredentials，挑战／UV／来源和C校验不放宽；补编码测试和Release禁用入口检查，当前原生／Release待重验。观察器只对只读ADB超时重试一次。主账号、草稿、所有版本和环境保留；未提交／推送。


> **2026-10-10 B3＋B4 当前凭据选择修复：**已接受NI-D04／K01／K02，共3／11。v11原注册续办、真实绑定C204及身份账号普通worker关闭／V释放已完成；旧凭据系统列表缺少人工可辨认账号标签，用户未认证，原生get失败且C未收到旧证明，C01／C03／C04未接受。v12关闭／移除断言用 allowCredentials 限定本次实际登记的公开凭据ID，仍要求真实系统证明和返回同一ID，服务器校验未放宽；不让用户从重复标签中猜账号。原失败进程的迟到控制器已结束，旧响应保留为历史，另做完整同进程轮次。专用Go测试构建固定8轮／64天上限已经runtime/operator测试和vet，现有约35天偏移、SQL七天截止、真实时间、CA及库保持；只再执行草稿cycle5、身份cycle6与UNKNOWN绑定cycle7，累计约56天，不追加ID或无界重试。共享188项及原生7项／release11项保留原版本范围。环境、账号、草稿和历史APK归档保留；未提交／推送。


> **2026-10-10 B3＋B4 注册修复历史快照：**NI-D04／K01／K02三项已有各自实际App、设备、SQL及版本证明。新的草稿账号关闭及V释放已完成，但v9累积用户名26字符被客户端6–24字符规则拒绝，C01／C03／C04仍未接受；失败按版本保留。v11已核对原邮箱实际字段为 registration.request.email，新用户名固定20个合法字符，并保留同精确邮箱的原注册、旧草稿和第4次关闭计数基线，SQL只读复核原七天截止、普通worker清理及V释放后续办，不重新注销或回退／重复推进时钟。当前约28天偏移，专用上限48天；CA／端点／库／主包状态保留。分析、四种ARM64构建及签名对照PASS；共享188项、原生7项和release11项保留原版本／范围。C02完整迟到轮次及D01／D02／D03／D05继续固定执行，泛化原生错误不能算关联拒绝通过。历史APK已按精确摘要移至C盘工作区专用缓存，不清SDK／AVD／构建缓存／数据库；一个从未安装的v10未关联包归档副本因空间不足不完整，已明确记录。未提交／推送。


> **2026-10-10 B3＋B4 注册修复历史快照：**NI-D04／K01／K02三项已有各自实际App、设备、SQL及版本证明。新的草稿账号关闭及V释放已完成，但v9累积用户名26字符被客户端6–24字符规则拒绝，C01／C03／C04仍未接受；失败按版本保留。v10将新用户名固定20个合法字符，并保留同精确邮箱的原注册、旧草稿和第4次关闭计数基线，SQL只读复核原七天截止、普通worker清理及V释放后续办，不重新注销或回退／重复推进时钟。当前约28天偏移，专用上限48天；CA／端点／库／主包状态保留。分析、四种ARM64构建及签名对照PASS；共享188项、原生7项和release11项保留原版本／范围。C02完整迟到轮次及D01／D02／D03／D05继续固定执行，泛化原生错误不能算关联拒绝通过。未提交／推送。


> **2026-10-10 B3＋B4 早期历史检查点：**用户已明确继续。v9夹具分析、四种ARM64构建及签名对照PASS，批准隔离包更新完成；缺钥错误页补验及K02四阶段先集中执行。共享188项和原生7项／release11项保留原版本与范围，未变源码摘要已核对。专用测试时钟容量已扩至48天，保留约21天偏移，不回退高水位，不改SQL七天截止、主机／手机时间、CA或库。隔离卸载已移除原C02的旧Keystore钥匙，本地只剩历史旧密文，不能恢复为可用UNKNOWN；服务端回执与未释放响应保留，完整迟到回调另做新的同进程轮次。环境／主包／账号及草稿保留；未提交／推送。


> **2026-10-09 手机接手历史快照（2026-10-10已续跑）：**主包v8更新成功（APK摘要`0ddf6180d162…`），未卸载／清数据；未启动新验收，未自动点击安装、未代做认证或改变设备安全设置。当前没有本批设备runner／观察器／安装任务。按用户接手要求暂停手机操作；隔离包尚未更新，原C02待办／未释放响应、账号与环境保留。B3＋B4接受数仍为1／11，安装成功不代证固定项PASS。


> **2026-10-08 B1＋B2 当前交付：**固定11项已全部接受PASS：NI-L01–L04／NI-U01–U03／NI-A01–A04。每项保留真实App、宿主设备事实与顺序、独立C／SQL及代理计数、启动时APK与源码摘要。覆盖配置变化、Activity／engine销毁与持久恢复、后台取消、新请求期间旧成功／错误回调围栏、真实无可用凭据、大字小屏、TalkBack失败／恢复码确认／UNKNOWN原键核对与终态，以及原生请求期间冻结503、冻结恢复入口拒绝、实际另一设备接替401、主动新登录后新挑战204。TalkBack十轮失败按各自版本保留；独立不抑制辅助服务的诊断证明公开错误节点与焦点链，自动焦点不计人工验收。新进程保留真实手势与人工朗读确认，合成字段只作夹具准备，不代证IME；原辅助设置已恢复。当前候选分析／Flutter188项／ARM64＋x64构建、原生codec／ownership5项、独立release10项guard与交接校验PASS，各自版本和范围保留；旧14阶段不改写。完整非iOS／AC05／B02及生产仍未通过，iOS本轮排除。固定24项累计接受11项，余13项及B6终验不在本次B1＋B2范围。环境、缓存、账号与草稿保留；未提交／推送。见矩阵JSON的`b1b2Verification`及[固定计划](auth-privacy-non-ios-closure-plan.md)。


> **2026-10-08 固定收口计划：**剩余非iOS匿名基础验收统一按[24项／6批次最终计划](auth-privacy-non-ios-closure-plan.md)执行；预算48–64有效工时，目标2026-10-19，前提为持续工作日推进且第二实体Android在10月15日前到位。10月15日核对B1–B4；每批报告固定ID累计结果，不再零散追加“下一步”。24项及最终候选回归／交接通过才可结束非iOS开发验收；缺第二设备不能算完整PASS。iOS、生产及未来业务联动独立，不阻止本分支按其授权范围结束。此为计划，新增项尚未执行。

<!-- CURRENT_NON_IOS_START -->
> **2026-10-08 批量验收交接：**十四个命名实际App阶段已PASS，每项保留自己的APK／夹具／runner摘要、设备PID和代理计数。覆盖真实注册、双端独立草稿／手机主动接替／账号隔离，真实Passkey成功响应丢失与原键跨进程COMMITTED核对，实际provider期间控制器取消与产品返回，C证据过期冻结后的旧会话401／主动登录／明确结束旧UNKNOWN，两次提前成功后的原回执确认与产品移除，未回应原生操作约60秒取消，篡改来源422拒绝及自然到期原键NOT_COMMITTED核对。旧来源拒绝在核对前遇USB及服务中断，仍按原版本保留，未迁成新会话原结果；新的完整负向／核对另有自己的证明。取消／超时后的OEM窗口清理由宿主在原生结果后执行，不宣称自动关闭或任意迟到回调；两秒观察范围保持。对应四组SQL/race/vet、R03十九项、R05及Flutter188项回归PASS，不代证新夹具；新夹具分析／ARM64＋x64构建与设备执行逐项PASS。Activity重建／旋转、原生等待期间Gate／接替、完整关联／签名负向及真实Passkey／未知迟到待办参与关闭仍需补入口和证据。仅有vivo，OEM实体搬家BLOCKED；iOS本轮SKIP；完整AC05／B02及生产继续未通过。工具、环境、缓存、原账号与草稿按用户指令保留；未提交／推送。见[报告](auth-privacy-non-ios-validation-report.md)和[机器记录](../../services/api/authlab/android-matrix-verification.json)。
> **2026-10-07 非 iOS 匿名基础当前增量：**真实 vivo 系统 Passkey 核心链保留原版本 PASS；同证书来源兼容及 V 无确认锚点核对修复已通过当前 R01完整SQL/race/vet、R03实际C/V及R05真实Dart→HTTPS→SQL回归。新实际App双设备接替与未过期旧代次 OTP 的 V冻结／恢复／原结果核对已PASS；模拟器完整App会话／身份草稿跨进程、卸载重装及受控旧密文缺钥拒绝已PASS，OEM搬家未验。vivo原生vault16项／3组跨进程、Passkey codec5、实际单App备份拒绝、手机→模拟器密文缺钥拒绝及模拟器探针卸载重装已PASS，各自保留APK版本和证明范围。新实际App双设备／V Gate夹具的运行结果逐项见[机器记录](../../services/api/authlab/android-matrix-verification.json)。旧一次性服务被旧退出trap清理后，已修复显式保留模式，实际验证初始化器退出后C/V、双Gate watcher及材料仍在；新端点与合成账号另行验收，原r1/r2/r3结果不迁成新库证据。真实锁屏／解锁、独立计数的手机重启与同会话／草稿恢复，以及独立release原生调试入口／开发信任拒绝已PASS；当前客户端188项与R05增量PASS；过期flow正常十分钟清理后的原键未知核对／主动续办／同密钥新票据四个实际App进程已PASS。真实IME已在vivo现有搜狗键盘上PASS：18次实际编辑事件、10次非折叠组合态，未确认文字未入原生草稿，确认后同会话／中文草稿经PID7275→7968独立进程恢复；初版真实触摸被测试绑定丢弃的夹具失败保留，原输入法已恢复。此次仅修改测试／runner并执行分析、构建与实际IME场景，188项与R01／R03／R05保留原执行范围，未重跑。TalkBack实际导航／取消／返回及新进程同会话／草稿焦点朗读已PASS，原辅助功能已恢复；此次分析／离线构建与实际设备场景PASS，完整188项及R01／R03／R05保留原执行范围。独立Gate／证据测试时钟推进的正式关闭／同邮箱再注册已PASS，零身份草稿和三身份资料／累计历史与原凭据拒绝经实际vivo App验证；SQL七天截止与触发器未改，不代证真实等待七天或未决待办迟到回调。系统Passkey边界及OEM矩阵仍待完成，AC05／B02整项未通过。iOS按用户指令排除，生产单列。见[任务单](auth-privacy-non-ios-plan.md)和[报告](auth-privacy-non-ios-validation-report.md)。工具、缓存和新环境按用户指令保留。HnuHole增量未提交／推送；公开测试关联站点已按授权发布。

> **2026-10-07 批量验收历史快照：**完全访问已启用，原自动审批额度故障已解除；私有配置导出、匹配摘要的实际代理与ARM64＋x64合包构建已PASS。四组完整SQL/race/vet、实际C/V、R05及Flutter188项回归已导出对应源码清单，缓存源码未在执行与采集间变化，并与当前对应后端／客户端源码一致；不代证新增手机夹具。批量实际App已接受八阶段：新账号注册、手机草稿、模拟器独立草稿、手机主动接替恢复、同机账号隔离、真实Passkey绑定响应丢失、独立进程原回执核对、实际provider活动期间控制器取消后产品返回。前七项属于v1包；取消属于触摸修正后的v3包PID18612。取消后系统窗口仍在，验收后宿主关闭；只证明两秒观察窗口内无新增凭据／提交，不宣称系统窗口自动关闭或任意迟到回调。来源负向两次在原生侧失败，没有HTTP证明提交，未计PASS；新增产品移除已有测试Passkey与真实异步等待后接续，原未知结果先核对、不重放证明。历史账号关闭／IME／TalkBack／核心Passkey和各自旧版本保留。仅有vivo S18，OEM实体搬家BLOCKED；iOS本轮SKIP，完整AC05／B02及生产继续未通过。环境／缓存保留；未提交／推送。见[任务单](auth-privacy-non-ios-plan.md)、[报告](auth-privacy-non-ios-validation-report.md)和[机器记录](../../services/api/authlab/android-matrix-verification.json)。
<!-- CURRENT_NON_IOS_END -->
> **2026-10-05 Android 异常验收当前结果：**vivo S18 上三组实际 App 故障场景已 PASS，七个独立进程 PID 为 10229／10535／12328／12825／13052／13286／13482。覆盖真实提交响应丢失、原意图重启核对无重复；C Gate 冻结拒绝写与恢复后旧代次令牌拒绝／主动登录；退出先清 Bearer、独立撤销待办持久化和重启排空。Flutter 分析、182 项测试、完整 ARM64 测试包及 runner／调试入口负向检查 PASS。见[任务单](auth-privacy-android-fault-plan.md)、[报告](auth-privacy-android-fault-validation-report.md)、[机器记录](../../services/api/authlab/android-fault-verification.json)。保留历史正常链路与初次部分执行的原版本；本轮复用环境／缓存／测试 App 按用户指令保留，临时 USB 映射已移除。完整 AC05／B02／系统 Passkey／iOS／生产仍 BLOCKED；剩余设备矩阵继续单列。未提交／推送／部署。

> **2026-10-05 Android 真机当前结果：**基于已发布 `0eff47a`，vivo S18上的实际App→HTTPS实际cmd C/V→一次性SQL／原生Keystore基础链已PASS。write/read PID为20708／21981；覆盖测试SMTP注册、恢复码完整确认、身份创建／改名、跨进程会话／身份恢复、退出、旧会话401和点击“前往登录”后的密码登录。Flutter分析、182项测试、完整ARM64测试APK及负向保护PASS。见[任务单](auth-privacy-android-live-plan.md)、[报告](auth-privacy-android-live-validation-report.md)和[记录](../../services/api/authlab/android-live-verification.json)。只连接已安装且摘要匹配的App，阶段间不重装。本轮一次性数据库／服务／私钥／专用缓存／APK及临时测试App已清理，当前本地交接完成；AC05整项／B02／系统Passkey／iOS／完整设备矩阵／生产仍未通过，本轮未提交／推送。

下方AC01–AC06保留原日期与证明范围；AC04–AC06已在72ca9e8发布、0eff47a补交付记录，历史“未提交／未推送”不代表当前Git基线。旧AC06的PASS仅证明原版本地交接；本次源码、真机结果、清理与本地交接另见currentAndroidLive／currentHandoffState，不覆盖旧证据。

> **2026-10-05 AC06 当前交接：**匿名基础源码与本地交接材料已整理，详细结论见[最终交接报告](auth-privacy-final-handoff-report.md)、[AC06任务单](auth-privacy-final-handoff-plan.md)和[最终记录](../../services/api/authlab/final-handoff-verification.json)。后端／真实客户端回归保留AC04原证据，Android模拟器范围保留AC05；AC05整项、B02整模块及生产仍未通过。当前AC04–AC06修改尚未提交／推送，本地交接完成不代表远端已发布。历史规格／AI评审／旧台账按原日期、源码摘要与证明范围理解；下一步补外部平台配置与设备证据，或按当次授权发布当前材料，不自动开发完整业务片。

> **2026-10-05 AC05 当前交付：**当前完整 Android arm64 App、两个 instrumentation APK、模拟器 vault16项与3组跨进程、Passkey Dart9／Android codec5、Flutter真实原生双进程均PASS；新增身份草稿恢复／组合输入／账号隔离和原意图核对，write/read PID 7062／7189。Flutter分析及179项、四份OpenAPI本轮PASS。AC05整项和B02整模块仍BLOCKED：iOS／系统Passkey／物理设备／系统备份与完整App→实际C/V尚无完整证据。见[AC05报告](auth-privacy-platform-acceptance-validation-report.md)、[任务单](auth-privacy-platform-acceptance-plan.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。保留AC04原指纹与证明范围；下一步AC06最终交接，不扩展完整业务片。本轮未提交／推送／部署。

下方认证历史记录按原日期与版本理解；其平台范围和阻塞保留台账 currentAC05，后端回归保留 currentAC04。F3 当前实现及平台待验范围以顶部交接和台账 currentCommunityFlutterF3 为准。

> **2026-10-05 AC04 当前交付：**基于已推送 `cbc99b0`，补齐真实 Dart→HTTPS handler→SQL 的 V 独立冻结／恢复旧 OTP 围栏、身份关闭资料／永久历史和同邮箱新账号隔离场景；修正 R03 普通重启测试的授权事务停机时序，应用逻辑／公开 API／迁移未变。完整 Go／SQL／race／vet、R03 实际 C/V、Flutter 分析及179项测试、R05 均 PASS。覆盖、失败修复与精确范围见[AC04报告](auth-privacy-regression-validation-report.md)、[任务单](auth-privacy-regression-plan.md)和[机器记录](../../services/api/authlab/privacy-regression-verification.json)。B02整模块仍BLOCKED；下一步AC05平台验收，再AC06最终收口。本轮未提交／推送／部署。

下方 AC01–AC03 和平台记录保留原版本与证明范围；当前回归入口为台账 currentAC04，历史“未实现／未执行”不代表本轮状态。

> **2026-10-05 Git远端交付：**AC01／AC02／AC03源码、测试和小型证据已提交至 [8db630f](https://github.com/zewbby/HnuHole/commit/8db630f66bfc87cc05164aaae95b02b0d884d09a)，并普通推送到 `origin/codex/auth-privacy-handoff`；远端提交号已核验一致。本段是随后补充的交付记录。下方“未提交／未推送”及机器记录的uncommitted字段保留测试时快照，当前交付状态见台账publicationDelivery／Git提交历史。原测试摘要保留；额外Git文本摘要只允许CRLF→LF换行转换，协议向量仍逐字节核验。发布本次Git提交没有重新执行动态测试，也不代表部署、B02整模块验收或生产批准。

> **2026-10-05 AC03 当前交付：**当前数据／角色／HTTP／客户端持久状态及日志已完成有范围核对，修复应用错误／HTTP、PostgreSQL普通错误和移动端通道诊断三项差异；后续匿名业务契约已固定。完整Go／SQL／race／vet、R03实际C/V角色／日志与AC01／AC02回归、Flutter analyze与179项测试、R05真实Dart→HTTPS→SQL均PASS。见 [AC03报告](auth-privacy-boundary-validation-report.md)、[三步任务单](auth-privacy-boundary-plan.md)、[后续契约](auth-privacy-business-contract.md)及[机器记录](../../services/api/authlab/privacy-boundary-verification.json)。B02整模块继续BLOCKED，公共内容／聊天／管理消费者尚未实现，原生设备／生产证据单列。未提交／推送／部署。

以下 AC02／AC01及更早记录保留原日期、摘要和证明范围；“AC03未实施”等仅描述历史版本。currentFeature旧SQL／Flutter等字段明确保留为历史快照；本轮结果见currentAC03，历史平台不代证当前native验收。

> **2026-10-04 AC02 当前交付：**在保留 AC01 的工作区中，整账号正式关闭与身份联动已实现，完整服务端 SQL／race／vet 和 R03 实际 C/V 验收均 PASS。正式关闭原子擦除活动身份资料，保留累计状态、已有墓碑和永久回执；11→12 前向升级、受限角色、冻结／并发／回滚及同邮箱新账号独立历史取得本轮证据。详见 [AC02报告](auth-identity-account-closure-validation-report.md)、[实施任务单](auth-identity-account-closure-plan.md)及[机器记录](../../services/api/authlab/identity-account-closure-verification.json)。AC03 尚未实施；B02 整模块仍 BLOCKED，帖子／聊天业务调用、客户端／设备与生产缺口单列。未提交／推送／部署。

以下 AC01 及更早交付保留原日期、源码摘要与证明范围；“AC02 未实现”等表述仅描述历史版本。当前服务端版本以 AC02 记录为准，历史平台结果不能代证当前回归。

> **2026-10-04 AC01 交付（历史版本）：**基于 `faf557d` 的本次工作区已实现 V 独立 Gate，最终完整 Go／SQL／race／vet 和 R03 实际 C/V 进程验收均 PASS。V 正式迁移 3→4、独立状态／材料／连接池、受限恢复角色、最终资格事务、后台外部调用代次复核和旧 V schema 快照阻断均已接通。详见 [AC01报告](auth-verifier-safety-gate-validation-report.md)、[实施方案](auth-verifier-safety-gate-plan.md)及[机器证据](../../services/api/authlab/verifier-safety-gate-verification.json)。AC02／AC03 尚未实施；B02 整模块仍 BLOCKED，平台与生产门槛单列。本次改动尚未提交／推送。

以下原有 2026-10-04 平台交付及更早记录保留其原版本和范围；其中“AC01 未实现”和工具未执行等字段描述历史状态，当前 AC01 以上述证据为准。

> **2026-10-04 最新验证与环境交付：**基于远端 `codex/auth-privacy-handoff` 的 `d624ea30943a2b12096c20dbeefd844ba0e5e840`。Flutter分析与175项mobile测试、真实Dart→HTTPS→PostgreSQL R05、Android完整app构建、16项vault＋3组跨进程探针、9项Passkey Dart／5项Android codec和真实Flutter双进程共享AuthStore探针均PASS；Go/SQL/race/vet、R03实际C/V进程及完整OpenAPI已在本轮复验。环境与可复验命令见[本机环境](local-test-environment.md)，精确证明范围／失败修复见[最新记录](../../services/api/authlab/identity-runtime-test-verification.json)。**B02整模块仍BLOCKED：AC01 V Gate、AC02身份整账号关闭尚未实现，iOS、真实Passkey ceremony和物理设备／B02设备矩阵仍未验。**用户要求保留D盘工具环境、删除全部测试缓存和临时产物，完成后直接推送对应分支。

## AC05 当前 Android 故障场景与保留环境

- A00／A05／A12／A13／N01／B02：unknown→reconcile 以同一原键与跨进程 Keystore 恢复真实 C SQL 回执，身份数与提交数不增加；映射 X01／X02／X04／X08。
- A01／A11／A12／A13／B02：冻结时 App 暂停权威恢复，保护写 503；恢复推进代次，旧令牌拒绝，主动登录重新建立会话；映射 X02／X03／X08。
- A05／A12／A13／N01／B01：退出先清 Bearer、原生独立能力待办保留，重启后实际撤销成功和旧令牌拒绝；映射 X03／X08。
- 真实入口：[App 故障测试](../../apps/mobile/integration_test/auth_fault_device_test.dart)、[设备 runner](../../tools/run-android-live-device.ps1)、[代理](../../tools/android-auth-fault-proxy.py)、[宿主控制](../../tools/control-android-auth-fault.py)、[Android 私有调试连接](../../apps/mobile/android/app/src/main/kotlin/org/hnuhole/hnuhole_mobile/MainActivity.kt)。版本、七个 PID、SQL 计数及剩余 NOT_RUN／BLOCKED 均见[本轮报告](auth-privacy-android-fault-validation-report.md)和[证据](../../services/api/authlab/android-fault-verification.json)。
- Windows／WSL 保留目录、OWNER、运行时生命周期和复验参数见本轮报告；测试 App、依赖缓存与现有 SDK／AVD 保留，临时 USB 映射移除。当前场景通过不覆盖锁屏、备份／重装、V Gate、正式关闭、OEM／辅助服务、跨设备或系统 Passkey／iOS。

## AC05 当前模块映射与复验入口

- N01／A12／B01：R07 标准完整 App 和 native vault16＋3组、R09 Flutter真实原生双进程通过；[设备入口](../../apps/mobile/integration_test/auth_security_device_test.dart)保留原凭据操作键与登出围栏。Keystore／故障注入和模拟器进程边界不代证 OEM 锁屏、系统备份和真实卸载重装。
- B02／A12／N01：新增[身份设备场景](../../apps/mobile/integration_test/identity_device_scenarios.dart)，R09／R10 验证首次合法昵称草稿、组合输入不覆盖持久草稿、账号隔离及原键结果核对，映射 X04／X05／X08。授权和身份 API 为测试提供者；完整 App→实际 C/V 与物理 IME／辅助服务仍未验，未来公开业务消费者仍未实现。
- N03／B01／A09：R08 Dart9项和 Android codec5项本轮通过；系统 Passkey 仍 BLOCKED。实际 RP、Android 发布签名／origin与 assetlinks、Apple Team／Bundle及 AASA／关联域需要提供并部署；codec 不代表系统绑定／恢复。
- N02：R06／R09 仍 BLOCKED，无 macOS／完整 Xcode与iOS设备，本轮未执行原生构建、Keychain、双进程或 AuthenticationServices。保留旧 marker／codec 原版本范围。

准确构建和探针命令见[平台报告](auth-privacy-platform-acceptance-validation-report.md)、[本机环境](local-test-environment.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。跨进程 runner 新增可选 `-PubCache <专用缓存绝对路径>`，两APK使用同一 namespace／签名，保留应用后显式 force-stop，不能中途卸载或清数据。源码指纹包含 Android／iOS／设备测试与资源；旧 AC04 后端指纹不重写为当前全平台通过。

## 历史记录与验收目录

以下记录保留原日期、版本及证明范围；“缺Flutter／未验／未提交”只描述当时状态，现行结果见顶部入口和机器台账。

> **2026-10-03 本机接续验证（历史）：**从远端codex/auth-privacy-handoff的87e603c3f54b2fc08d1501dd3a0d7db5b70d17cc拉取。AC04的B02 R03/R05测试源码已补；**Go全量SQL/race/vet、四份OpenAPI完整校验及R03实际非owner C/V HTTPS/mTLS进程验收通过**。R03覆盖身份CRUD、成功和拒绝回执、实际服务重启、Gate冻结/恢复后新会话核对、迁移10→11及缺表/缺DML拒绝。实际启动发现权限检查format()参数未指定类型，已补$1::text并通过实际进程和匹配race/vet复验。Go位于WSL /usr/lib/go-1.22/bin；PG/Docker可用，固定Goose仅在本次临时目录构建。**Flutter/Dart入口未找到，R05真实Dart→SQL及设备/原生Passkey仍BLOCKED/NOT_RUN，B02整模块未PASS。**AC01 V Gate、AC02身份整账号关闭仍未实现。逐项结果、失败修复/复验和源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。下方旧机器/版本和缺Go/未补B02测试链描述是历史状态。

> **2026-10-03 远端接续交付：**用户已授权将当前匿名收口材料、运行时／设备／B02源码与测试提交并推送到 `origin/codex/auth-privacy-handoff`，由另一台机器继续。先读[机器接续入口](auth-privacy-machine-handoff.md)，再按[匿名清单 AC01–AC06](auth-privacy-closure-checklist.md)执行；提交／推送不代表缺口已修复或动态验收通过。下方“未提交／推送”是历史记录，最新交付状态以本次提交及远端结果为准。

> **2026-10-03 匿名分支范围纠正：**本分支以匿名方案及其基础实现收口，停在 B02，不进入 B05/B03 等完整业务片。当前有限缺口和结束条件见[匿名收口清单](auth-privacy-closure-checklist.md)：先补 V 独立 Gate、现有身份的整账号关闭联动，再核对隐私边界、补真实测试链与集中验收。B02继续登记为“基础管理已实现，业务联动待实现”，动态／设备未执行项保持待验；本段覆盖下方历史开发顺序，不改写历史测试证据。

登记日期：2026-10-03（Asia/Shanghai）。用户最新要求先完成匿名分支收口；此前允许开发先行、集中按模块验收的安排继续有效，但不授权扩大到完整业务片。最初盘点仅建立交接；其后本片已写入设备／凭据管理及原生 Passkey 源码，实际轻量检查与未执行验收分别登记如下，未下载大型工具。

> **上一功能片：**按[设备与恢复凭据管理＋原生 Passkey D0–D6](auth-privacy-device-credentials-passkey-plan.md)实现 B01/N03，并补 A09 的固定受信配置与持久原结果查询。源码完成／编译、SQL和真机验收待执行；用户暂无 RP／签名／Team ID配置。现行[报告](auth-privacy-device-credentials-passkey-validation-report.md)与[机器记录](../../services/api/authlab/device-credentials-passkey-verification.json)标识本片被测指纹和真实命令，不覆盖历史证据。

> **2026-10-03 B02身份管理基础：**本人身份列表／创建／改名／删除、默认头像和我的→设置入口已写入；注册零身份仍能浏览，落实最多3个／不能删最后一个、累计创建及六个月／30天限制。全部访问最终Gate／会话／归属复核，账号串行及成功／拒绝终态回执保护未知提交与迟到重试。**基础管理已实现，业务联动待实现；编译、SQL、Flutter和真机验收待执行。**帖内绑定、旧帖／聊天投影随业务模块，自定义头像随媒体实现。见[任务单](identity-management-plan.md)、[报告](identity-management-validation-report.md)、[机器记录](../../services/api/authlab/identity-management-verification.json)和[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。后续按[匿名收口清单](auth-privacy-closure-checklist.md)补齐基础缺口并交付，不进入完整发帖／列表业务片；未提交／推送。

## 1. 使用方式与基线

这份文档是验收入口，不替代各产品模块的规则。机器台账为[模块验收队列](module-acceptance-ledger.json)。每个模块有固定 ID，后续开发和验证均沿用该 ID，记录实现进展、实际执行结果、失败原因和待补证据。仓库根[AGENTS.md](../../AGENTS.md)已要求每个功能任务单实现结束前同步本交接与台账，列明未测模块、原因和测试入口；延期验收不扩大当次开发范围。

当前分支为 `codex/auth-privacy-handoff`，实际 checkout 为 `/Users/zewbao/Desktop/workspace/Hnuhole/remote-auth-privacy-handoff`，HEAD 为 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`。C/V runtime、正式迁移、worker、目录与移动端续期有大量未提交改动；HEAD 单独不能标识当前代码，台账另记源码指纹。开始验收前应先固定实际被测代码版本；含未提交改动时同时登记指纹，修复后重新记录并复验受影响模块。

用户报告新认证登录后真实目录能够加载。此处保留该功能完成声明；当前本地[运行时报告](auth-privacy-runtime-business-integration-validation-report.md)及[机器记录](../../services/api/authlab/runtime-business-integration-verification.json)仍是 `IMPLEMENTED_IN_WORKING_TREE_DYNAMIC_ACCEPTANCE_PENDING`，没有本轮编译／SQL／真实进程通过记录。因此本台账不将功能完成声明转换为自动化验收 PASS。

2026-10-02 本轮只读工具盘点：Go／gofmt、Docker、PostgreSQL 命令、Goose、sqlc、oapi-codegen、Flutter／Dart 均不在 PATH。大运行时／专用缓存／APK此前已按用户要求删除。本台账不要求重装第二台电脑：工具齐全后同一电脑即可运行隔离 C/V 数据库、API、Dart 和多数故障测试；iOS 全部原生验收另需完整 Xcode，设备项按所具备手机／模拟器登记。

可以延期集中动态／设备验收。后续开发仍同步保留或补充测试源码；有可用工具时做相应编译／静态检查与聚焦回归，缺工具就记录未执行。新增受保护读写必须沿用 Gate 最终授权事务，不能以“以后测试”为由改为旧认证回退或跳过授权。未验收功能不计为可发布完成，生产放行需相关模块及跨模块链路通过。

## 2. 状态定义与验收顺序

实现状态与验收状态分开维护：

| 状态 | 含义 |
| --- | --- |
| 代码已有／当前待验 | 实现或测试源码存在，当前版本未取得充分运行证据 |
| 历史通过／当前待复验 | 历史指定基线有隔离证据，当前改动仍需回归；历史报告保留不改 |
| 部分实现／待开发再验 | 有骨架或辅助接口，但模块流程未完整接通 |
| 尚未实现／待开发再验 | 只有规则／图稿／规划，不能当作“只差测试” |
| 生产证据待验 | 开发测试不能证明的运营、灾备、发布或独立审计边界 |

每次执行结果只填 `PASS`、`FAIL`、`BLOCKED`（工具／环境不具备）、`SKIP`（测试主动跳过）或 `NOT_RUN`。`BLOCKED/SKIP/NOT_RUN` 不算 PASS。一个模块只有所需层级和关键场景都有对应证据，才能把本次验收改为通过；设备编译、内存替身、handler fixture 与真实 cmd／原生运行各有独立证明范围。

以下保留全产品验收目录；本分支只执行匿名收口清单映射的模块，B05–B12的完整业务实现与验收留到后续。本分支 P01 先实现后验，不能等全部业务再补。验收按依赖执行，不要求一个模块重新创建一套大环境：

1. A00 → A01/A02：编译、契约、迁移权限、服务配置／TLS。
2. A03–A10：认证安全与持久任务；A04 的开发资格测试不替代 P01 的 V Gate。
3. A11/A12/B03：真实目录、客户端持久续期及入口树。
4. A13：跨 C/V、客户端、实际进程的综合链路。
5. N01/N02/N03 与 B01：原生安全存储、完整 app、原生 Passkey／管理流程；不同 OS 分别登记。
6. B02–B12：身份及内容、互动、聊天、通知、治理与排行，按下方业务依赖推进。
7. P01–P06：安全与生产边界，最后再验完整发布版本和跨模块故障链路。

一个公共 runner 可为多个模块提供证据，但要逐模块注明执行了哪些场景，不能只填“全套命令退出0”。当前三个 runner **没有** `--module`／`--run` 选项，不能凭空给它们传参数；默认运行一次完整 suite 后按模块归档。需要单模块 SQL 定位时，验收会话应复用现有临时库建立／保护／清理流程，在库销毁前运行顶层 test 选择；该筛选封装目前尚不存在，不能拿普通无 DSN 的 `go test -run` 当 SQL 通过。

## 3. 已有代码的验收队列（A00–A13）

表内 runner 编号 R00–R09 在第7节给出准确命令。列出的测试文件是入口，不承诺已覆盖下面全部场景；验收人须逐项映射实际用例，缺用例时补充测试或明确的故障注入证据。

| ID | 模块与当前状态 | 主要已有测试／源码入口 | 验收入口／依赖 |
| --- | --- | --- | --- |
| A00 | 工具、编译、协议向量、契约与生成链；历史部分通过，当前待验 | `protocol/protocol_test.go`、`password_test.go`、`cmd/authdev/main_test.go`；[OpenAPI README](../../packages/openapi/README.md)、[sqlc配置](../../services/api/sqlc.yaml) | R00/R01；所有后续模块前置 |
| A01 | 正式迁移、权限、旧认证退役；代码已有，首次动态待验 | C `migrations/0003`–`0011`、V `verifier-migrations/0001`–`0003`；`infra/postgres`；[runtime runner](../../services/api/authlab/run-runtime-isolated.sh) | R03；依赖A00 |
| A02 | 实际 C/V 服务、配置、HTTPS／mTLS、开发引导；代码已有，实际 cmd 待验 | `authprivacyruntime`、`cmd/api`、`cmd/verifier`、`cmd/authdev`；`tls_test.go`、`peer_test.go`、`endpoints_test.go` | R02/R03；依赖A00/A01 |
| A03 | C Safety Gate、可信时间、持久冻结和恢复；历史隔离通过，当前待复验 | `authorization_gate_test.go`、`authorization_evidence.go` | R02/R03；依赖A01/A02 |
| A04 | V OTP、资格、配额、退役与原确认续办；历史通过，当前待复验 | `eligibility_otp_test.go`、`eligibility_confirmation_test.go`、`mail_test.go`、HTTP `endtoend_postgres_test.go` | R02/R03；依赖A01/A02；V Gate见P01 |
| A05 | C 注册、密码准备、槽位、资格与幂等；历史通过，当前待复验 | `postgres_test.go` 的整个 `TestPostgresIsolatedSlice`、HTTP `TestHTTPSPostgresEligibilityAndSignup` | R02/R03；依赖A03/A04 |
| A06 | 密码登录、接替、认证、续期与定向退出；历史通过，当前待复验 | `password_test.go`、`community_sessions_test.go`、HTTP `session_endpoints_test.go` | R02/R03；依赖A03/A05 |
| A07 | 独立恢复码证明、密码重设与未知结果；历史通过，当前待复验 | `community_recovery_test.go`、HTTP `recovery_closure_endpoints_test.go` | R02/R03；依赖A03/A06 |
| A08 | 七天注销、处罚联动、到期关闭及释放；历史通过，当前待复验 | `community_closure_test.go`、HTTP `recovery_closure_endpoints_test.go` | R02/R03；依赖A03/A06/A10；完整治理不是此模块 |
| A09 | 恢复码轮换与 WebAuthn 服务端凭据管理；原结果核对及可选runtime策略已接，当前待验 | `community_credential_result_test.go`、`community_credentials_test.go`、`passkey_verification_test.go`、HTTP `credential_endpoints_test.go`／`credential_endtoend_postgres_test.go`、runtime `webauthn_config_test.go` | R01/R02/R03/R05；依赖A03/A06；真实非owner HTTPS仍待验；原生桥见N03 |
| A10 | 有界 worker、SMTP、收据 claim／签名／ACK、清理；新增部分首次待验 | `workers_test.go`、`eligibility_mail_worker_test.go`、`outbox_workers_test.go`、`outbox_authorization_test.go`、`retirement_authorization_test.go` | R02/R03；依赖A01–A07；与A08联合 |
| A11 | 真实目录、最终授权事务与目录续期；代码已有，当前待验 | `community_authorized_test.go`、HTTP `channel_endpoints_test.go` | R02/R03/R05；依赖A01/A03/A06 |
| A12 | Flutter 核心认证、未知结果／退出待办、目录持久截止；历史通过，新改动待复验 | [六个Dart测试文件](../../apps/mobile/test)、`auth_session_controller.dart`、`auth_store.dart`、目录controller | R04/R05；依赖A05–A11；原生持久性另验 |
| A13 | 真实公共 HTTPS＋PG、实际 cmd＋Mailpit 综合流程；历史部分通过，本轮待验 | [Dart联调](../../apps/mobile/integration/auth_public_https_postgres_test.dart)、Go `TestMobileClientHTTPSPostgres`、`cmd/runtimeprobe` | R03/R05；依赖A01–A12 |

上表未带目录的 Go 文件名：领域测试位于 `services/api/internal/authprivacy`，HTTP 测试位于 `services/api/internal/authprivacyhttp`。历史来源见第9节。

### A00：编译、版本与契约

- Go 格式、所有入口编译、race、vet；不通过时先定位修复，再接其他模块的运行证据。
- 当前声明 Go1.22，Compose固定PG16.6、Mailpit1.21.8；历史Go1.27.1／PG18.6不能外推。记录实际版本；调整最低版本须有依据并同步配置／说明。
- 固定签名字节、弱公钥／无效签名、规范base64url、域／用途／epoch、时间算术和持钥证明；协议向量纯测试能单独运行。
- 三份OpenAPI完整validator、严格JSON／能力头、错误契约与目录生成；`--yaml-only`不替代完整validator。sqlc生成配置存在，但尚无统一wrapper／已提交生成包；用锁定工具检查生成和编译关系后记录，不能宣称已有CI。

### A01：正式迁移与最小权限

- 空库、重复迁移、失败事务回滚；已发布0001／0002不改，临时旧通道升级保留全部字段／UUID／code。
- migration owner、runtime、recovery、business角色隔离；无DDL／owner membership；跨方拒绝；sequence权限实际可用。
- 旧 `public.sessions` 不可到达新路由且runtime无读取权；即使旧account_id碰巧相同也不导入资格、密码或真实会话。
- 使用非owner运行连接走全流程；旧authlab的schema-reset owner只能证明故障事务，不能代证本模块。Down不能回退已消费、撤销、关闭或generation事实。

### A02：服务、配置与传输

- 分别启动实际C/V cmd，错误库／结构／角色／配置／用途钥／私钥权限拒绝；区分live与ready，冻结ready503。
- public真实HTTPS、internal真实mTLS；错CA／hostname／peer／过期证书／origin拒绝，转发头不能模拟TLS身份。
- Mailpit真实SMTP收取合成OTP；公开C/V没有开发取码入口，敏感正文／密码／OTP／密钥不写普通日志。
- 停证据源后按TTL拒绝授权；重启复用持久状态、不自动解冻；SIGINT/SIGTERM及请求／worker有界停止。设备SAN与信任链另验，loopback证书不代证设备可连。

### A03：C Gate与灾备

- 5秒回退容忍、5分钟证据TTL；缺失／坏签名／旧证据／过期／高水位不一致全部持久冻结。
- 多连接／副本、锁等待、旧数据库快照、锚点落盘失败、SQL提交未知、请求取消；冻结不得被业务rollback或断线抹掉。
- 单受限恢复角色按独立签名证据显式恢复，generation推进；旧token／旧权限不能复活；break-glass边界、审计与钥用途拒绝。
- 新增 `TestGateNanosecondClockPersistsIdenticalSQLAndAnchorTimePostgres` 必须实跑，证明最终SQL与锚点时刻一致且归一后不越证据截止。
- 文件锚点只是开发实现；独立运营／外部锚点／真实灾备证据见P02/P03。

### A04：V资格与配额

- 精确邮箱／域与大小写规则、统一受理、幂等、60秒等待、最新码、有效期、发送／校验预算、三错锁及重发不重置。
- OTP消费与配额保留同事务；签名提交后执行；HSM失败／迟到不生成第二资格或延长原有效期。
- 未开户旧槽位退役与原确认续办、另请求先占槽位、重复／错用途收据、ACK丢失、清理不复活已消费事实。
- V目前仍使用DB时间，本模块开发通过不等于可信时间／旧快照恢复安全，后者必须由P01独立实现和验证。

### A05：注册与槽位事实

- 限时资格、严格公钥、真实挑战PoP、恢复码完整确认、用户名竞争、账号＋唯一会话＋槽位＋无秘密结果共事务。
- 注册／退役竞争、不存在槽位锁、锁等待跨截止、同资格重复消费、旧票／旧操作墓碑拒绝。
- 原结果查询不重放Bearer／恢复码；不同负载同键拒绝，未知结果核对不新建操作。
- Gate冻结／恢复发生在准备与最终提交之间时不开户；C不接收邮箱映射，V不得收到用户名／密码／恢复材料。
- `TestPostgresIsolatedSlice` 子用例共享lab且有前序数据依赖，必须按整个顶层test执行。

### A06：登录与会话

- 密码政策／规范化、有界Argon2id工作池、未知用户名KDF行为、取消／容量与错误响应。
- 同账号并发登录只留一个当前会话；旧机401 `session_replaced`；定向撤销旧会话不伤后来新会话。
- 最终trustedAt下认证、≤7天续至本次＋30天、>7天不改、过期不续；不换token，不累计延期。
- 重设、封禁、PENDING_CLOSE／CLOSED、generation推进与会话请求竞争；截止前主动登录取消注销，静默恢复／续期不能取消。

### A07：独立恢复与重设

- 原恢复码／Passkey证明绑定账号、当前凭据版本和唯一重设意图；新意图替代旧意图、旧证明无效。
- 新密码／新码完整确认后原子重设；旧恢复码／全部旧Passkey／全部旧会话废弃，不自动登录、不取消注销、不解除处罚。
- 响应丢失后持久核对PENDING／COMMITTED／NOT_COMMITTED；过期与提交竞争不能误报可重执行。
- 所有意图／结果读写最终Gate；事件写失败／存储故障回滚，留存后旧原POST仍拒绝。

### A08：注销、处罚与释放

- 新鲜密码／当前会话申请、不可变七天截止、撤会话；截止前主动登录取消，到期后不可取消。
- 禁言与封禁边界、缓冲期新封禁、迟到处罚、到期finalizer竞争，取锁后的最终可信时间裁决。
- 关闭清控制凭据、撤会话、槽位终态与释放outbox共事务；V处理旧配额、C本地持久ACK及状态留存。
- 状态能力与身份隐私、重复ACK不改起点、恢复不能重新开放旧号。正式内容清理／通知依赖B模块，不能由当前认证finalizer代证。

### A09：恢复凭据与服务端WebAuthn

- 实际 `authprivacyruntime.Config` 已增加显式 `webAuthn:{rpId,origins,androidOrigins}`，C `server.go` 装配 `WithWebAuthn`，`authdev` 提供显式政策参数；省略配置禁用，V拒绝该配置，HTTP AllowedOrigins不自动当作WebAuthn策略。配置校验／Android规范签名origin测试源码已有，Go未编译；RP及签名身份尚未提供，真实cmd／非owner HTTPS绑定与恢复仍待验。
- 恢复码轮换权限绑定当前会话、新鲜密码原版本与generation；新码一次展示／完整确认；普通变更保留密码、当前会话与其他有效凭据。
- Passkey绑定、移除、数量与最后恢复途径约束；同一目标／同键结果、他人目标不泄露；原管理权限随凭据变化废弃。
- ES256、COSE／CBOR、规范ID、原始clientData、challenge／RP／origin／账户句柄、UP／UV／BE、签名与计数高水位负向测试。
- 可发现恢复只创建受限重设意图，不能直接创建普通会话；挑战一次消费、错误配置fail closed、清理保留永久墓碑。
- `GET /api/v1/auth/credential-change-result` 绑定原会话、原ID与操作键，三态均HTTP200；已知意图的不可逆终止才可报NOT_COMMITTED，缺失或异键不推断失败。新增SQL回归覆盖提交丢响应、锁等待／会话代次／Gate、墓碑及外账号挑战不可阻塞；这些源码未运行。8天后410只显示核对过期，不重放秘密或原提交。
- 合成签名／RP测试不等于系统Passkey能力；N03负责原生真实证明。

### A10：后台持久任务与清理

- 批次／并发／deadline／退避／取消、多worker互斥claim与崩溃恢复；SQL锁外发SMTP、签名／mTLS。
- QUEUED按原摘要推进，外发前持久DISPATCHING；UNKNOWN／DISPATCHING不自动重投；进程重启后同样不重投。
- outbox lease／原generation／CAS；迟到签名／旧claim／ACK不覆盖新状态，不复活已清理任务。
- 冻结在claim前、签名在途、V已处理但C本地ACK前、清理最终提交前分别注入；在途外发无法撤回，已提交V事实保留，恢复只重试原收据。
- ACK起点、服务端最终会话截止、结果墓碑和永久槽位终态不因重签／重启／恢复重置留存。锚点／提交未知等故障需逐项补证，不能只从测试名推断全部覆盖。

### A11：业务目录授权

- `public.channels` 七记录、五字段，完整校验后提交；缺项／重复或非法code／SQL故障返回503，无部分数据、不续期。
- 与撤销／接替／重设／注销／封禁共账号锁、与Gate冻结共最终提交裁决；撤销先提交拒绝，目录先提交本次成功有效。
- 锁等待跨会话到期、处罚截止或generation；规范token字节散列；旧字符串散列／旧表token拒绝。
- 200必须带权威 `Session-Expires-At`、服务端requestId和no-store；400／401／403／429／503按当前契约。冻结＋非法能力仍保持HTTP解析错误优先级。
- 重点现有test：`TestDirectoryRenewalAndInvalidCatalogRollbackPostgres`、`TestDirectoryDatabaseFailureDoesNotRenewPostgres`、`TestDirectoryAccountLockWaitUsesFinalGateAndExpiryPostgres`、`TestDirectoryCommitPrecedesWaitingRevocationPostgres`、`TestDirectoryRejectsLegacyTokenForSameAccountPostgres`、`TestRealHTTPSDirectoryUsesCommunitySessionsAndGatePostgres`。其他并发／故障仍须逐项映射。

### A12：移动端核心与目录状态

- 注册、隐藏后完整重输恢复码、登录、权威启动恢复、持久结果核对、重设、注销状态与未知写入fail closed。
- 退出先持久登出标记再移除Bearer；旧撤销待办不拖住新会话，不删除后来token；账号／部署scope隔离。
- 目录严格解析七节点及UTC截止；同token／requestVersion下先确认安全存储落盘再发布；写失败无节点。
- 登录进行中、换机／退出／新请求后的迟到结果不能发布旧节点或改新token；同token旧响应不缩短已持久截止。
- 401仅清对应会话；503／网络故障及400／403／429保留安全token、隐藏业务并可前台重试；无后台定时保活。Dart替身不能代证原生存储。

### A13：完整链路

- R03验证实际cmd＋正式迁移＋非owner＋Mailpit；R05验证Dart客户端＋真实公共HTTPS＋隔离PG，二者分别保留证据。
- OTP注册→恢复码确认→目录七节点→阈值续期并重启→接替／退出→独立恢复→Gate冻结／显式恢复旧代次拒绝→到期注销／V释放／CACK。
- 失败、响应丢失、进程重启、证据源停止、迟到回调及注销／处罚与业务读取竞争；记录每一段实际执行结果。
- 历史2026-10-01 Dart链路使用503目录占位和内存vault；新fixture使用真实目录但仍是内存vault、handler fixture，不能代证原生或实际cmd。R03也不能代证完整手机app。

## 4. 原生平台队列（N01–N03）

| ID | 当前状态 | 必需验收与入口 |
| --- | --- | --- |
| N01 | Android vault／instrumentation历史编译；新增真实vault登出及两进程探针源码，设备和完整app待验 | R07/R09；`AndroidAuthVaultTest.kt`16项、`AuthVaultProcessRestartTest.kt`外驱探针、[设备test](../../apps/mobile/integration_test/auth_security_device_test.dart)；Keystore丢钥／损坏、锁屏、磁盘满、namespace、多engine、备份／卸载重装、原生确认丢失、真实app杀进程后登出标记和迟到响应；标准完整app构建 |
| N02 | iOS同源SwiftPM/CocoaPods打包已补；macOS marker本片通过，Keychain／iOS链接／完整app待验 | R06/R09；[RunnerTests](../../apps/mobile/ios/RunnerTests/RunnerTests.swift)已替换空example，真实Keychain属性／错误写／两XCTest进程probe源码已有；验首次解锁、Keychain不可用／重装残留、marker同步失败重试、多engine、磁盘错误、进程杀死、备份／恢复。parse不代证类型检查和链接 |
| N03 | Android Credential Manager／iOS AuthenticationServices桥源码已实现，平台关联和真机闭环待验 | R08/R09及[原生包说明](../../packages/auth_passkey/README.md)；Dart9、Android codec/ownership5、iOS codec4项源码；绑定／移除／可发现恢复、UV取消、不可用、跨设备与备份标志、挑战过期、接替／冻结／未知提交。macOS共享codec通过不代证系统sheet |

原生真机连接需显式开发HTTPS入口、匹配SAN/origin与平台信任链；不关闭TLS验证，不为手机调试开放PG／SMTP／Mailpit／内部mTLS。Android跨进程探针为write→force-stop→read、kill-before-replace→read-before、kill-after-sync→read-after，独立namespace；默认instrumentation不自动运行。kill阶段中断是预期，随后read成功才算恢复证据；进程中断不等于设备断电。完整参数见[原生报告](auth-privacy-mobile-native-integration-validation-report.md)。

## 5. 尚未完整实现的业务队列（B01–B12）

本节保留早期业务队列及规则摘要，较新的实现和验收以本页各任务更新、所属分支详情与机器台账为准；早期“尚无帖子／通知／举报主链”不再代表当前源码。B08／B11的帖子举报与最小系统通知阶段1正在本分支集成验证，评论依赖及完整互动／私信仍未完成。其他业务按各自真实交付与证据推进，不用本次更新覆盖其历史结论。

| ID／模块 | 规则与当前实现 | 开发后必须交接的关键场景 | 主要依赖 |
| --- | --- | --- | --- |
| B01 账号安全管理页面 | [账号](modules/accounts.md)／[恢复策略](auth-privacy-recovery-decision.md)；[管理页](../../apps/mobile/lib/src/auth/security_management_screen.dart)／[controller](../../apps/mobile/lib/src/auth/security_management_controller.dart)已接设备、退出、轮换、绑定／移除及原结果核对；Flutter未编译／运行 | R04/R05/R08/R09；controller28场景、widget4、恢复流程与嵌套路由回归源码；新鲜密码、新码一次展示隐藏后完整确认、进程重启原键核对、旧会话记录分流、接替／Gate／迟到围栏、系统Passkey闭环；没有邮箱接管 | A06/A07/A09/A12、N01–N03 |
| B02 预设身份／帖内身份 | [身份](modules/identity.md)；[基础管理报告](identity-management-validation-report.md)，**基础管理已实现，业务联动待实现** | R10：本人CRUD／默认头像、零身份可读、累计与日期、归属／并发／Gate／会话、成功和拒绝终态幂等／未知核对；首次昵称草稿持久恢复。未实现：首次公开操作恢复、帖内绑定及删除后的帖子／聊天／失败任务投影 | A01/A03/A06/A12；业务依赖B05/B06/B07/B08/B09/B10，媒体上传后续 |
| B03 入口／导航／列表／文字搜索 | [导航](modules/navigation.md)，二维树有骨架；feed／搜索未实现 | 无权限无节点；初始五项、拖动到达另两项；树返回与重启／新登录位置；通道feed／分页、返回不跳位；搜索标题正文标签、按通道分组与相关度／最新、无正文预览；分作用域历史去重／20词／换机同步；不可见内容不命中 | A11/A12、B02/B05/B04/B12 |
| B04 通道与自定义标签 | [标签](modules/tags.md)，七通道有代码；标签／筛选未实现 | 一帖一个通道、发布后不改通道；0–3自定义标签、允许空；当前通道多标签AND筛选与清筛选恢复；标签编辑不重发、不跨通道、不复活删除／下架内容；主题屏蔽不纳入首版 | A11、B03/B05/B11 |
| B05 新建帖子／草稿／后台发布 | [新建帖子](modules/post-composer.md)，未实现 | 标题／正文／图片限制与编辑确认保持；草稿按账号持久、重启恢复、保存失败留编辑页；受理任务参数／图片清单固定；未知结果查原任务、取消与成功竞争；退出后已受理任务按规则续办、注销／处罚停止未公开任务；身份删除后草稿可重选、已提交任务不可换身份 | B02/B04、A03/A06/A10、本地业务／媒体存储 |
| B06 帖子详情／赞藏／分享 | [帖子详情](modules/post-detail.md)，未实现 | 正文／评论分界与独立滚动；账号级点赞／收藏去重、失败回退与未知核对；删除扣正确数量；分享与深链登录后直达、外链预览不泄露标题正文；作者身份联系、图片顺序／缩放／主动保存 | B02/B05/B07/B09、媒体、深链 |
| B07 评论与回复 | [评论](modules/comments.md)，未实现 | 实际目标关系、同帖固定身份；分页定位与一层缩进；浏览不自动重排／插入别人新评论；本人成功定位；主评论删整楼／回复删本条；文本／单图；未提交输入离帖清、已受理任务重启核对；删帖后不可发送、失败入口在系统通知 | B02/B05/B06/B08、A10 |
| B08 消息中心／互动／系统通知 | [消息](modules/messages.md)；本分支最小系统通知阶段1正在集成验证，完整互动收件箱／私信／推送未实现，见本页最新B08/B11交接 | 身份切换防串箱、列表不批量已读与详情单条已读；账号／身份范围及资源路由；真实评论失败待阶段2；其余隐藏／置顶／互动、搜索与推送规则按模块后续实现 | B07/B09/B11、A06、推送平台 |
| B09 私信与会话 | [私信](modules/messaging.md)，未实现 | 双向身份对跨帖唯一；首次来源／首次一条文字与图限制；撤回／删除不恢复首发额度；接收端持久后ACK、空间不足不ACK、重启幂等补投；本地历史不由云端恢复；接替不丢旧机文件；两分钟撤回／未知核对；账号级拉黑但前台不暴露其他身份；不对外提供已读／在线／输入信号 | B02/B05、A03/A06/A10、本地存储／媒体 |
| B10 我的／个人内容／设置 | [个人内容](modules/personal.md)，我的→设置→身份／账号安全已接；个人帖子／收藏、黑名单和通知设置仍未实现 | 私有帖子／收藏页签与位置；草稿／发送中／失败／成功卡片不重复；删除身份内容归属规则；全身份收藏共用、原帖删除占位可移除；保存／删除故障；设备／身份／黑名单／通知设置各归属正确 | B01/B02/B05/B06/B08/B09 |
| B11 作者编辑删除／举报／审核／处罚申诉 | [管理](modules/moderation.md)；本分支已有帖子举报／网页审核／必要申诉正在集成验证，完整治理仍部分实现，见本页最新B08/B11交接 | 原工单核对；跨原因同快照合案／并发不重复；双角色与回避、编号最小DTO、独立处罚／有条件恢复、三轮且唯一待审、材料逐批分页；评论与私信证据按阶段2／后续范围 | 全内容模块、A08、独立后台／证据／通知 |
| B12 热度／热榜／浏览量 | [排行](modules/popularity.md)，未实现；权重／衰减等仍待设计收口 | 整5分钟、近7天前20、先过滤后补位；停留不重排、返回刷新失败保留仍有效旧榜；同分稳定序号；正文打开才计数、账号每日去重、作者自看不计；热度排除作者自互动、账号级人数去重、删除／取消后重算 | B03/B05/B06/B07/B11、A10；具体参数实施前核对真正待决项 |

上述是已有规则的测试摘要，限制数值、状态与删除范围以所链接模块为准。后续新增业务需附上真实源码／测试入口；已有任务的实际 runner 以本页对应更新为准，不为尚未实现的私信等业务提供占位验收命令。

跨业务共用场景编号：

- X01：每条受保护读写在同一业务事务最终验证账号、处罚、会话和Gate；客户端显示状态不能代替服务端授权。
- X02：接替／退出／重设／注销／封禁／Freeze先提交则后续业务拒绝；业务先提交可完成该次操作，随后权限失效；取锁后时间与generation裁决。
- X03：所有目标归属与可见性在服务端验证；更换资源ID／账号／身份不能越权或串联面具。普通业务／审核／导出角色无认证材料权限。
- X04：未知提交保持原操作键／任务与参数，查原结果；迟到回调、重复投递、进程重启不重复发布／处罚／计数、不复活已终态任务。
- X05：账号与C/V部署scope隔离，退出／换机／新请求fence；草稿、搜索、聊天、图片与缓存按既定规则保留或清理，旧响应不污染新账号。
- X06：PENDING_CLOSE、正式关闭和处罚期间的新公开写／未公开后台任务按既定边界拒绝；私有数据清理／通知与永久拒重放事实分开验。
- X07：删除／下架／权限变化后列表、搜索、排行、深链、推送预览和本地缓存不能暴露不可访问内容；离线副本范围按产品承诺验。
- X08：容量／断网／锁屏／磁盘满／存储确认丢失时不误报成功、不丢唯一恢复或原操作核对能力；客户端错误分流与前台重试符合契约。

每个新业务模块按相关X编号添加边界测试；不依赖通道目录通过来宣称未来所有业务已经安全。

### 上一片设备／凭据任务的历史交接与重开范围

上一片任务单为[D0–D6](auth-privacy-device-credentials-passkey-plan.md)，被测版本为上述HEAD＋[机器记录](../../services/api/authlab/device-credentials-passkey-verification.json)的工作区指纹。以下均未取得模块验收PASS：Go／Flutter缺工具，数据库与手机验收环境未具备；原生Passkey另缺用户提供的实际RP及签名关联。台账保留历史结果，并重新打开受影响的当前验收。

| 模块 | 本片源码／测试位置及影响 | 实际执行与下一验收 |
| --- | --- | --- |
| B01 | `apps/mobile/lib/src/auth/{credential_management_api,security_management_controller,security_management_screen}.dart`；`test/{security_management_controller,security_management_screen,passkey_recovery_flow}_test.dart`、`auth_api_test.dart`、`auth_screen_test.dart`；设备读、密码复验、轮换／绑定／移除、持久核对、路由与迟到取消围栏 | R04聚焦命令／analyze实际127，BLOCKED；R05未运行。先编译及完整Dart回归，再用R05验证真实SQL／HTTPS；最后R09真机。X01/X02/X04/X05/X08 |
| A09 | `services/api/internal/authprivacy/community_credential_result{,_test}.go`、`passkey_verification{,_test}.go`、HTTP `credential_endpoints{,_test}.go`／`credential_endtoend_postgres_test.go`、runtime `webauthn_config_test.go`、`cmd/authdev/main_test.go`；受信原生策略与原结果核对 | R02的Go实际127，BLOCKED；R03非owner实际cmd未运行。R01政策／签名负向，R02 SQL竞争／墓碑，R03实际配置及R05客户端联调逐项映射。X01/X02/X04/X05 |
| N03 | `packages/auth_passkey/lib`、`android/src/main`、`ios/hnuhole_auth_passkey/Sources`及该包Dart／Android／iOS测试；`tools/configure-passkey-associations.py`和`tools/tests/test_passkey_associations.py` | R08共享Swift codec及5项Python测试PASS，范围仅共享代码／生成器。Dart、Android、iOS类型／链接与系统sheet未运行；实际身份确定后生成并部署关联，按包说明及R09验证两平台。X02/X04/X05/X08 |
| N01 | 新 `apps/mobile/integration_test/auth_security_device_test.dart`，原Android vault16项及两进程探针；pending只存ID／键／摘要，不存新码／证明 | 没有本片Android编译或设备通过记录；R07标准app和原探针、R09真实vault两进程先write再停止app再read。授权API替身仅证明本地启动围栏。X04/X05/X08 |
| N02 | `packages/auth_vault/ios/hnuhole_auth_vault/{Package.swift,Sources}`同源打包、`apps/mobile/ios/RunnerTests/RunnerTests.swift`实际Keychain与跨XCTest进程测试 | R06 marker和Swift parse／podspec语法PASS，仅macOS／语法；完整Xcode／Flutter Framework链接BLOCKED，Keychain设备NOT_RUN。R09再验属性、故障、进程及完整app。X04/X05/X08 |
| A00/A02 | `packages/openapi/community-auth-api.yaml`、runtime `config.go/server.go`、`community.config.example.json`、`cmd/authdev`固定政策 | YAML-only PASS，完整validator缺依赖BLOCKED；编译／生成／actual cmd待R00/R01/R03。CORS不能替代WebAuthn policy；默认关闭，V拒配置 |
| A03/A06/A07/A12 | 新结果读事务最终Gate／会话；`auth_flows.dart`原生恢复与authorityVersion、`auth_session_controller.dart`、`auth_state_codec.dart`／`auth_store.dart`原会话持久核对；目录controller构造初始化同步修正 | 共享边界变化重开R02/R04/R05；Gate冻结、接替／退出／新登录开始、首读／写盘等待／native／HTTP迟到、旧会话不能以新token查结果、重设不登录／不取消注销。Dart替身非设备证据。X01/X02/X04/X05/X08 |
| A13/B03/B10 | `apps/mobile/integration/auth_public_https_postgres_test.dart`、Go `mobile_client_postgres_test.go`丢响应注入；`main.dart`我的入口、认证路由不误弹上层回归 | R05未运行：真实handler／TLS／SQL，仍为内存vault和同进程重建，不代证设备／actual cmd。B03/B10本片仅入口变化，完整feed／搜索／个人内容依然未实现。X02/X04/X05 |

缺失场景与平台版本／部署步骤见本片报告和原生包README；不把测试源码数量计为通过数量。真机需另补系统绑定／移除后恢复、真实锁屏／容量故障、在途接替／冻结、丢响应杀进程及同步换机，不用codec或内存vault代验。

## 6. 安全与生产证据队列（P01–P06）

| ID | 当前缺口／状态 | 需要交接的证据 |
| --- | --- | --- |
| P01 V独立Safety Gate | 已明确另片，尚未实现 | V自身可信时间／高水位、持久冻结、独立证据／恢复钥／generation；OTP／预算／资格／配额／已处理收据／清理旧快照不复活；最终签名与后台边界。不得依赖C恢复信任，需独立设计后实施 |
| P02 生产运营与密钥／授时／锚点 | 同机开发材料已有，真实独立运营证据未验 | V/C独立主体与权限、密钥托管／轮换／撤销、独立可信证据与不可随DB回退的锚点；生产限权和恢复角色；开发watch／文件锁不能代签 |
| P03 真实灾备与留存 | 规格与隔离恢复测试存在，生产操作未验 | 两方真实备份／WAL／日志／材料留存与清理、旧快照恢复／信任撤销／终态核对、最新凭据不可恢复时冻结、ACK起点不可恢复时不重延长；有界演练及实际责任记录 |
| P04 容量、共享限流与隐私侧信道 | 本地限流／KDF工作池有基础，生产校准未验 | 多副本共享预算／限流、KDF并发与时延、真实邮件未知结果受控核对、用户名／邮箱枚举与时延、永久墓碑容量、worker积压与过载；按实际规模负载及故障证据 |
| P05 CI、完整发布、平台与外部服务 | 已有协作/Go/Flutter/SQL/契约CI；PR #16测试签名候选与隔离演练通过，未合并；正式签名／生产端点等未配置 | Android/iOS正式签名／安装／升级；固定端点与平台关联、推送／媒体／本地业务加密等实际集成。候选与宿主CI不代证完整发布；未选的供应商／云区域等仍需实施前设计 |
| P06 人类独立安全评审 | 独立人类评审未完成 | 锁定最终代码／协议／迁移／平台证据包，未参与设计的真实评审者、发现／修复／复验与结论；内部AI／subagent检查不能代替 |

开发可以在这些项目尚未验收时继续推进；生产放行前必须逐项明确完成范围、责任人、证据与残余限制。V Gate是未实现安全模块，不能用“延期验收”替代开发。

## 7. 已有可执行入口

先检查工具及缓存，记录实际OS／版本／文件系统。macOS/Linux可本机运行；Windows服务端、锚点和runner在WSL2 Linux文件系统，不能用 `/mnt/c` 代证持久性。Go执行Flutter的fixture要求同一WSL/Linux的Flutter可执行文件，不能传Windows `.bat`。race需要C编译器与CGO，缺失记BLOCKED，不关闭race代验。

### R00：轻量静态与格式检查

仓库根目录：

```sh
git diff --check
gofmt -l services/api/cmd services/api/internal
sh -n services/api/authlab/run-isolated.sh
sh -n services/api/authlab/run-mobile-isolated.sh
sh -n services/api/authlab/run-runtime-isolated.sh
```

`gofmt -l`只列出需要格式化的文件；输出非空需按被测范围格式化并重新登记代码。shell解析、JSON／YAML和空白检查均不证明编译／SQL／运行行为。最初盘点只做文档复核；本片diff、shell、YAML、Swift parse及Ruby语法已执行，gofmt缺失、Go／Flutter命令退出127，详见现行机器记录。

### R01：契约、生成与不依赖DB的聚焦回归

仓库根目录，使用[锁定工具](../../services/api/README.md)和[OpenAPI依赖](../../packages/openapi/requirements-check.txt)：

```sh
python3 packages/openapi/check-specs.py
sh packages/openapi/generate-channel.sh
sh packages/openapi/generate-channel.sh --check
```

`--check`需要先生成本地baseline；生成物被忽略，证明同契约重生成一致，不是已提交生成物的CI漂移证明。sqlc在 `services/api` 用现有配置执行 `sqlc generate`，还需编译生成包及核对完整迁移可解析；目前无统一生成wrapper，不能声称其已通过。

`services/api` 的纯逻辑／边界聚焦入口：

```sh
go test -race -count=1 -p 1 ./internal/authprivacy/protocol
go test -race -count=1 -p 1 ./internal/authprivacy -run '^TestPassword(PolicyAndNormalization|CapacityAndCancellation)$|^TestWebAuthn'
go test -race -count=1 -p 1 ./cmd/authdev
```

这些不代证SQL或设备。完整测试／vet仍在R02和最终收尾运行。

### R02：隔离数据库／并发／故障完整回归

`services/api`，已有Go与 `initdb/pg_ctl/psql`：

```sh
sh authlab/run-isolated.sh
go test -race -count=1 -p 1 ./...
go vet ./...
```

runner创建私有Unix socket的双库，固定全仓race＋vet，退出停止并删除本次临时库。独立 `go test` 没有正确DSN会SKIP SQL；额外退出0不代证数据库。fixture会DROP认证schema和C的 `public.sessions/public.channels`，仅接受 `hnuhole_c/v` 配对角色／库、非super、Unix socket、`AUTHLAB_ALLOW_SCHEMA_RESET=1`、`AUTHLAB_RUNTIME_TAG`以 `hnuhole_authlab_` 开头且DSN application_name匹配。**不能把运行库TCP DSN、未知持久库或真实用户库传给fixture。**保持 `-p 1`，不同包不可并行reset同库。

### R03：正式迁移／最小权限／真实进程与Mailpit

`services/api`：

```sh
sh authlab/run-runtime-isolated.sh
```

要求已有Go、Goose v3.22.1、Docker Compose、psql、Python3、curl、cmp，以及已缓存 `postgres:16.6-alpine`、`axllent/mailpit:v1.21.8` 和Go依赖。runner不下载；缺缓存记BLOCKED。一次性随机项目／端口／私有目录，实际cmd和非owner角色，自己的升级库／账户／时间fixture，trap只清自己资源。过期fixture不等于等待真实七天。用源码中的明确检查逐项归档A01/A02/A08/A10/A11/A13，覆盖不足另补。

### R04：Flutter分模块与完整Dart回归

`apps/mobile`，依赖准备后：

```sh
flutter pub get
flutter analyze
flutter test test/auth_crypto_test.dart test/auth_api_test.dart --reporter expanded
flutter test test/auth_flows_test.dart test/auth_session_controller_test.dart --reporter expanded
flutter test test/auth_screen_test.dart test/auth_vault_test.dart --reporter expanded
flutter test --reporter expanded
```

聚焦组用于定位，完整test用于最终回归，不因聚焦通过省略完整检查。本片新增管理页widget和认证页嵌套路由回归；入口树尚无独立widget测试文件，B03仍须补完整交互／视口测试。认证测试和目录fixture不能代证全部导航行为。

### R05：真实Dart→C/V公共HTTPS／PG

先从 `apps/mobile` 执行pub get，再从 `services/api`：

```sh
export AUTHLAB_MOBILE_FLUTTER="$(command -v flutter)"
sh authlab/run-mobile-isolated.sh
```

runner固定执行 `TestMobileClientHTTPSPostgres`，由Go fixture生成私有配置并启动Dart。普通Flutter test不跑 `integration/`；直接运行integration缺 `AUTHLAB_MOBILE_CONFIG`会跳过，普通Go测试无Flutter变量同样跳过。不计这些SKIP为链路通过。需要Go、PG宿主工具、同平台Flutter；vault仍是内存替身，实际cmd另由R03证明。

### R06：macOS安装标记回归

仓库根目录，仅macOS＋Swift命令行工具：

```sh
sh packages/auth_vault/test/native/run-installation-marker.sh
```

临时二进制／模块缓存由脚本删除。仅证明marker真实文件系统回归；N02的Keychain、iOS链接、设备和多engine必须另补入口及真实平台证据。

### R07：Android标准构建与已有设备测试

先具备锁定Flutter／依赖、Java17、插件SDK36、标准app所需NDK、adb及专用设备。历史完整app因NDK28.2.13676358缺失而阻断；验收时按当前锁定模板核对实际SDK／NDK，不盲改版本。Windows宿主机可做Flutter／Android，此部分不强制WSL；Go联调仍按R05平台约束。

`apps/mobile`：

```sh
flutter build apk --debug --target-platform android-arm64
```

当前checkout无 `gradlew/gradlew.bat`；先由标准Flutter构建准备wrapper／local.properties等，再在 `apps/mobile/android`：

```sh
./gradlew --no-daemon :hnuhole_auth_vault:assembleDebugAndroidTest
```

Windows宿主PowerShell在同一 `apps/mobile/android` 目录使用Flutter准备后的wrapper：

```powershell
.\gradlew.bat --no-daemon :hnuhole_auth_vault:assembleDebugAndroidTest
```

安装生成的测试APK及所需目标包后，在专用设备执行：

```sh
adb shell am instrument -w \
  -e class org.hnuhole.authvault.AndroidAuthVaultTest \
  org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner
```

跨进程probe具体参数与namespace按[原生报告](auth-privacy-mobile-native-integration-validation-report.md)，不能把默认16项测试当probe也已执行。受限prebuilt-debug旁路不代证标准完整app／release；iOS和release签名命令须由实际配置环境确定，当前没有可直接套用的完整验收命令。

### R08：本片Passkey共享代码与客户端聚焦

仓库根，已有Swift CLI及Python3：

```sh
sh packages/auth_passkey/test/native/run-codec.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests -p 'test_passkey_associations.py' -v
```

本片两项实际PASS，前者只编译共享Foundation codec／ownership，不链接AuthenticationServices；后者5项不发布关联。在 `apps/mobile` 依赖准备后执行本片聚焦：

```sh
flutter test test/security_management_controller_test.dart test/security_management_screen_test.dart test/passkey_recovery_flow_test.dart test/auth_api_test.dart test/auth_screen_test.dart --reporter expanded
```

本片命令实际127（缺Flutter）；完整R04仍须运行。原生包自身Dart9项、Android5项instrumentation、iOS4项codec XCTest准确入口见[包README](../../packages/auth_passkey/README.md)，都不能代证系统Passkey UI。

### R09：本片真机存储与Passkey闭环

在 `apps/mobile`，完整Flutter平台环境及明确专用设备：

```sh
flutter test integration_test/auth_security_device_test.dart -d "${AUTH_TEST_DEVICE:?}"
```

跨进程分别用 `--dart-define=AUTH_DEVICE_PHASE=write`／`read`，同一个唯一 `--dart-define=AUTH_DEVICE_NAMESPACE=native.security.test.<本轮唯一值>`；两次间明确停止app，保留安装数据，read必须不同PID。禁止同namespace并行或卸载／清数据。它直接用原生vault，但授权API是替身；不证明服务端／Passkey。iOS RunnerTests的真实Keychain和两XCTest进程probe环境变量、数据保留及cleanup边界见[报告](auth-privacy-device-credentials-passkey-validation-report.md)。

实际Passkey系统流程暂无自动化真机runner；需按[原生包真机矩阵](../../packages/auth_passkey/README.md)在批准RP／签名关联和真实C环境执行绑定、移除、可发现恢复、UV取消、负向关联、接替／Freeze、提交未知与重启、跨设备。先标准完整app构建及平台链接，再做系统sheet和真实签名闭环，不能虚构通用iOS签名／部署命令。

### R10：B02身份管理基础与共享回归

[任务单I1–I4](identity-management-plan.md)、[本片报告](identity-management-validation-report.md)、[机器记录](../../services/api/authlab/identity-management-verification.json)。保留纯规则 `identity_rules_test.go`、真实SQL `community_identities_test.go`、TLS替身／真实HTTPS-SQL `identity_endpoints_test.go`，以及mobile身份API／controller／formatter／widget测试。日期、成功／拒绝原结果、账号归属和共享codec是本片证明重点。

```sh
# 仓库根，仅结构：当前已有Anaconda的PyYAML 6.0.1可执行
/opt/anaconda3/bin/python packages/openapi/check-specs.py --yaml-only

# services/api；先具备现成Go、PG／Goose工具与明确归属的一次性库
sh authlab/run-isolated.sh
sh authlab/run-runtime-isolated.sh
# 普通无DSN时SQL可能SKIP；不得计数据库通过
go test -race -count=1 -p 1 ./...
go vet ./...

# apps/mobile：用现成Flutter pub get后，完整回归包括身份和原认证／安全页
flutter analyze
flutter test --reporter expanded
```

上述runner没有新增模块筛选参数。R03/R05现有实际cmd／Dart＋SQL序列尚未扩展B02操作，完整联调验收需补相应fixture，不将旧runner通过外推为身份通过。当前Go／Flutter／数据库与完整OpenAPI依赖缺失，编译／SQL／race／页面测试为NOT_RUN；工具启动BLOCKED单列，轻量结构不代证动态通过。Android／iOS验IME、小屏大字／无障碍、同机草稿／待核对意图真实杀进程、401接替、503冻结、安全存储故障和账号切换弹层清空，分别记录设备证据。新增迁移11与非owner权限、共享AuthStore codec和主路由要求A01/A02/A12、N01/N02、B01/B03/B10相应回归；旧SHA通过不代证本片。

B02尚未实现项：B05/B07首次公开操作创建／选择后恢复输入及原子帖内绑定；B06/B07旧内容删除占位；B08/B09本人聊天／备注清理、失败任务投影；B10顶部身份和旧帖列表联动；头像上传／登记留后续媒体。验收队列不能将这些写成“只差测试”。

## 8. 证据登记、修复与资源清理

每个模块完成一次验收后写一份小型记录或在本次统一记录中按moduleId分组，包含：moduleId、被测commit、源码指纹（若有未提交改动）、OS／工具／DB／设备版本、命令与工作目录、退出码、场景／test名称、实际PASS/FAIL/SKIP数量及原因、采用真实边界还是替身、未完成项、相关修复commit／复验结果、清理范围。台账的 `currentResult` 只更新为实际结果，不覆盖历史报告。

同一命令可以引用同一证据文件，不复制大日志；发生失败保留脱敏的最小错误片段、可复现步骤和故障点。修复共享Gate／迁移／会话／存储时重开所有受影响模块及相关X场景，不以修复前SHA的通过记录代证。

开发新模块时至少追加：真实源码／测试路径、实现状态、相关依赖／X场景、可执行命令或“需补测试入口”、延期原因。不要先勾PASS。验收结束更新HANDOFF／progress及本台账，按当次用户指令提交；是否推送／发布另依授权。

只保留测试源码和小型报告／JSON。大型运行时、专用缓存、APK、临时DB、开发私钥、录屏／完整日志按本次可确认归属的清单清理；不得删除测试源码、SDK／AVD、未知卷或用户数据。手工开发库用于重启验证时先保留，销毁只针对自己记录的项目名；不做全局prune。无第二电脑时可在同机分批运行、共用现成工具，并在每批结束清临时产物。

## 9. 历史证据与新会话提示

历史通过只适用于原记录范围／版本：

- [C Gate报告](auth-authorization-safety-gate-validation-report.md)、[Gate机器记录](../../services/api/authlab/authorization-safety-gate-verification.json)。
- [资格／HTTP报告](auth-privacy-eligibility-http-validation-report.md)、[资格机器记录](../../services/api/authlab/eligibility-http-verification.json)。
- [会话报告](auth-privacy-session-lifecycle-validation-report.md)、[会话机器记录](../../services/api/authlab/session-lifecycle-verification.json)。
- [恢复／注销报告](auth-privacy-recovery-closure-validation-report.md)、[恢复／注销机器记录](../../services/api/authlab/recovery-closure-verification.json)。
- [恢复凭据报告](auth-privacy-recovery-credentials-validation-report.md)、[凭据机器记录](../../services/api/authlab/recovery-credentials-verification.json)。
- [移动端核心报告](auth-privacy-mobile-auth-validation-report.md)、[核心机器记录](../../services/api/authlab/mobile-auth-verification.json)：历史78项，不代证原生设备。
- [原生／联调报告](auth-privacy-mobile-native-integration-validation-report.md)、[原生机器记录](../../services/api/authlab/mobile-native-integration-verification.json)：历史目录503占位、内存vault；Android只编译／测试库APK，iOS仅marker／语法。
- [首条隔离SQL报告](auth-privacy-isolated-validation-report.md)、[首条机器记录](../../services/api/authlab/verification.json)：历史槽位／ACK基础。
- [本次runtime实施报告](auth-privacy-runtime-business-integration-validation-report.md)、[本次机器记录](../../services/api/authlab/runtime-business-integration-verification.json)：当前动态验收待执行。
- [本片设备／凭据／Passkey报告](auth-privacy-device-credentials-passkey-validation-report.md)、[本片机器记录](../../services/api/authlab/device-credentials-passkey-verification.json)：共享Swift及生成器检查通过，Go／Flutter／SQL／设备／关联验收待执行。

继续开发时可直接交接：

> 只在 `codex/auth-privacy-handoff` 工作。先读 `docs/design/HANDOFF.md` 和 `docs/design/module-acceptance-handoff.md`／`module-acceptance-ledger.json`。用户允许先继续业务开发，之后集中按模块验收；不要因没有第二台电脑停工，不重下大型工具缓存。按已收口产品规则实现所指定业务模块，同步测试源码与模块台账，受保护访问沿用C Gate最终业务事务；缺工具如实记未执行，不声称通过。保护现有未提交工作，不清未知数据库或SDK。

开始验收时可直接交接：

> 只在 `codex/auth-privacy-handoff`，先核对当前代码／台账与工具。按 `docs/design/module-acceptance-handoff.md` 的模块及依赖验证本次指定范围，优先复用同机已有工具，使用明确归属的一次性库。记录真实边界、命令、SHA／指纹、PASS/FAIL/BLOCKED/SKIP及缺失场景，修复后复验受影响模块；普通无DSN／无Flutter的退出0不算链路通过。验完更新小型证据、模块台账、HANDOFF／progress，清理自己的临时数据与产物；未实现模块先开发，不能直接勾验收。

### 2026-10-03 AC04缺失测试源码接续

R03沿用 `sh services/api/authlab/run-runtime-isolated.sh`，无新增module参数。`runtimeprobe/identities.go`经过实际C/V公共HTTPS和受限runtime角色；注册零身份仍可浏览，同键重放／冲突、改名冷却、最后一个身份拒绝、删除不重置累计创建、字段allowlist、实际服务重启和Gate恢复后新会话回执均有明确断言。runner增加三个身份表的缺表及各必需DML负向启动、版本10拒绝和10→11升级账号／七通道保持；本次R03实际执行通过；Flutter和真机不由R03代证。

R05沿用 `sh services/api/authlab/run-mobile-isolated.sh`。新 `identity_https_scenarios.dart` 使用正式Dart传输／controller与SQL，Go fixture仅在真实handler完成后丢弃响应。CREATE、PATCH、DELETE和最后一个身份拒绝均核对原回执；会话接替时隐藏旧资料并以同账号新会话恢复原意图。vault仍为内存，restartClient仅重建对象，不能记作真实app杀进程／安全存储通过。

A01/A02/A13/B02和X01/X02/X03/X04/X05/X08需要执行对应当前回归；身份关闭和V Gate尚未实现，不由这次测试增补代证。实际已执行与阻塞原因、基线／源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。

## AC02 当前服务端交接：身份整账号正式关闭

任务单：[AC02实施](auth-identity-account-closure-plan.md)。报告：[本轮验证](auth-identity-account-closure-validation-report.md)。机器证据：[固定源码与实际结果](../../services/api/authlab/identity-account-closure-verification.json)。基线 `faf557d` 含未提交 AC01/AC02；当前服务端 133 文件摘要 `300d31ce7526c836473fc372bb6309d85944289d28ab86361300f5bd0c7af07d`。

| 模块／场景 | 实现位置 | 本轮实际执行与边界 |
| --- | --- | --- |
| A08、B02；X02/X06关闭基础 | `internal/authprivacy/community_closure.go`；`migrations/0012_identity_account_closure.sql` | 最终 C Gate 同事务关闭账号／撤凭据／擦活动身份／写释放 outbox；七天缓冲、登录或封禁取消不提前擦除。累计状态、已删墓碑与永久回执保留。R01 SQL/race＋R02 vet PASS；新增 `community_identity_closure_test.go`、`identity_closure_migration_test.go` 共12个顶层用例覆盖0/1/3、4worker、两序CREATE/RENAME竞态、全事务故障、冻结／旧代、RC双删约束和其他隔离拒绝。 |
| A00/A13、A08/B02升级与真实流程 | `internal/authprivacyruntime/server.go`、`cmd/runtimeprobe/identity_closure.go`、`cmd/runtimeprobe/main.go`、`authlab/run-runtime-isolated.sh` | R03 实际 C/V cmd、正式11→12／受限角色 PASS；旧11／缺失禁用触发器拒绝；ACTIVE/PENDING及旧墓碑／counter/receipt保持、legacy CLOSED资料前向修复；实际HTTPS＋Mailpit同邮箱新资格、新账号零身份与新建首身份不继承旧历史。时间等待采用明确专属fixture，非七天／60秒实时间验收。 |
| B02纯投影；X07部分契约 | `internal/authprivacy/community_identity_projection.go` | 纯函数有限3字段，独立全长身份token／统一头像键／闭号优先，R01/R03纯契约断言 PASS；没有公开帖子／聊天投影接口或业务资源reader，不能登记业务联动完成。 |
| A01/A02/A03/A04/A06/A10/P01受影响基础 | 既有认证／会话／双侧Gate／释放源码与相同完整runner | 本轮完整SQL/race/vet及原R03基础回归 PASS；旧AC01证据保留128文件版本，不替代当前133文件。历史客户端／设备结果保留其原版本。 |

当前未执行：R05、Flutter、Android/iOS、系统Passkey和物理设备，因为本片未改移动端源码或公开wire contract，仍需最终匿名收口时按影响范围补验；环境与现有入口见[本机环境](local-test-environment.md)及本文 R05/R07/R09/R10。帖子／评论／聊天和本人本地聊天／私人备注／搜索清理缺完整业务调用者，属于待开发而非只差测试；X06/X07整场景未PASS。AC03隐私／日志与后续契约核对仍NOT_RUN，生产P02/P03/P06另待真实运营／灾备／人类审计。下一收口项为AC03；B02整模块继续BLOCKED，不启动一般业务片。

## 2026-10-05 AC03 测试交接

任务单：[AC03三步计划](auth-privacy-boundary-plan.md)。对应A00/A01/A02/A03/A04/A05/A06/A08/A09/A10/A11/A12/A13、B01/B02、P01；跨模块X02/X06/X07，后续B05–B11不实施。被测版本为faf557d基线的未提交AC03工作区，219文件摘要及实际命令见[机器记录](../../services/api/authlab/privacy-boundary-verification.json)，保留旧AC01／AC02／平台记录。

新增实现位于`services/api/internal/authprivacyruntime/diagnostics.go`、`database_diagnostics.go`与实际server/cmd入口；开发PG日志选项位于`infra/docker-compose.yml`及R01/R05 runner；移动诊断修复位于`apps/mobile/lib/src/channels/{http_channel_repository,channel_repository}.dart`及`src/navigation/channel_directory_controller.dart`。后续DTO／占位／发送任务受理绑定／身份对私信／管理恢复合约见[接入契约](auth-privacy-business-contract.md)，未集成调用者明确列NOT_RUN。

实际执行：R01 `sh services/api/authlab/run-isolated.sh` 内完整Go SQL/race与R02 vet PASS；R03 `sh services/api/authlab/run-runtime-isolated.sh` 实际cmd／正式迁移／受限角色矩阵／unsafe日志配置启动拒绝／真实PG及应用日志探针与AC01／AC02回归PASS。新增Go测试位于`privacy_boundary_postgres_test.go`、HTTP `privacy_boundary_test.go`／`identity_privacy_postgres_test.go`、runtime `diagnostics_test.go`／`database_diagnostics_test.go`（均在各internal包）；新增角色SQL和日志探针位于`authlab/privacy-role-audit.sql`及`privacy-diagnostics-canary.py`。

当前Windows Flutter3.47.5/Dart3.13.4 `flutter analyze --no-pub` 无问题、`flutter test --no-pub` 179项PASS（4项新增于auth_api_test.dart）；WSL R05 `sh services/api/authlab/run-mobile-isolated.sh` 当前真实Dart→HTTPS handler→隔离C/V SQL PASS。两条runner从services/api或用实际路径调用，未添加不存在的module选项。命令环境使用[既有D盘/WSL工具](local-test-environment.md)，数据库全部自建一次性；对外公开DTO尚无消费者，不能把本人接口负向测试代作公众内容测试。

未执行：R07/R09/R10 Android/iOS原生、系统Passkey、物理设备/B02矩阵本轮未重跑；iOS构建/Keychain和实际ceremony仍缺工具/设备/平台配置。B05–B11帖子/聊天/治理调用者及本地聊天/备注/搜索清理尚未实现，无现成完整业务验收入口，需未来模块先实现再补X06/X07。P02–P06真实分权、生产代理/邮件/日志/备份与灾备、独立人类审计需要生产环境/真实主体，当前fixture不能代证。B02继续BLOCKED；后续仅按用户指定AC04集中场景与AC05平台推进，不进入完整业务片。

## 2026-10-05 AC04 测试交接

任务单、测试源码与12组关键场景映射见[AC04报告](auth-privacy-regression-validation-report.md)和[任务单](auth-privacy-regression-plan.md)。基线cbc99b0，当前修改未提交；最新raw／Linux换行摘要和真实执行结果见[机器记录](../../services/api/authlab/privacy-regression-verification.json)。

R01完整Go／一次性SQL／race、R02 vet、R03实际非owner C/V／C12V4迁移升级／冻结恢复／旧快照／身份关闭与同邮箱注册、Linux Flutter analyze及179项测试、R05真实Dart＋HTTPS handler＋SQL均PASS。R05新增V冻结请求／确认／结果拒绝与旧代OTP失效、身份缓冲／取消不变、正式擦除和永久回执保持、重复终结、旧Bearer拒绝及新账号原键NOT_FOUND。R03普通重启在持有两侧一次性Gate行锁、当前授权完成后停机；任意授权中断仍可能安全冻结，需要显式恢复。

影响P01、A00/A01/A02/A03/A04/A05/A06/A08/A09/A10/A11/A12/A13、B01/B02；X02及X06/X07仅当前基础边界。R01主动SKIP opt-in移动测试，R05另跑取得证据。R00契约／生成未跑（输入未变）；R07/R09/R10原生、系统Passkey、物理设备与B02矩阵未跑，iOS／平台关联仍缺配置设备；入口沿用本文件runner表。B05–B11消费者未实现，生产P02–P06仍缺外部事实与独立审计。下一验收为AC05；B02仍BLOCKED。


## PM01 帖子图片服务端（2026-10-15）

| 项目 | 当前证据与边界 |
| --- | --- |
| 实现 | `services/api/internal/postmedia/`、`authprivacy/community_post_images.go`、`authprivacyhttp/post_images_endpoints.go`、迁移0014及精确grants；协议见 `packages/openapi/post-image-api.yaml` 和媒体黄金向量 |
| 真实SQL/字节 | 九图7+2补传、完整清单/散列/尺寸、GIF/WebP原字节、私有受限runtime、取消/禁言/封禁/注销/身份删除/截止清理、原身份重试、竞争围栏；实际文件Gate与限资源Python验证器 |
| HTTP | `post_images_postgres_test.go` 实际loopback TLS+SQL；`post_images_endpoints_test.go` 为严格路由/闭合DTO宿主替身，单独计证 |
| 已执行 | Go72顶层/含子项244全部PASS，Python4、OpenAPI6、全包编译与vet PASS；源指纹/逐用例/重复计数合并见脱敏证据 |
| NOT_RUN | 实际cmd媒体装配、正式Goose旧库前向升级、Flutter上传/持久图片草稿/loader接线、Android API29+设备/原格式相册、iOS、容量/备份擦除/生产安全 |
| 跨模块 | A01/A03/A06/A08/A10/A13、B02/B05/B06/B11与X05；新迁移/授权的scoped回归不升级整模块历史PASS |
| 后续 | 前端按固定双方SHA先解决DTO/摘要/失效差异；独立环境显式配置validator、迁移与grants，再集成验证。评论B07、私信B09未实现，不借用帖子端点 |

复验入口 `services/api/authlab/run-post-images-isolated.sh`，环境与命令见[媒体契约](post-image-media-contract.md)。本轮没有调用Flutter/SDK/ADB/手机，也没有重复TalkBack验收；iOS继续单列NOT_RUN。
