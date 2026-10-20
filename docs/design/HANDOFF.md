# Hnuhole 新会话接续说明

> FEED-INTERACTIONS-UI-01 续办（2026-10-20）：已核实后端[#30](https://github.com/zewbby/HnuHole/pull/30)合入main `c923fa5a`；本分支已整合。大批量摘要上限、FA-D03查看器对比度、普通续期评论窗及旧媒体租约迟到拒绝已修，分析0／移动端580项／查看器116项PASS，独立Max静态复核无阻断。更新后的共享C0021/V0004真实联调7项PASS（50项摘要1963字节、单图/三图、条件赞藏、B账号旗标不变、旧条件412）；2005同签debug已交Android独立补验。待设备响应丢失/迟到写/重试/切账号无阻断及最终head适用CI全通过后，按用户授权转Ready并合并#31，再从最终main重建同签debug候选。无公信CA入口，release/profile真实链路及性能NOT_RUN，保留正式安全guard；不正式发布，前端不操作设备或更新环境。见[本轮收口证据](feed-interactions-ui-finalization-20261020.json)。下方未合并/565/2004为原版本快照。

> FEED-INTERACTIONS-UI-01：2026-10-20，独立 feat/feed-interactions-ui／[Draft PR #31](https://github.com/zewbby/HnuHole/pull/31)，真实赞/藏/评论数与列表详情共享状态已接通；分析0、565宿主、HTTPS/SQL、7张渲染、同签APK限定PASS。360dp缺陷已由Android会话复验修复；2003忙态穿透/失权媒体跳位已修并升Max复核，2004独立0021候选两缺陷已真机复验PASS；FA15设备强丢响应BLOCKED。依赖后端#30尚未合并，main整合/最终CI待完成，2004评论0→2→0及7项只读SQL对照PASS，Android独立报告按各版本范围记录；不合并或发布，不升级完整模块。见[任务](../branches/feat-feed-interactions-ui.md)／[机器记录](feed-interactions-ui-verification-20261020.json)。

> **2026-10-20 FEED-INTERACTION-ORDER-01：后端限定PASS。**新版列表联调复现旧无条件赞藏PUT迟到覆盖取消；独立 `codex/fix/feed-interaction-order` 新增0021私有写版本及 `Interaction-Version`／`If-Interaction-Version`，最终事务内CAS、过期412，同值旧写也旋转，聚合往返不复活旧条件。Go全包/build/vet、11份API、真实SQL/race/TLS 56顶层／115含子项零失败零跳过；见[任务](../branches/fix-feed-interaction-order.md)、[证据](feed-interaction-order-verification-20261020.json)及[契约](feed-backend-contract.md#feed-interaction-order-01未知结果与迟到请求)。独立审查／最终head CI待PR；未合并、未部署。共享测试环境保持已合并444d258／C0020/V0004；正式环境未触碰。

> **2026-10-20 FEED-INTERACTIONS-01 本分支后端限定PASS：**基于已合入 #27／#28 的 main `f3454d1`，用户指定独立 `feat/feed-interactions`；新增0020、账号级幂等赞／藏及批量／单帖摘要，评论数共用既有统计，不改严格FeedPost／旧接口。真实SQL/race/TLS 50顶层／108含子项零失败零跳过、Go全包／11份API通过。前端按[接线契约](feed-backend-contract.md#点赞收藏与评论数接线)独立接入，见[任务](../branches/feat-feed-interactions.md)与[机器记录](feed-interactions-verification-20261020.json)。尚未合并，最终head CI／合并回执以PR为准；不冒充独立成员批准，不扩展收藏列表／通知／热度／私信，未部署或设备／生产验收。下方 #27／#28“未合并”为原送审快照，已由本次核对更新。

> **2026-10-19 FEED-UI-01：**已确认后端 [#27](https://github.com/zewbby/HnuHole/pull/27) 合入 `f1752e1`，独立 `codex/feat/feed-ui` 基于新 main 接推荐／通道／账号屏蔽／真实浏览及自适应单图／横向多图。保留原认证、发帖、评论和图片链路，无私信。本地分析、530项Flutter宿主回归、真实HTTPS/SQL、6张实图与全插件Android构建限定PASS，未合并／部署；[任务](../branches/feat-feed-ui.md)、[验证](feed-ui-verification-20261019.json)和渲染沿各自范围交接，完整 B03/B04/B06/B12、设备及生产结论不升级。

> **2026-10-19 PR #27 复核增量：**同一代理复核接口、迁移、计数、屏蔽与分页，真实复现并修复“去重主键丢失仍放行并重复计数”的P2；新增精确主键启动校验及显式冲突目标，不改0019 SQL与公开契约。修复版 Go宿主/build/vet、11份API、真实SQL/race/TLS 33顶层／70含子项零跳过通过；旧29／61属于原版。见[复核记录](feed-backend-review-20261019.json)与[任务](../branches/feat-feed-backend.md)，修复版最终head CI以PR为准，不冒充独立成员批准；按用户指令不合并、不部署。

> **2026-10-19 FEED-BACKEND-01 本分支交付：**基于最新 main `fc2348f` 的独立 `codex/feat/feed-backend`，新增0019、HEAT-07真实浏览／账号上海自然日去重、跨通道时间稳定游标及账号通道屏蔽（分页前过滤）。旧鉴权、匿名 DTO 与旧接口兼容；Go全量宿主/build/vet、真实SQL/race/TLS 29顶层／61含子项及11份API通过。仅后端分支范围，PR／CI见[任务](../branches/feat-feed-backend.md)与[记录](feed-backend-verification-20261019.json)，未合并／部署。下一前端按[接线顺序](feed-backend-contract.md#前端接入)使用新 `/feed`、账号偏好及正文显示后的 `/views`；不搬入旧UI整包，不扩展其他业务，设备／生产未验。

> **2026-10-19 Gate取消误冻结修复已合入main：**[PR #25](https://github.com/zewbby/HnuHole/pull/25)，`54a6768`。发布前取消不误冻结；发布后以独立限时SQL context收尾，真实故障仍fail closed。真实C/V SQL/TLS复现及修复回归、独立审查和固定head八项适用CI通过；两项Android旧流程明确SKIP。新建测试工具/库已清理，旧APK和恢复归档摘要不变；未部署、未发布、未重验手机，原单次触发因无请求trace仍未确定。见[任务](../branches/fix-gate-cancellation-freeze.md)、[合并回执](gate-cancellation-main-merge-20261019.json)与[清理记录](gate-cancellation-cleanup-20261019.json)。

> **2026-10-19 Gate取消误冻结修复（本分支，尚未合并）：**真实 C/V PostgreSQL 和可信 TLS 断连已复现旧代码故障；发布前取消拒绝且不改检查点，发布后以独立限时 context 完成SQL收尾，真实故障仍冻结。限定本地SQL/race/build/vet及独立只读审查完成，最终head CI/合并待核对。历史单次事件缺请求trace，具体归因仍未确定；不重建Android/不恢复旧环境/不连接手机，旧候选和证据保留。见[任务](../branches/fix-gate-cancellation-freeze.md)与[机器记录](gate-cancellation-verification-20261019.json)。

> **2026-10-19 Android 集成候选已合入 main：[PR #23](https://github.com/zewbby/HnuHole/pull/23)，`b6cc077`，最终head两项CI通过、独立审查无阻断、合并树一致。**产品固定 `1a810944`，普通 APK、新增 C18 恢复及 vivo S18 真实举报→网页处置→App 通知/申诉→独立复核→App 结果/已读限定通过；Gate根因未知事件及正式恢复事实保留，不宣称持续可用或生产。候选/私有恢复材料/证据已留存，手机窗口和服务/3个数据库/构建进程已关闭，Linux SDK/缓存已删除；Windows专属ADB SDK目录删除被自动审批拦截，停用但保留，见[清理回执](../release/android-integration-cleanup-20261019.json)。不再验收/追新main；未部署或正式发布。见[任务](../branches/ci-android-integration-candidate.md)、[合并回执](../release/android-integration-main-merge-20261019.json)及[复现说明](../release/android-integration-reproduction-20261019.md)。

> **2026-10-19 评论举报闭环交付候选：COMMENT_REPORT_CLOSED_LOOP_SCOPED_PASS。** 基于已合入完整评论 #19 的 main，新增0018，将真实主评论/单图回复举报、网页处置、本人通知、原申诉及独立复核一次接通。6项新SQL/race、1项实际Dart HTTPS/网页闭环、45项受影响Flutter/analyze0/bundle、Go build/vet、10份API与Node12通过，独立只读审查无阻断。见[任务/合并状态](../branches/feat-comment-report-moderation.md)、[报告](comment-report-validation-20261019.md)、[机器证据](comment-report-verification-20261019.json)和[契约](report-notification-contract.md)。#18与#19有效证据沿用；失败任务/重试/放弃/移除直接复用#19，仅补验新下架影响。本范围合并后结束，无评论业务待接项；未发布/部署，不扩展手机/iOS/Passkey/完整消息中心或生产结论，B08/B11整体PARTIAL。以下旧“第二阶段待评论接入”等保留原版本历史。

> **2026-10-19 评论开发已合并交付并结束。** 用户明确授权“完成合并交付，结束评论开发”；[核心 #17](https://github.com/zewbby/HnuHole/pull/17)（`3e0cc02`）→[业务接通 #19](https://github.com/zewbby/HnuHole/pull/19)（`2da7cdf`）已依次 Squash 合入 main。#19 普通整合 #17 实际 main 后，完整文件树与已实测 `d1b83c5` 一致；送合 head `ad0a9c0` 的全部适用 CI 通过，57项产品输入指纹保持一致。详见[合并回执](comments-main-merge-20261019.json)、[接通报告](comments-connected-report-20261019.md)及[独立审查](comments-connected-review-20261019.json)。页面、原生已提交任务持久化、单图、点赞、删除、失败恢复和真实失败通知数据源均已进入主线，迁移链为0001..0017。Android限定验收结论保持；B07全平台/生产仍为PARTIAL，iOS、跨设备Passkey及新增评论实体TalkBack/多机型矩阵留后续独立授权，未发布。当前评论开发任务关闭，下方各阶段记录保留原版本历史。


> **2026-10-18 评论文字后端增量：BACKEND_TEXT_SCOPED_PASS。**[Draft PR #19](https://github.com/zewbby/HnuHole/pull/19) 堆叠于核心 #17；已正常整合 main `1b78f42` 的真实治理0015，正式评论0016及空库/升级/Down拒绝、真实PG/受限角色/TLS HTTP/重试放弃/封口/生命周期针对性检查通过。被测后端 `07911ab`，完整B07仍BLOCKED、通知provider未接入；本轮不推进客户端/图片/原生日志/设备。见[报告](comments-backend-text-report-20261018.md)、[机器记录](comments-backend-text-verification-20261018.json)与[后端任务](../branches/feat-comments-backend-text.md)。独立成员审查与最终head CI待PR核对，未合并/未发布；下方“0015尚未合入”等为原日期历史快照。
> **2026-10-19 已确认合并 main：**[PR #16](https://github.com/zewbby/HnuHole/pull/16) 经本session用户明确授权转正式送审并普通 Squash Merge，提交 `32cb87b73e2feb518e1c5ec75ea11bb4d3414df1`（上海时间10:13:17）。文件树与已测最终head `a6f8f60` 完全一致，八项最新检查全SUCCESS；独立agent审查无阻断，无GitHub成员批准，不伪造批准或绕过规则。候选构建、同机隔离恢复/回滚与vivo S18最小文字/单PNG限定证据已进入主线；未正式发布，P03/P05完整生产结论不升级。手机窗口已结束，不再ADB；跨设备Passkey、iOS及报告列出的未验范围继续保留。见[合并回执](../release/android-prerelease-main-merge-20261019.json)及[任务详情](../branches/ci-android-prerelease.md)。以下待合并/draft/NOT_RUN条目保留为各自版本和时点的历史快照。

> **2026-10-19 手机实测完成：**8691eb4测试包在vivo S18 / Android15 API35通过本轮11项限定检查：正常UI合成注册/恢复码确认、中文身份输入、文字及单PNG发布/读回、大图/Gal原字节保存、跨进程会话保留、退出后密码重登。输入截短导致的一次错误登录及旧个人路由失效观察如实保留；未改认证/业务代码。用户明确授权后才移除旧签名同包及本机数据。自有临时媒体、两条reverse、ADB5049及后端均已收回，窗口已结束，不再ADB。详见[手机报告](../release/android-device-validation-20261019.md)及[机器记录](../release/android-device-validation-20261019.json)。不升级完整原生安全/Passkey/多图/TalkBack/生产结论，iOS及跨设备Passkey继续延期；PR #16仍未合并/发布。

> **2026-10-19 较早准备快照（下列NOT_RUN属于实测前）：**8691eb4独立SDK/签名/pinned-CA debug包构建验签PASS，绑定14f5096的lab-09（schema15）C52045/V37073；用户当前不能测。没有ADB/手机操作，安装和原生/业务链路保持NOT_RUN。准确APK/证书摘要及CA到期见[发布记录](../release/android-prerelease.md)。

> **2026-10-18 预发布主线同步：**核对PR #18已实际合入main `1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`，正式迁移新增0015。下方schema14及PR #18合并前状态保留原版本；本任务14f5096的schema15新环境已通过13项/75摘要/五实例停机，手机包构建验签PASS；受影响CI仍按最终head核对，不沿用旧结果作为新版本PASS。未连接手机。

> **2026-10-18 手机测试包准备：**用户指定vivo S18 / OriginOS 5，目前不能测；仅授权先准备本任务pinned-CA debug包。独立工具/签名、原包名、无历史诊断/DAL声明，不运行ADB或连接手机；实际设备和APK服务链路仍NOT_RUN。端口、证书到期和同包覆盖阻断见[发布记录](../release/android-prerelease.md)。

> **2026-10-18 Android候选与隔离预发布：**[PR #16](https://github.com/zewbby/HnuHole/pull/16) 已实现独立候选CI、测试签名接线、配置/启停/健康和真实恢复/回滚路径，尚未合并或发布。本地0d10719的11项实际演练、60份表/sequence恢复摘要、独立CLI生命周期和Linux6项工具回归PASS；独立CI后台和测试签名release候选6b2927c实际PASS，APK/证书摘要已归档；安装和APK实际服务链路NOT_RUN。见[任务详情](../branches/ci-android-prerelease.md)、[发布记录与复现入口](../release/android-prerelease.md)。同机开发证明不代证P03生产独立运营；本候选手机NOT_RUN、跨设备Passkey/iOS延期，不复用历史手机或旧签名。

> **2026-10-18 举报／审核阶段1：PHASE1_SCOPED_PASS。**产品候选 `aab9a647d9c8310e344bbc767abb5cbdc1045f73` 基于最新已核对 main `986477b`，已提交、推送至[PR #18](https://github.com/zewbby/HnuHole/pull/18)，独立 agent 安全复核无阻断。已有帖子举报→真实网页审核→最小系统通知／必要申诉链通过实际 Dart→C HTTPS→PostgreSQL→浏览器验证。最终聚焦47项零FAIL/SKIP；完整继承回归321项PASS、两个既有独立Flutter入口明确SKIP、不计通过。Flutter439／analyze0／bundle、9份OpenAPI、Node12、Go host／build／vet及产品候选4工作流7任务全部通过。632个产品／测试／配置输入指纹、失败历史及交付head回执方法见[验收报告](report-moderation-validation-report.md)和[机器记录](report-moderation-verification.json)。0015不依赖评论表，评论举报／真实失败provider阶段2仍NOT_INTEGRATED；完整互动、私信及推送未实现。未合并、未部署、未发布，B08／B11保持PARTIAL，手机／iOS／跨设备Passkey及生产未验边界不扩大。 见[任务详情](../branches/feat-report-moderation.md)、[通知契约](report-notification-contract.md)与[模块交接](module-acceptance-handoff.md)；下方旧记录保留各自日期与范围。

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

接续时先通过分支记录核对 PR、主线漂移及交付状态；实际通过范围以本轮机器记录为准。下方主线业务交付与历史日期记录原样保留；它们各自的“当前／本轮”只描述原时点，不覆盖上述候选状态。

> **2026-10-16 图片集成分支已退役：**`codex/post-image-integration` 本地/远端已删除，交付与 iOS 待办保留于[分支详情](../branches/post-image-integration.md)。电脑清理82处约22.52GiB，剩余工具/生成文件/新建清理密钥profile删除被自动审批拒绝；手机41图和5包已清、专用连接已关闭，电脑不得记作全部清理完成。详见[退役回执](../branches/post-image-integration-retirement-20261016.json)。

> **2026-10-16 已合并 main：**PM01/IV01 帖子图片任务经 [PR #2](https://github.com/zewbby/HnuHole/pull/2) 合并，主线提交 `4fc19baf8655da4b012a0a6dd2c8c9a7b2bab398`，送审提交 `2f46700`，来源 `codex/post-image-integration`（f30e8ae）。本任务的独立组件、帖子选图上传、真实前后端联调和 S18 Android 约定范围已交付；本任务功能范围剩余 iOS（原始选图未实现、入口关闭，macOS/Xcode/iPhone 原生与设备验收待完成）。GitHub Flutter 分析0/组件112项/受影响mobile130项/bundle、Go test/build/vet、协作检查均实际PASS；仅宿主CI，不扩充原SQL/手机证据范围。独立agent复审无阻断，不伪造GitHub成员批准。未发布或部署，详情见[合并回执](post-image-main-delivery-20261016.json)。下方旧日期记录保留原时点状态。

> **2026-10-16 合并检查修复：**保留main原协作policy；清理6份继承文件的行尾空格，将两份API测试内嵌TLS私钥改为运行时OpenSSL临时生成并在测试结束删除。仅测试/文档格式变更，产品实现不变；受影响5文件130项实际PASS，产品CI新增Flutter/Go检查。送审快照取最终产品树，不改写既有共享分支历史；GitHub检查与独立审查完成前不记作已合并。

> **2026-10-16 合并交付进行中：**工作项PM01/IV01帖子图片业务，交付源 `codex/post-image-integration`（功能交付1c8ad33、修复fd2e4c0）。本任务除iOS外约定范围已完成；README已列实现、S18证据及iOS原始选图/原生验收剩余。同步main协作规则，使用符合新命名规则的送审快照分支承载相同产品源码，经PR进入main；此时尚未合并、未发布。项目级预算/生产与评论私信另列，既有验证范围不变。

> **2026-10-15 主App帖子图片S18真机联调已完成约定范围：**修复实现 `fd2e4c04f48b29ddda0142660188988c4a655f5f`，分支 `codex/post-image-integration`。实际原生Picker/原图跨进程恢复、九图C/V/SQL上传及缺项补传、失败编辑同任务RETRY、受保护查看、Gal原格式保存与Gallery动画回放、删帖/退出/切账号/迟到隔离取得本轮证据；修复成功核对后残留旧错误提示。最后修改后分析0、相关宿主69、Python守卫15、bundle、Android Debug20263116构建/验签及上机复验PASS。手机窗口结束，系统设置已恢复、自己的App/后端已停、映射已撤；Linux专用私钥/库已清理。Windows清理被自动审批拦截，材料仍保留且私有目录ACL受限，不能写成已清理。iOS原始选图仍未实现，最大资源预算/库存升级/生产与评论私信另列；不重测旧TalkBack、不宣称全模块/双端通过。见[本轮报告](post-image-android-device-report.md)与[机器记录](post-image-android-device-verification.json)。下方旧记录保留各自版本与范围。

> **2026-10-15 主App帖子图片真机验收的非手机准备已完成：**实现 `2eeb19ce87542aed9e0c57874e8d6b3478df946d`，本任务独立kit `E:/Hnuhole-post-media-android-20261015`。新主App/probe两个API29+包构建与验签、分析0、原图宿主10项、离线守卫15项/设备命令守卫4项、专用真实C/V/Goose/受限空PG重启及Windows HTTPS均PASS；自己的后端已停。没有调用ADB或操作手机，PMA01–14全部NOT_RUN，等待另一会话释放；旧组件TalkBack不重测。按用户要求暂留独立APK/签名/空库/工具供直接配合，过期先核就绪清单。见[准备报告](post-image-android-preparation-report.md)、[机器记录](post-image-android-preparation-verification.json)、[集中SOP](../../tools/post-media-android/README.md)。下方旧结果保留原源码和范围。

> **2026-10-15 帖子图片真实前后端联调完成：**联合分支 `codex/post-image-integration`，源码 `31e82df6ad0f8345471705cf78e6e0f463beecfb`（前端075b567＋后端d893378）。真实C/V进程、Goose/受限PG、Flutter生产页面/API/原图草稿/补传/读取/保存resolver，19检查点全部PASS；修复旧上传暂停状态污染新RETRY。当前分析0、完整宿主375（零排除）、后端SQL/race244、Python4/OpenAPI6、编译/vet、Windows bundle与Android原生构建/验签PASS。没有手机或其他会话服务操作；原生业务真机、iOS原始选图、总预算/生产与评论私信另列。见[联合报告](post-image-joint-report.md)和[机器记录](post-image-joint-verification.json)。下方各分支旧记录保留原版本与范围。

> **2026-10-15 帖子选图上传前端已补齐：**实现 `5cd5fdb8f3766bb5ae5840fa7546eda6739fd98c`，最多9图/排序/移除、加密原图草稿、媒体摘要、逐项补传和重启核对已接现有写帖页。最终分析0、完整mobile374项（零排除，含修复后的控制器43项）、bundle及Android API29+原生构建/验签PASS。后端仍固定d893378独立分支，真实C/V/SQL联调和业务手机未验；本轮未操作手机/服务。iOS选图库会重编码原图，原格式选图尚未实现、入口保持关闭，不能只写待验；评论私信/总资源预算另列。见[本轮报告](post-image-composer-report.md)和[机器记录](post-image-composer-verification.json)。下方旧结果保留原版本，不代证当前。

> **2026-10-15 真实帖子图片读取已接线：**前端固定源码 `b5ab3969870daa43b9d40919311d68f1d4cdca61` 对接后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587` 契约；main/通道/我的→详情已装配受保护读取、最长60秒租约、逐个内存缓存释放与原格式保存resolver。分析0、聚焦76项、其余315项及bundle PASS；完整Windows控制器文件43项保留已复现SQLite清理故障，未计PASS。两个源分支未合并/部署，本轮没有手机或服务操作；完整C进程/SQL联调、业务原生构建/真机未验，上传UI/原图草稿/补传恢复与评论私信未开发，iOS独立。见[读取接线报告](image-viewer-post-media-read-report.md)和[机器记录](image-viewer-post-media-read-verification.json)。下方旧钩子/组件记录按原版本与范围保留。

> **2026-10-15 图片前端接入阶段1：**独立 `codex/image-viewer-business-integration`，从已提交社区e0c1280接入原图片包bd7458a；现有通道/我的→帖子详情已接图片loader钩子、等尺寸预览和独立查看路由，撤销/删除/迟到与返回位置有宿主证据。生产尚无真实图片接口，评论/私信未开发，MIV14仅部分实现。新会话负责帖子图片业务，不编辑社区验收目录/服务/手机；见[阶段1报告](image-viewer-business-stage1-report.md)、[机器记录](image-viewer-business-stage1-verification.json)和[新会话prompt](image-viewer-media-next-session.md)。分析、聚焦34项、其余290项回归、bundle通过；完整Windows回归的SQLite清理errno32已在未改动基线复现，未冒称全套通过。下方历史各按原版本与范围理解。
> **2026-10-15 帖子图片后端独立交付：**分支 `codex/post-image-media`，从已提交社区 `e0c128033682923d519ea99546d72503b085a99e` 在独立 clone 实现真实 SQL 原字节存储、最多九张不可变清单、单项短期补传能力、完整验证后原子公开、受保护清单/原图读取与撤销/清理。Go 72个顶层／含子项244 PASS、Python合成图4 PASS、OpenAPI6份、全包编译/vet PASS；宿主替身与真实TLS/SQL/文件系统范围分列，不代表实际cmd/Goose升级/Flutter/设备/iOS/生产通过。只读参考前端 `a696742f943c1cfe6a5005024dccaf40be752d8f`，未修改或合并其工作区；接线前须处理 imageCount/空正文、新媒体摘要、60秒终止租约。PM01/B05/B06仍为后端已实现／宿主与平台待实现或验收，评论/私信只登记未来契约。见[契约与方案](post-image-media-contract.md)、[脱敏证据](post-image-media-verification-20261015.json)；源码固定提交 efccade441bfc5d453751a3fac74211b090e8129 已正常推送并核对远端；见[交付回执](post-image-media-delivery-20261015.json)，不部署、不发布。下方社区与认证证据保留原版本与范围。

> **2026-10-15 手机窗口当前阻断：BLOCKED_KEY_ISOLATION。**用户已确认 vivo S18、30–45分钟窗口、认证会话释放、隔离包和专用USB key；原stage1实际等待90秒后exit1，未发现目标设备，未安装/启动App、注册或业务写入。Windows环境变量不能证明专用key隔离，已给stage1/2添加不可凭授权flag绕过的前置守卫；CA-A01–13全部NOT_RUN，stage2也阻断。Windows136 PASS＋3 POSIX SKIP、Linux139 PASS仅为host；自有60761 server已按exe/start/port核实后停止，既存5037未动；用户已结束本轮窗口，后续须重新确认。见[本轮报告](community-android-device-blocked-20261015.md)与[脱敏记录](community-android-device-blocked-20261015.json)。历史准备/指纹/APK证据保留原范围；先证明真正独立profile或验证专用key目录的ADB，再由原服务归属方安全释放USB并重验摘要/ready/空库。新增OS账户/安全配置或共享key例外须用户明确变更授权。

> **2026-10-15 第二项非手机准备完成：**任务1/2无冲突，第一项450项输入、APK/签名及待验空库均保持原状。第二项新增实际插件跨进程/本地清理探针、35项原生测试与3组认证中断的精确 runner，三个独立新包/签名已构建核对。新执行mobile322、分析0、Linux136／Windows133＋3个POSIX跳过；199项镜像、manifest/runner/DEX/SQLite均通过。见[第二项准备报告](community-android-stage2-preparation-20261015.md)、[机器记录](community-android-stage2-preparation-20261015.json)和[手机SOP](../../tools/community-android-stage2/README.md)。未用ADB/手机，设备35项、进程/重启、实际账号与IME/读屏全部NOT_RUN；两项材料按用户要求保留，确认设备窗口后继续。任务3/4、iOS与生产仍分别待验。

> **2026-10-15 第一项非手机准备完成：**修复 DELETE 首次核对失败后遗漏 poll 集合，以及 C 确认取消注销后的 UI 完成入口。最后产品修改后 mobile322/R05/F4 通过，真实 server/权限/runtime/vet 通过；新增整段 host 八检查点和最终隔离 Debug/标准未签名 Release 构建通过，实际设备与 IME 仍 NOT_RUN。见[准备报告](community-android-stage1-preparation-20261015.md)和[机器记录](community-android-stage1-preparation-20261015.json)。按用户要求保留专用环境、手机新空库和 APK；未调用 ADB 或创建真实账号/USB key。后续确认设备窗口、隔离包/USB 授权并补真实输入法，任务2–4、iOS和生产分别待验。

> **2026-10-14 当前统一任务单：**用户将双实体Android验证追加到原三项工作之后，顺序为①单机文字社区流程②原生存储与生命周期③系统Passkey及单机回归④双设备NI-X01/NI-X02。见[四阶段统一任务单](community-android-unified-acceptance-plan-20261014.md)。当前只更新计划/交接，没有新增测试或设备操作；单机窗口仍延期，第二设备与两机窗口尚未确认，RP/package/signature关联须另行准备审批。20261013主机/构建证据和其“排除第二设备”保留为原范围历史；新任务整体须四阶段全部收口才通过，iOS/生产和未实现业务仍独立。

> **Git与清理回执：**整合后源码提交`28cee4656edd710d60676a81794c20cd49f45351`（父提交为上述社区保存SHA和固定认证SHA）已正常推送且远端核对一致。此后交接回执仅改文档/台账，443项运行输入未变。三处canonical任务根经owner与进程核对后清理PASS，约11.07GiB逻辑文件、SDK副本/缓存/APK/合成CA及调试私钥均删除，源码、测试、脱敏记录与外部复验脚本保留；不做VHD压缩或全局清理。见[交付回执](community-auth-integration-delivery-20261013.json)。设备仍按用户指令延期，后续须重建独立材料并获得窗口，不能把已删除APK/签名当作可直接安装的制品。

> **2026-10-13 当前联合结果：主机回归及Android构建PASS，设备验收由用户明确延期，任务为部分完成。**整合前20份任务文件已保存并正常推送为`7452dadefb52e7b695cdd1079d21083fcb6cae02`；以用户指定的已提交认证`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`三方整合，保留既定文字页、关闭清理、业务vault、SQL0013/最小授权及锁。联合源码新执行checks（分析0／mobile320）、R05、F4主机8项、server六包race、posts权限9顶层/4生命周期、实际cmd/正式迁移R03的25断言及最终vet均PASS；原生标准Debug/Release ARM64、两测试APK和隔离设备候选构建PASS，实际设备用例全部NOT_RUN。最后4项runner/宿主夹具修改未改变App/Go产品/SQL/协议，受影响检查已重跑；最终443项输入指纹`599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7`。旧311及认证22/0/2不计联合结果。见[联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)、[固定SHA差异](community-flutter-f4-auth-integration-diff-20261012.md)、[单台Android复验清单](community-single-android-acceptance-20261013.md)。仅正常提交/推送本分支；第二实体Android、iOS、完整模块及生产未验，未用ADB/手机。以下旧日期记录保留原范围，不代表当前交付状态。

> **2026-10-12 F4当前验证收尾：固定基线主机子范围PASS，等待最终认证整合。**用户确认后已应用固定后端来源的最小`c_posts`授权补丁（仅新增29行，原认证授权前缀不变），并对最终运行代码完整重跑六stage：mobile分析0问题／20测试文件311项非隐藏测试、R05、F4-H01–H08本轮8项、server六测试包race＋内置vet、posts-privileges九个顶层测试（含受限runtime权限）＋四个lifecycle子项、最终vet均PASS。旧308／旧8项不计本轮；授权前权限FAIL及日志／JSON保留在`logs/pre-approved-grant-rerun`历史归档，不是当前未修复失败。见[本轮报告](community-flutter-f4-validation-report-20261012.md)、[本轮机器记录](community-flutter-f4-validation-20261012.json)及[认证整合差异清单](community-flutter-f4-auth-integration-diff-20261012.md)。

> 独立clone为`E:/HnuHole-community-f4-20261012/repo`；起始SHA与当前HEAD均为`4d58116bdde2c1d2d406b965590bc1625a5c7955`，本轮20个修改文件全部未提交，未推送／合并认证／部署。全部最终检查覆盖授权修复后的282份源码／测试／配置文本，指纹为`186915148fa007eaa5fd2692744adf1af05f500df02b54388270f922d68e7d46`；日志在`E:/HnuHole-community-f4-20261012/logs`。最终认证整合SHA仍未指定，F4 final／FP14继续BLOCKED_DEPENDENCY；手机、原生业务vault7项、实际main插件启动／自动poll、跨原生进程／备份、物理UX及iOS未验，实际部署cmd／旧库前向升级／完整App／生产仍未通过。复验步骤与实际清理结果以本轮报告／机器记录为准。以下授权前及更早记录保留原日期、版本与范围，不覆盖本段当前结果。

> **2026-10-12 F4授权前历史快照：PARTIAL／BLOCKED（已由上方批准后复验取代）。**本轮最终mobile分析0问题、20文件311项非隐藏测试、R05、F4-H01–H08重新执行的8项、server六测试包race及最终vet均PASS；旧308／旧8项不计本轮。`posts-privileges` FAIL：`TestPostSchemaRestrictedRuntimePrivilegesPostgres` 报“required text post schema, hooks or privileges absent”，核对发现社区 `infra/postgres/grant-community.sql` 漏掉 `c_posts` 授权。权限补丁尚未应用，需说明安全配置修改范围并等待用户授权，之后在新一次性库重跑受影响权限／server／vet；当前不能登记完整主机范围PASS或完整App验收。见[本轮报告](community-flutter-f4-validation-report-20261012.md)、[本轮机器记录](community-flutter-f4-validation-20261012.json)及[认证整合差异清单](community-flutter-f4-auth-integration-diff-20261012.md)。

> **授权前历史快照续：**本轮独立clone为`E:/HnuHole-community-f4-20261012/repo`；起始SHA与当前HEAD均为`4d58116bdde2c1d2d406b965590bc1625a5c7955`，本轮修改全部未提交，未推送／合并认证／部署。上述已通过检查覆盖最后运行源码修改，权限失败独立保留；日志在`E:/HnuHole-community-f4-20261012/logs`，最终文件／指纹／退出码以本轮机器记录为准。认证已提交快照仅供差异审查，最终用于整合的固定SHA仍未指定，FP14保持BLOCKED_DEPENDENCY。手机、原生业务vault7项、实际main插件启动／自动poll、跨原生进程／备份、物理UX及iOS均未验；复验步骤见本轮报告。验收目标仍为“当前固定基线在主机范围可复验，等待最终认证整合”，本轮因社区权限缺口仅部分完成。下方历史记录保留原日期、版本与范围。

> **2026-10-10 F4换机交接：**源码`68d35af`已完成固定后端接入，生产根路由真实HTTPS／独立PG／文件SQLite的8项主机检查PASS，补设置“账号与安全”入口。见[报告](community-flutter-f4-report.md)、[机器记录](community-flutter-f4-verification.json)和[换机入口](community-flutter-f4-machine-handoff.md)。F4最终认证候选／FP14仍BLOCKED；早期mobile0问题／308PASS不代证最终全量，最终checks／R05／vet因WSL emergency_ro未完成。F5原生／设备／iOS未跑。一次性PG与进程已结束，但本任务Linux缓存删除errno30、清理BLOCKED；不带缓存换机，不动其他会话。旧F3及认证记录保留原版本与范围。

> **2026-10-09 F3 当前交付：**文字页面、主导航、controller与加密SQLite状态已完成，源码`eb6c914`；[实现报告](community-flutter-f3-report.md)、[机器记录](community-flutter-f3-verification.json)和[实际Flutter复审](ui-reviews/community-flutter-f3-ui-review.md)固定当前证据。完整mobile分析0问题、308项PASS（SQLite30／controller34／screens23含14帧）；F1正式图未改。补未来版本拒绝、旧retry随机迁移、删除丢响应／切账号围栏及Android闭号多engine临界区。真实C/V／SQL整合、Android原生7项／构建／跨进程／设备、iOS及物理UX仍NOT_RUN；下一阶段F4固定最终认证候选，F5另行平台验收。scoped PASS不代证整模块或生产通过；下方F2及认证旧结果均为历史版本。

> **2026-10-09 F2契约／存储设计完成：**见[F2设计](community-flutter-f2-design.md)、[版本锁](community-flutter-f2-lock.json)及[静态记录](community-flutter-f2-verification.json)。基于已发布后端514a944固定14操作、命令/任务/客户端未知三层状态、精确摘要与seal/cancel/retry/delete语义；保持Drift/加密SQLite三表v1、独立业务key和环境/账号scope原字节规则。正式F1资产未改；本轮未导入业务代码、未执行Flutter/SQL/设备验收，不把后端未提交T4或历史PASS移入本分支。F3按锁选择复用源码，补未来schema拒写及删除核对回归，F4仍待最终认证候选。

> **2026-10-09用户纠正／撤回重复改版：**用户明确“这种布局我上面不是已经定稿过了吗”，[刚生成的正常网格v3已撤回](ui-reviews/my-content-aligned-v3.md)。“我的”正常态沿用已定稿本人列表版式，不另做网格、不再列为待评审；F1-11记为已定布局复用，F1-14为定稿通道列表复用，F1-22为删除成功直接返回。当前19个正式PNG场景＋2个已定版式复用场景＋1个无单页返回动作，原22场景已收口，无需继续画图。正式PNG均未修改；Flutter业务／平台NOT_RUN。此前候选／缺口计数为历史。

> **2026-10-09 F1全量出图核对：**见[22场景完整清单](ui-reviews/f1-completion-audit.md)。21个页面场景均已有图；本人删除成功直接返回，无独立页。本轮补齐[我的正常列表对齐v3](ui-reviews/my-content-aligned-v3.md)：置顶首位、统一预览框及对齐页脚，新图仍单列候选；已定稿发布状态与详情不替换。当前19有效正式＋1正常列表候选＋1复用列表流程示例＋1返回动作，没有未画独立页。只图稿与文档，Flutter业务／平台NOT_RUN，不改模块台账；下方版本与数量为历史。

> **2026-10-09最新三图明确确认：**用户本次附正常阅读／身份停用／本人删除确认三图并“要这三张”，F1-19—21按具体附件明确批准，见[三图确认及字节核对](ui-reviews/post-detail-selected-final.md)。附件与三个现有正式PNG逐字节一致，未重画或改色；F1-20／21批准依据从既定无意见规则补强为本次明确确认。统一缩略图与原比例大图、宋体确认问题及删除成功直接返回上一级规则保留，F1-22独立页仍取消。设计数量与实现边界不变：19有效正式、2候选／示例、1无单页返回动作；业务与平台NOT_RUN，不改模块台账。

> **2026-10-09最新：详情收口／删除直接返回。**用户明确图片预览不随原图方向或分辨率改变大小，点开看原比例，并认可[F1-19统一缩略图正常页v2](ui-reviews/post-detail-normal-v2.md)，正式文件已原字节归档。随后要求画完剩余三场景；F1-20身份停用、F1-21本人删除确认依既定无意见规则归档，见[最后三场景记录](ui-reviews/post-detail-states-v1.md)。用户取消F1-22删除后独立页：本人确认且删除成功后直接返回上一级来源页，同步移除内容并保留列表位置，不再经过“帖子已删除／返回列表”页。旧图只保留历史；收藏／通知／分享的已删占位仍不展示正文或评论。F1原22个场景均已有设计处理：21个页面场景已画（19有效正式＋F1-11／14两候选或流程示例），F1-22改为无独立页面的返回动作；没有尚未绘制的独立页面。仅图稿与产品规则，Flutter业务、图片查看、删除与回退、权限／持久化及设备验收NOT_RUN，不改模块台账。当前默认阅读采用本轮白色正式页，历史深色档案及下方旧计数按历史理解。

> **2026-10-09最新：四图附件定稿／F1-19出图。**用户本次附四张原图明确“定稿这几张”，F1-15通道暗蓝成功提示、F1-16我的发布中、F1-17失败草稿、F1-18失败编辑已原字节归档，见[定稿记录与摘要](ui-reviews/post-publish-feedback-selected-v3.md)。本次具体选择优先于此前黑色提示及等高网格候选：两个本人状态按所选错落双列原图，不静默优化或替换；F1-11正常网格与F1-14返回流程示例仍单列候选。点击发布直接回原通道、后台任务及失败草稿仅本人显示、原身份／通道固定、未知结果继续核对。按定稿后同轮继续规则，已应用项目UI技能与imagegen完成[F1-19正常正文详情v1](ui-reviews/post-detail-normal-v1.md)：白色框架、标题左／作者右、正文后3图、紧凑评论／赞藏，DRAFT／已展示。当前16有效正式＋3候选＋3未画，19／22场景已画，剩身份停用／本人删除／已删除占位。仅设计与文档，无Flutter业务或平台PASS；模块台账不改。下方旧计数及网格／黑色描述为历史节点。

> **2026-10-09当前：发布直接返回／本人网格对齐v2。**用户指出独立发布状态页不适合主流程，要求确认发布直接回主页面，发布中／失败放在我的帖子，失败保留草稿＋亮红叹号，成功上部小浮层；又提供小红书本人帖子参考并要求对齐。已应用项目UI技能与imagegen完成[当前6图](ui-reviews/post-publish-feedback-v2.md)：F1-11双列等宽对齐网格、F1-14返回原通道、F1-15顶部小黑色发布成功提示、F1-16本人发布中、F1-17失败草稿、F1-18续写重试。未知与取消核对仍核对原任务，失败重试身份／通道固定。独立状态v1未定稿、已被替代；原My混排v1批准保留历史，当前F1-11改版待评审，空态与删除弹窗仍正式。当前12有效正式＋6候选＋4详情未画，共22场景，已画18场景。只图稿及产品规则，无Flutter业务实现／平台PASS；不改模块台账。下方同日早期18／22记录为被后续反馈修正的历史节点。

> **2026-10-09 F1当前18／22已画：**用户明确“我没给意见就是定稿了，再画一类，一定要应用相应的skill来画图”。我的混排v1和空态v1按授权原图归档，[我的三页](ui-reviews/my-content-states-v1.md)全部FINAL；新评审规则已写入UI流程及项目skill。应用hnuhole-ui-craft、frontend-design、ui-ux-pro-max本地检索、Impeccable Operate参考和内置imagegen完成[发布任务五态v1](ui-reviews/post-task-states-v1.md)：处理中、结果待确认、取消核对、明确失败、修改重试。白色框架、暗灰蓝按钮、固定身份与通道；未知不冒称失败，取消不冒称成功。当前13 FINAL＋5本批已展示／DRAFT＋4详情未画，下一类正文详情4页。本轮仅图稿与文档；Flutter业务未实现、动态／平台NOT_RUN，不改模块台账。下方2026-10-08计数为历史节点。

> **2026-10-08 F1-13正式定稿／弹框字体规则：**用户认可宋体v5并明确“定稿”，正式归档[我的-删除草稿确认](../../UI产品图/我的-删除草稿确认.png)，见[确认记录](ui-reviews/my-draft-delete-confirm-v5.md)。居中两行：小宋体问题“确认删除这篇草稿？”、左取消／右亮朱红确认。后续这类弹框正文尽量宋体，动作按钮不必宋体，已纳入UI流程；不推广全App字体或重画原正式稿。当前11 FINAL＋2 DRAFT＋9未画，共22页；我的混排、空态仍待评审，下一步先收口现有两页，再继续任务5页与详情4页。仅图稿定稿，业务／平台／真实字体渲染NOT_RUN。

> **2026-10-08 F1-13宋体局部修正：**用户限定仅“确认删除这篇草稿？”小一点并用宋体，当前[弹窗v5](ui-reviews/my-draft-delete-confirm-v5.md)已按该要求出图、待评审；两行结构、左取消／右亮朱红确认及按钮字体未改。只作用于本弹窗问题行，不推广全局字体，v1—v4保留历史。仍10正式＋3我的候选＋9未画；社区业务／真实字体渲染／动态与平台均NOT_RUN。

> **2026-10-08 F1-13两行弹窗：**用户明确框内仅两行，第一行“确认删除这篇草稿？”，第二行左“取消”、右“确认”。当前[删除确认v4](ui-reviews/my-draft-delete-confirm-v4.md)按该文案出图，白色居中框／厚重文字／亮朱红确认；具体标题和无法恢复说明已从框内移除，删除仍不可恢复，取消保留。PERSONAL-DRAFT-DELETE-01已同步，v1—v3保留历史，其他我的两图未改。仍10 FINAL＋3 DRAFT＋9未画，新图待评审，业务及平台NOT_RUN。

> **2026-10-08 F1-13当前改稿：**用户对亮色底部删除面板要求“用弹窗吧，别用这种”，现改为[居中弹窗v3](ui-reviews/my-draft-delete-confirm-v3.md)：白色弹窗、目标草稿标题、无法恢复提示，左取消／右亮朱红删除草稿。底部面板v1／v2保留历史，PERSONAL-DRAFT-DELETE-01已按新指令同步，其他我的两图不改。当前仍10 FINAL＋3 DRAFT＋9未出图，新弹窗待评审；业务／平台NOT_RUN。下方底部面板描述按历史理解。

> **2026-10-08 F1身份三态定稿／我的三页出图：**用户明确“身份选择的定稿 然后先画 我的”，F1-08选择v1／F1-09尚无身份v1／F1-10失效v2正式归档，见[定稿记录](ui-reviews/post-identity-and-save-states-v1.md)。随后F1-11[本人混排](ui-drafts/my-content-mixed-v1.png)、F1-12[空态](ui-drafts/my-content-empty-v1.png)、F1-13[草稿删除确认](ui-drafts/my-draft-delete-confirm-v2.png)已出图，见[本批评审](ui-reviews/my-content-states-v1.md)，均DRAFT／待用户评审；删除按钮按用户反馈由暗砖红改亮朱红v2。当前10 FINAL＋3 DRAFT＋9未出图，共22页。本人归档保留自己的帖子／收藏帖子页签，草稿／任务／正式帖同列表；未公开项无点赞，草稿删除按既有底部确认规则，保存失败仍为正式居中弹框。白色框架及暗灰蓝方向连贯，未自动定稿新图或全局主题。本轮仅图稿与文档，Flutter社区业务未实现、动态及平台NOT_RUN，不改模块验收台账。以下旧计数保留历史状态。

> **2026-10-08 F1厚重版正式定稿：**用户明确“用厚重的版本定稿”，F1-07[保存失败v3](ui-reviews/post-composer-save-failed-v3.md)布局及视觉正式定稿，正式文件[发帖-草稿保存失败](../../UI产品图/发帖-草稿保存失败.png)；白色居中弹框、左放弃／右重试、暗灰蓝动作和加强分量以本图为准。当前7 FINAL＋3身份候选＋12未出图，共22页；列表3页、编辑与确认4页全部定稿。身份选择／无身份／原选择失效已画但尚未确认，先评审现有三页，再进入“我的”3页、任务5页和详情4页。图稿定稿不等于业务实现；Flutter社区业务未实现、动态及平台验收NOT_RUN，不改模块台账，不自动推广为全局主题。下方旧计数保留历史状态。

> **2026-10-08 F1-07弹框修正：**用户要求草稿保存失败改为居中弹框，左“放弃”、右“重试”；看过v2后认可布局，同时要求视觉更厚重。当前[保存失败v3](ui-reviews/post-composer-save-failed-v3.md)已加重标题／按钮／边界与阴影，布局已确认、视觉待评审；v1和v2保留历史，其他三张身份候选未改。此指令覆盖原三按钮面板／复制文字入口要求，见POST-DRAFT-SAVE-FAIL-01。整体白色、暗灰蓝方向保持，未自动定稿新配色或本页。当前仍6 FINAL＋4候选＋12未出图；仅图稿与文档，业务实现及动态／平台验收NOT_RUN，下方旧版本按历史理解。

> **2026-10-08 F1当前6定稿＋4候选：**用户对发布确认明确“可以，下一批”，F1-06[发布确认v1](ui-reviews/post-publish-confirm-v1.md)正式定稿，正式图为[发帖-发布确认](../../UI产品图/发帖-发布确认.png)。随后本批已出图F1-07保存失败v1、F1-08身份选择v1、F1-09无身份v1、F1-10原选择失效v2，见[四页图稿与复审](ui-reviews/post-identity-and-save-states-v1.md)，均DRAFT／待用户评审，未覆盖正式稿。沿用白色框架及暗灰蓝动作；失效页两个有效身份均未选中，尚未受理的草稿须重选。当前共6 FINAL＋4 DRAFT＋12未出图；下一类“我的”3张。本轮仅图稿与文档，Flutter社区文字切片未实现、动态及平台验收NOT_RUN，不改模块台账或登记验收PASS。下方旧节点保留历史状态，当前进度以本段为准。

> **2026-10-08 F1第五张正式定稿：**用户看过键盘图后明确“这个可以”，F1-05[文字编辑键盘状态v1](ui-reviews/post-composer-keyboard-v1.md)正式定稿，正式图为[发帖-键盘编辑](../../UI产品图/发帖-键盘编辑.png)。当前共5张定稿：通道三状态＋编辑正常态＋键盘状态，不自动确认全局配色。按既有规则继续F1-06[发布确认v1](ui-reviews/post-publish-confirm-v1.md)，图稿`docs/design/ui-drafts/post-publish-confirm-v1.png`，已出图／DRAFT／待评审；内容按POST-FLOW-01呈现标题／标签／身份，底部固定“确认发布”，不增加预览或额外确认。其余16张未出图，包括第二类保存失败1张及其他四类15张。本轮仍仅图稿与文档，Flutter社区文字切片未实现、业务验收NOT_RUN，无代码或平台验收PASS，不改模块台账。以下定稿与出图记录保留历史状态。

> **2026-10-08 F1第四张正式定稿：**用户看过文字编辑页v1后明确“可以，我同意这个”，F1-04[文字编辑正常态](ui-reviews/post-composer-edit-v1.md)正式定稿，正式图为[发帖-文字编辑](../../UI产品图/发帖-文字编辑.png)。当前共4张定稿：F1-01／F1-02／F1-03通道三状态＋F1-04编辑正常态；此为具体页面定稿，不确认全局主题。按既有指令继续F1-05[文字编辑键盘状态v1](ui-reviews/post-composer-keyboard-v1.md)，产物`docs/design/ui-drafts/post-composer-keyboard-v1.png`，已出图／DRAFT／待评审；其余17张尚未出图，包括第二类确认／保存失败2张及其他四类15张。本轮仅图稿与文档，Flutter社区文字切片未实现、业务验收NOT_RUN，不改模块台账或登记验收PASS。下方为此前定稿及出图历史。

> **2026-10-08 F1第一类正式定稿（历史节点）：**用户明确“定稿这三个”，[v9三状态](ui-reviews/channel-feed-v9.md)登记为F1-01／F1-02／F1-03正式定稿，包含布局与本组三状态配色：白色整体框架、图片／纯文字双列瀑布流、点赞数、当前通道名、搜索、“最新发布＋筛选”、底栏，以及偏暗偏灰的原蓝色UI元素。正式图为[通道最新列表](../../UI产品图/通道最新列表.png)、[通道暂无帖子](../../UI产品图/通道暂无帖子.png)、[通道首次加载失败](../../UI产品图/通道首次加载失败.png)；原v9文件继续保留在`docs/design/ui-drafts/`。本次定稿不等于确认全局主题。v6布局先通过、v9实际图稿曾待评审；林绿／炭黑v7与整页暗蓝v8已废弃，历史稿不得覆盖本次定稿。底栏“首页”回导航树，不新增全通道广场；中央加号仍新建当前通道帖子，热榜继续由搜索进入。按既有指令直接继续第二类第一张[文字编辑页v1](ui-reviews/post-composer-edit-v1.md)，图稿路径`docs/design/ui-drafts/post-composer-edit-v1.png`，状态DRAFT／待评审。完整图稿范围优先于旧Q1隐藏策略，代码分工仍为文字切片；本轮不写代码，Flutter社区代码未实现，业务验收NOT_RUN，无动态或平台验收证据，不改模块台账。下方旧稿与认证记录保留历史证明范围。

> **2026-10-08 F1最新改稿：**用户否定深色单列并要求借鉴小红书；浅色双列v2又被指出对比弱。最新[正常列表v3](ui-reviews/channel-feed-v3.md)使用深墨蓝标题区／浅色信息区增加分量，待用户评审；空／失败状态还未同步新版，不将旧三图视为当前定稿。新指令覆盖旧黑底候选，完整产品范围未扩大。

> **2026-10-08 F1第一类出图：**按用户要求一次交付通道最新列表／暂无帖子／首次加载失败三张v1 PNG，见[图稿与复审](ui-reviews/channel-feed-v1.md)。全部为DRAFT／待用户评审，尚未确认页面或全局配色；没有Flutter实现或动态验收证据。下一步先收取三图反馈。

> **2026-10-08 项目UI技能：**用户提供frontend-design压缩包已安装至本工作树`.agents/skills/`；另固定ui-ux-pro-max和Impeccable的GitHub版本，新增hnuhole-ui-craft入口。见[来源及验证](project-ui-skills.md)与[画图工作流](ui-quality-workflow.md)。以后从规则／真实图稿出发，内部设计卡→单张PNG→看图复审→用户定稿→Flutter映射；营销hero推荐不得代替手机产品设计。本轮仅安装、技能验证、检索试跑及流程编写，未画新图、未实现社区代码、未执行设备验收。

> **2026-10-08 Flutter社区并行计划：**用户授权三个独立任务并行，本工作树 `codex/community-flutter-pages` 只承担第3项。见[前端实施计划](community-flutter-pages-plan.md)：文字编辑／确认、最新列表／正文详情、同机草稿与发布任务混排。已核对产品规则及深色v2参考图，未实现入口按用户授权隐藏；新页面图稿待评审，后端契约及认证候选待固定。本轮仅计划，代码未实现，业务验收全部NOT_RUN。原认证与社区后端分别在自己的工作树推进，下方认证记录保持历史证明范围。

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

下方记录按原日期与版本理解；当前平台范围和阻塞以台账 currentAC05 为准，后端回归保留 currentAC04。

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

## 历史记录与验收目录

以下记录保留原日期、版本及证明范围；“缺Flutter／未验／未提交”只描述当时状态，现行结果见顶部入口和机器台账。

> **2026-10-03 本机接续验证（历史）：**从远端codex/auth-privacy-handoff的87e603c3f54b2fc08d1501dd3a0d7db5b70d17cc拉取。AC04的B02 R03/R05测试源码已补；**Go全量SQL/race/vet、四份OpenAPI完整校验及R03实际非owner C/V HTTPS/mTLS进程验收通过**。R03覆盖身份CRUD、成功和拒绝回执、实际服务重启、Gate冻结/恢复后新会话核对、迁移10→11及缺表/缺DML拒绝。实际启动发现权限检查format()参数未指定类型，已补$1::text并通过实际进程和匹配race/vet复验。Go位于WSL /usr/lib/go-1.22/bin；PG/Docker可用，固定Goose仅在本次临时目录构建。**Flutter/Dart入口未找到，R05真实Dart→SQL及设备/原生Passkey仍BLOCKED/NOT_RUN，B02整模块未PASS。**AC01 V Gate、AC02身份整账号关闭仍未实现。逐项结果、失败修复/复验和源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。下方旧机器/版本和缺Go/未补B02测试链描述是历史状态。

> **2026-10-03 远端接续交付：**用户已授权将当前匿名收口材料、运行时／设备／B02源码与测试提交并推送到 `origin/codex/auth-privacy-handoff`，由另一台机器继续。先读[机器接续入口](auth-privacy-machine-handoff.md)，再按[匿名清单 AC01–AC06](auth-privacy-closure-checklist.md)执行；提交／推送不代表缺口已修复或动态验收通过。下方“未提交／推送”是历史记录，最新交付状态以本次提交及远端结果为准。

> **2026-10-03 匿名分支范围纠正：**本分支以匿名方案及其基础实现收口，停在 B02，不进入 B05/B03 等完整业务片。当前有限缺口和结束条件见[匿名收口清单](auth-privacy-closure-checklist.md)：先补 V 独立 Gate、现有身份的整账号关闭联动，再核对隐私边界、补真实测试链与集中验收。B02继续登记为“基础管理已实现，业务联动待实现”，动态／设备未执行项保持待验；本段覆盖下方历史开发顺序，不改写历史测试证据。

> **2026-10-03 B02身份管理基础：**本人身份列表／创建／改名／删除、默认头像和我的→设置入口已写入；注册零身份仍能浏览，落实最多3个／不能删最后一个、累计创建及六个月／30天限制。全部访问最终Gate／会话／归属复核，账号串行及成功／拒绝终态回执保护未知提交与迟到重试。**基础管理已实现，业务联动待实现；编译、SQL、Flutter和真机验收待执行。**帖内绑定、旧帖／聊天投影随业务模块，自定义头像随媒体实现。见[任务单](identity-management-plan.md)、[报告](identity-management-validation-report.md)、[机器记录](../../services/api/authlab/identity-management-verification.json)和[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。后续按[匿名收口清单](auth-privacy-closure-checklist.md)补齐基础缺口并交付，不进入完整发帖／列表业务片；未提交／推送。

> **2026-10-02 设备与恢复凭据管理＋原生Passkey：**按用户四项要求和[任务单D0–D6](auth-privacy-device-credentials-passkey-plan.md)写入当前／最近接替设备、主动退出、密码复验恢复码轮换／一次展示／完整确认／持久原结果核对，Android Credential Manager／iOS AuthenticationServices绑定、移除、可发现恢复。C runtime固定RP与Android签名来源已装配，新增无秘密结果查询；补真机vault／跨进程、SQL冻结／接替、取消／迟到结果与嵌套路由测试。**源码已有，Go／Flutter／SQL／完整原生链接及真机验收待执行，用户尚无RP／签名关联配置。**本机仅通过关联生成器、共享Swift codec／marker和轻量语法／契约结构。见[本轮报告](auth-privacy-device-credentials-passkey-validation-report.md)、[机器记录](../../services/api/authlab/device-credentials-passkey-verification.json)和更新后的[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。仍只在指定分支，未提交／推送；可以按后续指定任务单继续开发，集中补模块验收，不自动扩大本片。

> **2026-10-02 开发与验收顺序更新：**用户允许先继续完成业务功能，再集中按模块动态／设备验收，无需等待第二台电脑。[分模块测试交接](module-acceptance-handoff.md)和[机器台账](module-acceptance-ledger.json)盘点已有代码的当前待验、原生平台缺口、尚未实现业务及安全／生产证据。仓库根[AGENTS.md](../../AGENTS.md)规定：每个功能任务单实现结束必须更新这两份交接、HANDOFF和progress，明确未测项／原因／入口；代码完成与验收通过分开，不覆盖历史证据。缺工具可记录延期，新业务仍遵守最终Gate事务与权限边界。下方“先补验收再继续切片”的历史顺序由本段更新；当前代码未验状态保持真实，尚未取得新commit。只保留测试源码和小型记录，清理自己创建的大型临时产物。

> **2026-10-02 C/V 开发服务与目录授权实施，动态验收待执行：**只在 `codex/auth-privacy-handoff`、基线 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e` 的 checkout 按[实施计划 T0–T6](auth-privacy-runtime-business-integration-plan.md)写入正式 C/V 迁移、非 owner 运行权限、实际 HTTPS／mTLS 入口、独立开发 PKI／签名恢复工具、有界持久 worker、同事务目录授权与移动端截止先持久后发布。`run-runtime-isolated.sh` 已加入实际 cmd／Mailpit／升级／权限／重启闭环。**本机缺 Go／gofmt、Docker／PostgreSQL、Flutter，未编译或执行动态验收，不能宣布计划完成。**已执行检查与缺失证据见[本轮报告](auth-privacy-runtime-business-integration-validation-report.md)和[机器记录](../../services/api/authlab/runtime-business-integration-verification.json)。代码尚未提交／推送；新会话先在现成工具的电脑执行报告中的格式化、生成及全部 runner，修复失败并更新证据，再进入后续切片。[第40轮](../discussions/2026-10-01-grilling-round40.md)的范围保持：V Gate 另片、只用全新开发库与一次性升级库、Windows 服务端在 WSL2 Linux 文件系统；设备／Xcode 可并行，管理页面／原生 Passkey 留后续。下方历史节点中的“下一步”以本段为准。

> **2026-10-01 原生存储与真实 C/V 联调：**仍只基于 `codex/auth-privacy-handoff`，真实 Flutter→公共 HTTPS→隔离 C/V PostgreSQL 已验证注册、会话、未知结果、Gate 冻结／签名恢复与注销释放 ACK。Android 原生／instrumentation 编译和测试 APK 组装完成，新增 16 项设备故障测试及跨进程探针；iOS 安装标记失败重试和跨 engine 串行已修复，macOS 标记回归通过。设备测试、完整应用构建和 iOS Keychain 尚未验证。用户要求清理大型临时运行时／缓存／APK并推送远端给另一台电脑复验，步骤与边界见[本轮报告](auth-privacy-mobile-native-integration-validation-report.md)和[机器记录](../../services/api/authlab/mobile-native-integration-verification.json)。下一步先补设备／Xcode验收，再接设备／恢复凭据管理页面与原生Passkey；生产业务路由授权接Gate仍待做。

> **2026-09-30 移动端核心认证状态机（历史节点）：**指定分支 `codex/auth-privacy-handoff` 已接入校邮注册、恢复码隐藏后完整确认、密码登录、权威恢复／活跃续期、七天注销和持久结果核对。退出先确认登出标记持久化，再删除Bearer并以独立能力异步定向撤销，旧任务不影响新会话。系统安全存储适配器及Android/iOS工程已加入；完整Dart／TLS／组件回归和Go故障回归见[本轮报告](auth-privacy-mobile-auth-validation-report.md)及[机器记录](../../services/api/authlab/mobile-auth-verification.json)。下一步先做原生构建、真机安全存储故障与真实C/V整链联调，再补设备／凭据管理页面。原生Passkey、生产路由／迁移与业务授权接Gate、注销清理／通知、运营分权及独立安全验收继续待做。

> **2026-09-30 恢复凭据管理隔离实现（历史节点）：**当前分支 `codex/auth-privacy-handoff` 补齐新鲜密码复验恢复码轮换、可选 Passkey 的绑定／可发现恢复／两步移除，以及受限凭据清单。管理权限绑定原凭据版本、同一会话、固定RP策略及Gate代次，最终事务再次复核；普通变更保留其他凭据和当前会话，重设／关闭撤全部旧Passkey。交付与最终验证见[本轮报告](auth-privacy-recovery-credentials-validation-report.md)和[机器记录](../../services/api/authlab/recovery-credentials-verification.json)。下一步进入移动端安全存储、持久结果核对／登出待办及完整认证状态机；生产路由／迁移、真实平台Passkey演练、业务数据清理／通知及生产安全验收继续待做。

> **2026-09-30 恢复码与七天注销隔离实现（历史节点）：**在登录／会话切片之上加入恢复码证明、唯一重设意图、最终密码重设与无秘密结果核对，以及七天注销申请、截止前主动登录取消、到期关闭、受限状态与释放收据。密码重设不登录、不取消注销、不解除处罚；封禁受信命令即时撤会话，迟到封禁不能取消到期申请。新增授权与清理继续经过 Safety Gate。交付范围与证据见[本轮报告](auth-privacy-recovery-closure-validation-report.md)和[机器记录](../../services/api/authlab/recovery-closure-verification.json)。可选 Passkey、恢复码轮换、移动端、业务数据清理／通知和生产接入仍待做。

> **登录与会话隔离实现（2026-09-30，历史节点）：**指定分支 `codex/auth-privacy-handoff` 已在第 0 步 Gate 之上加入私有用户名＋密码登录、单设备接替、权威 Bearer 恢复／同令牌三十天续期、最近替代设备页和独立秘密定向退出。登录、认证读、续期、撤销及清理均在最终事务点经 Gate；并发、冻结、恢复、留存及真实 HTTPS／PostgreSQL 验证见[交付报告](auth-privacy-session-lifecycle-validation-report.md)和[机器记录](../../services/api/authlab/session-lifecycle-verification.json)。这仍是隔离服务端切片。独立恢复／Passkey、七天注销、处罚写入、移动端登出待办及生产接入未做；`PENDING_CLOSE` 登录在注销截止事务接入前 fail closed。生产独立授时、外部锚点、真实灾备与人类独立审计继续待验收。

> **第 0 步隔离实现（2026-09-30，历史节点）：**`codex/auth-privacy-handoff` 已为现有注册、初始 Session 和隔离认证读入口接入 Authorization Safety Gate：5 秒回退容忍、5 分钟签名证据、持久 FROZEN、高水位、库外签名锚点、授权代次、显式受限恢复与离线 break-glass。注册最终事务复核 Gate，旧快照与跨副本故障有真实 PostgreSQL 测试。[交付报告](auth-authorization-safety-gate-validation-report.md)和[机器记录](../../services/api/authlab/authorization-safety-gate-verification.json)注明实验与生产边界。第 0 步完成时登录／会话切片尚未做；其后续进展以上方记录为准。真实授时／库外运营基础设施、生产接入、灾备演练和独立人类审计仍待验收。

> **隔离实现进展（2026-09-29）：**用户已授权进入 Phase E，并明确要求实现校邮确认、退役后的原确认续办及双方 HTTP／mTLS。[实验切片](../../services/api/authlab/README.md)已加入校邮发码／最新码与预算、原子确认／提交后签名、原确认续办、双方独立公共／内部处理器和 mTLS 对端客户端。交付与验证范围见[本轮报告](auth-privacy-eligibility-http-validation-report.md)；首条数据库切片见[历史报告](auth-privacy-isolated-validation-report.md)。尚未接入生产路由／迁移；登录恢复、移动端、可信灾备与运营分权继续待做。“不要编码”是最初架构阶段的要求，已被后续实现授权更新；运营与人类审计是生产放行门槛。

> **第 0 步设计历史（2026-09-29）：**在继续用户名密码登录与完整会话管理前，先实现统一的 Authorization Safety Gate，覆盖可信时间高水位、持久冻结、授权代次、旧快照恢复与最终事务授权复核。第 39 轮四项边界已全部确认：FROZEN 时认证读写全部 fail closed；单个受限恢复角色可按独立证据/显式恢复/generation 推进解冻，不做双人控制；时钟回退容忍 5 秒；可信证据 TTL 5 分钟。正式设计见 [Authorization Safety Gate](auth-authorization-safety-gate.md)。实施进度以上方 2026-09-30 记录为准。

> **认证规格背景（2026-09-28）：**每次注册都验证校邮，之后用私有用户名和独立密码登录；V 按协议执行时，同一精确邮箱地址同时最多一个有效账号。忘记密码不能仅凭校邮验证码接管旧号。正式注销后，社区关闭旧号并释放该地址配额；再次注册重新收码并创建全新账号。[架构决策](auth-privacy-architecture-decision.md)说明隐私边界；公钥导出的资格槽位、限时签名资格、注册持钥证明、未消费资格退役与注销释放见[协议 v1](auth-privacy-registration-protocol.md)。[跨方威胁模型](auth-privacy-threat-model.md)记录内部攻击复核和独立评审门槛。旧 [ADR 0005](../adr/0005-privacy-preserving-email-authentication.md) 和[认证隐私交接](auth-privacy-gpt6-handoff.md)仅供追溯。恢复体验与逻辑数据／API 契约分别见[恢复决策](auth-privacy-recovery-decision.md)和[数据/API 契约](auth-privacy-data-api-contract.md)；[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)、[C OpenAPI](../../packages/openapi/community-auth-api.yaml)及[数据库迁移设计](auth-privacy-database-migration-design.md)已成稿；[固定向量与静态复验](auth-privacy-protocol-vectors.md)、[独立评审输入包](auth-privacy-security-review-package.md)已整理。认证远程分支为 `codex/auth-privacy-handoff`。该规格阶段之后已获隔离实现授权；当前进展以上方本轮报告为准，生产部署与独立安全评审继续待完成。

交接更新：2026-09-25。以下首段保留 2026-09-21 的 UI 交接状态：最新交付[长按对方图片 M v1](../../UI产品图/私信聊天-长按对方图片-配色M-v1.png)，待评审。首轮遇图片额度限制，用户“继续”后重试成功，当前不再受该失败阻塞。黑底灰青，两张同组收到的图片在左，只选中第一张，下面紧凑菜单仅删除／举报；无复制或撤回，删除仅本人单张、举报沿既定授权流程。此前[首发身份选择 L v2](../../UI产品图/私信聊天-首发身份选择-配色L-v2.png)经“下一张”定稿：只缩小弹框内标题和选项，改平面紧凑列表，上方聊天页不变；L v1 字大框大被否决。选择不发送，实际发送才固定帖内身份。I 本人长按、J v2 居中撤回＋重编辑均已定稿；重编辑点击直接回填、不自动发送，不再画 K 回填状态或问替换确认。H 蓝灰是明确配色候选，全局未锁色，后续新页继续协调换色；不能因试色做花哨多色或超大框体。此前 UI 下一步按反馈或继续本人图片长按、图片预览、发送失败等实际缺口，执行 [UI 设计与复审流程](ui-quality-workflow.md)，不附 prompt、不编码。其他状态见[评审记录](../discussions/2026-09-20-replies-ui-review.md)。

> 阶段切换（2026-09-23）：用户暂停 UI 设计讨论并进入工程方案阶段，确认 Flutter/Dart 移动端、Go 服务端和模块化单体后端；架构决策记录见 [ADR 0001](../adr/0001-engineering-baseline.md)，通信与持久化见 [ADR 0002](../adr/0002-communication-and-persistence-baseline.md)。该项为历史工程基线。当前认证已按新规格进入授权的隔离实现，不得使用已废弃的旧认证方案。

### 开发决策进展

- 第一轮：模块化单体、Flutter/Dart、Go，已确认。
- 第二轮：`net/http` + `chi`、PostgreSQL + `pgx`/`sqlc`、REST/JSON + OpenAPI、前台 WebSocket 事件、Drift/SQLite + 系统安全存储，已确认。
- 第三轮：单仓库 monorepo、`goose` + `oapi-codegen`、不透明服务端会话、宿主机 Flutter/Go + Docker Compose、文字内容主链，已确认；记录见 [ADR 0003](../adr/0003-repository-auth-and-first-slice.md)。
- 第四轮：本地 Git + GitHub Actions、Go 单元测试 + Docker PostgreSQL 集成测试、Mailpit + 开发验证适配器、容器化无状态 API + 托管 PostgreSQL + S3 兼容对象存储，已确认；记录见 [ADR 0004](../adr/0004-ci-testing-email-and-deployment.md)。
- Git/GitHub 目前不是用户熟悉领域；后续会用逐条命令说明提交、分支、推送和查看 Actions，不要求用户凭记忆操作。
- 本地 Git 已初始化为 `main`，当前开发分支为 `feature/engineering-baseline`；远程 `origin` 已绑定 `https://github.com/zhubaozhenshuai666-lang/HnuHole.git`，并跟踪 `origin/feature/engineering-baseline`。
- 当前已完成任务 1 的 OpenAPI 契约、PostgreSQL 迁移/七通道种子、认证保护的目录 API、Flutter 无节点入口树和二维可拖动节点骨架；移动端核心认证状态机已按本页顶部记录接入；注册资格、持钥开户、会话与恢复已在独立实验包实现，现有目录 API 尚未接到新Gate授权。当前 Go 会话校验只从不透明会话令牌查社区账号，不含邮箱映射；认证主链须先满足[当前认证架构决策](auth-privacy-architecture-decision.md)的协议与安全评审门槛，不能直接按旧顺序开工。注册不自动创建身份，无身份账号仍可浏览。
- **认证主链前置门槛**：V 校邮验证方与 C 社区方须实质独立；V 持邮箱→本次资格槽位，C 受限认证库持槽位→账号，双方串通可直接关联，单侧隔离承诺以分权为前提。每次注册收码；已有账号以私有用户名＋密码登录，仅能用预设独立凭据恢复。[协议 v1](auth-privacy-registration-protocol.md)已规定限时 `REGISTER/V2` 资格、公钥散列绑定、真实 C 挑战、退役／释放及重放拒绝；恢复、数据／API 和[内部威胁建模](auth-privacy-threat-model.md)已成稿；V/C OpenAPI及迁移设计已成稿；固定签名／弱点负向向量已内部复验，评审包已整理；生产迁移／完整链路、两组织运营安排和独立安全评审仍未完成，不得按旧 [ADR 0005](../adr/0005-privacy-preserving-email-authentication.md) 的稳定匿名凭证流程开工。

## 工作位置与讨论方式

认证规格的最新内部评审见[AI 交叉评审记录](auth-privacy-ai-cross-review.md)：初审固定源 `41fba77` 缺少 `RETIRED` 持久 ACK，当前补入 V 的退役收据入口及 outbox／清理／恢复规则；V 当前 6 个操作，C 22 个。用户确认邮箱可用、C 正式后台未建、暂无人类独立评审者；新上下文 subagent 可做 AI 交叉复核，Claude 的九份固定源材料披露已获用户授权，调用获准但本机 CLI 未登录，没有外部评审结果；用户随后决定本轮先不做 Claude，采用已完成的 subagent 规格评审。不能把内部 AI 结论当作 G6 签署或运营独立性证明；用户后续已授权隔离认证编码；该评审记录不代表生产验收。

- 后续 UI 工作必须同时使用用户指定的 `ui-ux-pro-max`（项目 `.agents/skills/ui-ux-pro-max/SKILL.md`）和 `frontend-design`（`/Users/zewbao/.codex/skills/frontend-design/SKILL.md`），遵循 [UI 设计与复审流程](ui-quality-workflow.md)。已定稿页面若有明确严重问题可后续重画，先记录证据和优先级，保留旧稿、新版另行评审；本次仅确立流程，未全面审计或重画。首次申诉提交 v2 仍待用户确认。
- 项目：`C:\Users\Administrator\Desktop\Hnuhole`。读取顺序：本文件 → [模块目录](README.md) → [进度](progress.md) → 本轮涉及模块全文及[讨论档案](../discussions/README.md)。仓库可能覆盖更大父目录，不做无关目录扫描。
- 用户要求使用 **grill-with-docs**，结合 grilling 与 domain-modeling；docs 是本地设计 Markdown，术语见项目 `CONTEXT.md`。不再机械凑十问，真实未决问题不足十个就少问。
- 先更新本轮模块、进度、交接，再筛选下一轮。每题须有具体场景、建议和所属模块；独立问题不依赖同轮未回答题。用档案与当前规则排重，不能只看到“待确认”三个字就复问。
- 不把已取消的功能、已回答的参数或同一交互的一串琐碎变体凑成新题。尚未提出的功能范围明确标为待建议，不擅自写入已确认。
- 新建议均待回答。用户对题目有修正时，以具体修正为准；原题建议不得冒充用户答复。修改文档已有授权，编码和新图稿须遵循用户当次请求。
- 2026-09-20 用户再次要求 UI 变更同步核查业务逻辑。本次取消逐条收件昵称／本人头像仅撤回展示要求，不改变身份隔离、帖内身份、跳转、未读或失败任务处理。后续若 UI 决策改变行为，须同步所属模块和必要依赖；真实缺口排重后 grilling，不因“业务已收口”而跳过，也不重开无关访谈。
- 中文讨论。图稿优先 PNG，一次一张评审，不使用 SVG/Inkscape 交付。旧稿冰蓝主题不再锁定；当前黑底方向逐页试色，布局基准 402×874，昵称占位用中性名称。每张图先自主设计出图，再由用户微调；不附 prompt，不要求用户先确认文字方案。
- 用户一般讨论偏好 Extra High、作图偏好 GPT-6 Astra Ultra；不能声称切换模型而未执行。
- 首版自定义 #标签选填已确认，不再问标签是否加入。统一中间分类、标签治理和主题屏蔽均不在首版；屏蔽后续版本单独设计。

## 第二十九轮之后的认证与身份补充

- 同一账号在同一帖子只有一个帖内身份。首次实际公开发送前，已有身份的账号选择一个，没有身份的账号先创建基础身份；只打开设置、选择身份或填写输入不绑定。绑定后主评论、所有楼中楼回复和从该帖继续发起的互动直接复用，不再重复设置；服务端按“账号 + 帖子”唯一约束拒绝换身份。
- 身份设置或选择从发帖、评论、楼中楼回复触发时，保留原操作的文字、图片和回复对象；完成后返回原操作，取消则不发布。
- 主动退出撤销服务端会话并清除安全存储令牌，但保留按账号隔离的本机草稿和文件；其他账号不可见，原账号重新登录后恢复。恢复遇 `401` 清令牌和节点回登录／注册入口，遇 `503` 或超时保留令牌和本地状态并重试。
- 新设备以用户名密码登录成功接替旧设备后，旧设备下一次受保护请求收到 `401/session_replaced`，提示“账号已在其他设备登录”，清除节点但保留草稿和聊天文件。
- 客户端认证主链须分别包含 V 的验证码申请／确认、C 的新号注册、用户名密码登录、独立凭据恢复及会话恢复／主动退出；旧“四接口、验证码确认即恢复旧号”设想作废。完整邮箱不进入 C 的数据库或业务接口；逻辑接口见[数据/API 契约](auth-privacy-data-api-contract.md)，精确形状见[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)和[C OpenAPI](../../packages/openapi/community-auth-api.yaml)，均为实施前评审稿。
- 首次公开发送在服务端接受有效任务时原子绑定帖内身份；异步发布失败仍沿用该身份重试，校验阶段拒绝则不绑定。V 发码／确认和 C 注册／登录分别使用本方幂等及重试规则，不跨方传递幂等键；超时核对原结果，不重复发码、建号或建会话。认证成功后恢复用户原本的入口意图。
- 会话初始有效期为三十天；剩余七天以内且用户活跃时将同一令牌延到实际现在＋三十天，不换令牌／撤销秘密，不弹验证码。主动退出、封禁和新设备接替仍立即撤销，续期不能恢复失效会话。
- 认证异常边界：投递未知时第 40 秒先用原幂等键核对状态，只有确认未发出才允许新的受限发码并重置六十秒间隔；主动退出先持久记录登出待完成，再清除本地令牌和节点；超时或重启后用不可访问社区的独立撤销秘密补做服务端撤销；安全存储不可用时不降级保存令牌；设备用随机安装标识识别，不读取硬件指纹。
- 注册验证码申请的邮箱枚举保护已确认：格式／域名合规的申请对精确地址配额状态返回相同受理状态和“如果可以发送，验证码将到达邮箱”提示；验证成功后才可能签发本次注册资格，不能恢复旧账号。具体投递、时延、限流的侧信道验收仍属安全评审范围。
- **历史进度（2026-09-25）：**当时曾确认稳定匿名凭证生命周期，后被本页顶部的 2026-09-26 当前架构替代。处罚规则仍按最新账号模块执行：禁言可申请注销，正式注销后禁言随旧账号终止；封禁不可注销，缓冲期内新封禁会取消申请。历史讨论见 [ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)、[第三十六轮](../discussions/2026-09-25-grilling-round36.md)和[第三十七轮](../discussions/2026-09-25-grilling-round37.md)。
- **2026-09-26 认证架构决策**：第三十八轮发现“唯一邮箱验证方若主动恶意伪造验证成功”可挑战旧号控制权。用户已接受 V 可造新资格但不能凭邮箱接管旧号的边界，选定校邮注册准入＋独立用户名密码账号及独立恢复。决策与候选取舍见[认证与隐私架构决策](auth-privacy-architecture-decision.md)；[GPT-6 认证隐私架构交接](auth-privacy-gpt6-handoff.md)与[第三十八轮](../discussions/2026-09-26-grilling-round38.md)是当时的问题背景。当前仍处于实施前规格化阶段。

## 第十九轮最新决定

| 项 | 最新结论 | 所属规则 |
| --- | --- | --- |
| 1 | 不限制前缀别名形式；后缀必须严格为 hainanu.edu.cn，禁空格、大小写区分继续适用 | [AUTH-01 / AUTH-INPUT-01](modules/accounts.md) |
| 2 | 首版不做周期性校内资格复核 | [AUTH-01](modules/accounts.md) |
| 3 | 首版移除模型功能及设计；标题全部手写，搜索按文字检索 | [POST-01](modules/post-composer.md)、[SEARCH-01](modules/navigation.md) |
| 4 | 评论图片失败可移除后手动发送文字或重选图片，保留文字和目标 | [COMMENT-MEDIA-FAIL-01](modules/comments.md) |
| 5 | 提示对方回复前只能发一条消息；图片入口保留，尝试发送图片时提示并阻止 | [DM-CONTACT-01](modules/messaging.md) |
| 6 | 撤回截止由服务端判定，超时失败且保留原消息 | [DM-RECALL-01](modules/messaging.md) |
| 7 | 我的两个页签分别显示空状态与对应入口 | [PERSONAL-EMPTY-01](modules/personal.md) |
| 8 | 同账号换机同步搜索历史；正式注销清除，重新注册为空 | [SEARCH-04](modules/navigation.md) |
| 9 | 暂无复核人员保持待复核，材料保留、不多占申诉次数，不承诺时限 | [APPEAL-01](modules/moderation.md) |
| 10 | 首版不公开热榜权重、衰减公式，后台保留可调配置，数值仍待定 | [HEAT-CONFIG-01](modules/popularity.md) |

原话与题目见[第十九轮档案](../discussions/2026-09-16-grilling-round19.md)。首版完全移除模型功能设计，包括旧拟题与意图理解搜索；标题手写，帖子文字搜索继续保留。

## 当前主干与不得回退的修正

- **账号**：每次注册验证校邮，客户端新生一次性公钥导出槽位，C 验签及对真实 C 挑战的持钥证明；日常／换机以私有用户名和独立密码登录，旧号恢复只用预设独立凭据。后缀严格为 `hainanu.edu.cn`，前缀别名可用，邮箱禁止任何空格且大小写区分。不做周期资格复核。V 与 C 必须由独立组织控制；V 持邮箱→槽位，C 受限认证库持槽位→账号，串通或共同泄漏可直接关联。详情见[当前认证架构决策](auth-privacy-architecture-decision.md)与[协议 v1](auth-privacy-registration-protocol.md)。
- 验证码五分钟、获取间隔六十秒，点击获取控件立即倒计时，明确未发出撤销本次等待；只最新码有效。三次输错限制异常设备对该邮箱五分钟，不延长、不清有效登录；锁定禁取码、结束清零；可确认旧码不计错；无 CAPTCHA。
- 单移动设备，新机以用户名密码登录成功后接替旧机；旧机文件保留，重新登录原账号并接替后才可在 App 看。会话三十天、活跃可续期。设备页展示当前与最近被替代设备。
- 注销七天缓冲，主动登录撤销。禁言可注销、封禁不可且会取消缓冲期申请；禁言在缓冲期内继续生效，但正式注销后随旧账号终止，不延续到同邮箱重新注册的新账号。正式注销后清本人聊天、备注、搜索历史，离线设备获知后清；对方本地聊天保留，各身份独立注销编号。
- **身份**：一至三个长期面具，每帖固定一个，实际发送绑定、失败沿用；不同身份不公开关联。昵称二至十二个可见字符，中英日韩/数字/Unicode 标点，禁止空格、表情、控制及不可见字符；大小写区分、本人不同身份不能同名；三十天改名，头像随时改。
- 首次公开发言前设置基础身份，昵称必填、头像可默认；中断后同机恢复、登录失效先重新登录。累计创建第三个身份后新增间隔六个月，删除不清等待。删除身份清本人对应聊天备注及明确失败内容，公开内容保留独立删除占位，旧帖移出“我的”；仍可从其他入口删旧帖但不可编辑。
- **发帖**：标题手写十五字、正文三千字、图片九张，文字图片至少一种；首版无视频或投票。两步发布无内容预览，返回编辑保留内容；加号始终新稿，旧草稿从“我的”进，管理身份往返保留输入。
- 点击发布回通道后台发送，“我的”转圈卡片保留到结果明确；可查状态、可取消上传发布，不能重复提交。主动取消成功不生成失败卡片、清临时上传文件但保留草稿原图；已成功结果以服务端为准。失败可改内容重试或删除，身份通道固定；失败卡片删除不可恢复。已接受任务不因登录失效换归属。
- 新帖草稿同机持久保存；**旧帖编辑退出不保存修改、不弹确认，下一次从公开版本开始**。删除帖关闭内容及评论、清编辑入口与未保存修改，不能继续编辑已删除帖。
- **阅读评论**：正文/评论默认约 2/3、1/3 独立滚动，可拖动分界增大评论区；收起重开恢复默认比例及阅读位置。主评论前十按赞、其余时间；楼中楼默认前五按赞、其余手动按时间，约五十条一页，末页全显剩余。
- 本人发送成功将该评论滚到评论区域顶部，排序不变、上方正文不滚；需要时展开所在楼。别人新增不提示不插入，重进帖子或收起评论再展开加载。离帖清未发输入，无长期评论草稿；明确失败弹顶部提示，原发送身份的失败任务从系统通知处理，不进入“我发出的”。
- **无引用块；“回复 xxx”可定位被回复的具体评论**，需要时展开并高亮。目标失效点击顶部提示“评论已经删除”，自动消失、无确认、不阻塞、可重复提示。输入中的失效回复目标仍保留输入供重新选择。主评论无提示删整楼，楼中楼只删本条保留他人回复；无帖子更新前核对功能。
- **私信**：按身份对跨帖延续。首次直接提示“对方回复前只能发一条消息”，保留图片入口；尝试发图片时提示“不允许发送图片”并阻止，首次只允许一条文字；对方回复后开放。发言者头像昵称进入对应身份私信，本人无操作；关系里的被回复者昵称用于评论定位。
- 私信转圈不可点，明确失败红感叹号点击询问重发，未知继续核对。两分钟撤回从平台成功接收起算、截止由服务端判定，超时/失败保留原消息。
- 聊天历史自动存本机，首版无迁移、无云历史恢复。待收新消息持续保存到接收方确认写入本地，不因离线时长丢弃。保存失败在运行期保留临时内容并提示，重开显示失败可重试，通过待投递副本补收；不是发信人发送失败。
- 新机恢复会话入口、昵称、备注，没有旧记录不提示。普通删聊天清本人记录但保留备注；删除身份则清对应本人聊天与备注，对方已有记录保留。首版不提供迁移、备份或导出；未发送文字按身份对同机保留，删除会话或身份时清除。
- **消息与我的**：消息三入口为点赞、评论与回复、系统通知，下方身份切换入口及私信列表。2026-09-20 用户要求切换入口使用显眼标识加文字说明，撤回旧“仅小圆点”；全页随身份切换，账号级通知例外。隐藏聊天暂不计未读，新消息恢复时旧未读一起恢复。备注仅本人可见、换机同步，搜索可匹配当前身份隐藏会话。
- “我的”汇总仍存在身份的帖子与草稿，收藏全身份共用；本人帖/收藏返回保留页签位置。两个页签各自有空状态和入口。点赞收藏先反馈、明确失败回退，收藏未知处理中暂停重复点击。
- **通道与标签**：通道必选，自定义 #标签选填、最多三个；无统一中间分类或标签治理。主题屏蔽后续版本设计，首版不设分类屏蔽入口、过滤或分类隐藏预览；私信拉黑与普通举报独立保留。
- **导航热度**：首版七个通道，树初始五个，热门优先；未登录只显示树入口外壳，已有用户登录或新用户注册建号并建立会话后，完整目录校验通过才加载节点，失败保留无节点树并可重试；无数据时默认露出吐槽/避雷/安利/搭子/情感。首条切片导航树拆为两次开发任务，英文通道编码、`GET /api/v1/channels` 契约和 `200/401/503` 错误边界已定，节点视觉与动效仍待 UI 阶段细化。全局文字搜索按通道分组，相关度/最新排序，同分较新优先；搜索历史按入口分隔、同账号同步、正式注销清除。
- 热榜近七天前二十，名次/标题/浏览量；按赞、藏、独立讨论人数与时间衰减，排除作者账号自身贡献；同分新帖优先、同时间用服务端单调唯一序号。权重数值不公开，后台可配置，具体公式仍待定。
- 热榜按服务端整五分钟计算，浏览中不重排，返回刷新置顶；失败保留仍可展示旧榜，没旧榜显示失败。离开榜单清旧缓存，重新进入加载。删光有效评论后下次刷新不计讨论人数。通道热度独立，作者账号计参与，不套帖子排作者规则。
- **治理**：拉黑按账号双向禁发、前台不暴露其他面具、保留已有记录且须明确解除。私信举报证据按首尾区间全部可用记录，已知缺口标明后可提交，改范围重新授权；已提交证据独立保存。主动放弃清材料，未知先核对任务。
- 同一事实举报归并；删公开帖/评论终结对应未完成举报，单方清聊天不终结。处罚独立计时；到期恢复权限，申诉继续。每次处罚最多三次独立申诉，首次五百字六图、每次追加五百字三图；追加不占次数。结案不追加旧申诉，新材料另发一轮、继续上限；独立事实可另举报。无人复核保留材料待复核、不多计次数、不承诺时限。

## 图稿位置与确认范围

- [消息身份切换展开 v2 · 已确认](../../UI产品图/消息身份切换-展开-v2.png)：内置 image_gen 编辑，显眼切换图标、“切换身份／查看不同身份的消息”、当前身份和下拉箭头；用户答复“可以，下一个”。v1 保留用于对比，既有 prompt 仅留档，不再作为用户交付要求。

- [消息首页正常状态 v1](../../UI产品图/消息首页-正常状态-v1.png)：GPT-6 Astra Ultra 设计、HTML/CSS 渲染，用户已确认主布局；源文件在 `docs/discussions/assets/2026-09-13-message-home-v1/`。
- [默认阅读](../../UI产品图/读帖子页面.png)、[展开评论](../../UI产品图/进入帖子后上拉评论页面.png)、[阅读对照](../../UI产品图/读帖子上拉评论流程图.png)：深色 v2 基准已确认，新增时间/标签/分享/图片规则尚未全部同步。
- [回复输入](../../UI产品图/回复输入状态.png)：v3 布局已确认。
- `UI产品图/楼中楼回复.png` 仍为历史三条版；身份弹框 v3 使用旧临时身份模型，均不能直接当作当前规则。
- 不需要依赖之前私有聊天中的图片才能继续；上述本地文件和模块足以重建上下文。Figma 旧文件 `wYSmtpR5iKKG90UsxKVeMR` 仅供追溯。

## 从这里继续

第十九、二十轮已处理，用户重贴的十条答复与第二十轮原记录一致，不要求再次确认。第二十一轮 Q1“不搞交易”、Q2“OK”、Q3“不允许”均已落盘：首版不做交易；审核员可重置违规昵称或头像并通知，强制整改不受改名间隔限制；下架帖不允许修改后重审，误判申诉恢复继续有效。

第二十二轮最终确认“可以，屏蔽后续版本可以设计”：通道必选、用户自定义 #标签选填、主题屏蔽留到后续版本。已清理旧中间分类与屏蔽依赖；不再问分类清单、治理和标签是否保留。

消息身份切换展开 v2 已确认。评论与回复继续保留“收到的／我发出的”两页签、当前身份隔离、时间倒序、昵称／评论／来源帖标题；用户已取消每条本人的收件身份小头像及“收件：某昵称”，不得恢复。旧 v1 仅作评审底稿。

收到的 v2、我发出的正常状态 v1、系统通知发送失败详情 v1、顶部失败提示 v1、系统通知时间流 v2、举报处理结果详情 v1 和违规处理通知详情 v1 已确认。首次申诉 v1 的次数标题被否决，当前修订 v2：主标题只写“申诉”，次数移为处罚摘要下方的小字说明。最多三次、本次五百字六图、补充不占次数均不变，不重复询问。旧发言列表内失败稿与分类式系统通知均作废，不得恢复。

不再问已定的首次身份、昵称字符、资格复核、验证码倒计时、三十天会话、五十条分页、待收消息保留期限、五分钟热榜、无审核员待复核。其余实现参数与视觉集中随实现/图稿评审，不制造小变体反复提问。
