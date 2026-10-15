# 文字社区与认证 Android 统一验收任务单

> **2026-10-15 第三项实测：PARTIAL。**独立RP获准发布；真实vivo系统Passkey创建、可发现恢复、绑定丢响应后跨进程原键核对、新凭据完整确认/无自动登录及重开恢复PASS。最终七阶段全部PASS（mobile334/分析0、R05、F4八项、server、受限权限、实际runtime25断言、vet），被测产品9dda242、205输入指纹5bc83b4d…677631；没有改产品/SQL/锁。Google两项正向关联现均linked=true，但严格默认HTTPS仍403/1010；坏签名超时、未关联包取消均无明确关联拒绝，第一次恢复超时保留。因此CA-A13和第三项不记整体PASS。见[实测报告](community-android-stage3-device-validation-20261015.md)/[机器记录](community-android-stage3-device-validation-20261015.json)/[已应用公开关联](community-android-stage3-applied-20261015/proposal.json)。手机窗口已结束，三个新包与未决材料保留，无后续ADB；任务1/2限定通过保留，任务4双实体、iOS、生产及完整App仍待验。下方旧日期准备/未授权/NOT_RUN记录均为原版本历史。

> **2026-10-15 普通网络读屏遗漏已补齐：**实际断开一次列表GET后发现错误不自动朗读，已修复；同包同证书复验中用户确认自动提醒、重新加载恢复、无需重登和原草稿保持均正常。最终mobile334／分析0／R05／F4八项PASS，覆盖最终205输入；TalkBack已代关、转发与业务计数核对恢复。见[补验报告](community-android-talkback-network-retry-20261015.md)/[记录](community-android-talkback-network-retry-20261015.json)。原333项及“列表重试朗读未验”保留为前一版本历史；第三项Passkey、第四项双设备、iOS和生产仍待验，不升级完整模块/App为PASS。

> **2026-10-15 TalkBack补充：PASS_APPROVED_TALKBACK_SCOPE。**通道重复、我的/返回英文、身份选中语义、必填提示自动朗读和中文数字语义语言已修复并由本轮单机限定清单复验；最终mobile333、导航语义4、分析0、R05和F4八项PASS，205输入指纹见[实测报告](community-android-talkback-validation-20261015.md)/[机器记录](community-android-talkback-validation-20261015.json)。一次GET503触发现有登录恢复保护，未误计普通列表重载朗读；原转发恢复、SQL写计数不变，按用户明确请求关闭TalkBack并核对。任务3系统Passkey、任务4双实体、iOS和生产仍独立未验；以下历史“TalkBack关闭未验”保留原版本范围。

> **2026-10-15 当前任务2单机范围通过：**原生35项＋3组进程中断、实际SQLite跨进程/用户整机重启/本地闭号清理PASS；正常App合成A重新正常登录后强停/重启的草稿、身份通道与会话由用户确认。先前旧会话因获准Gate恢复推进代次被拒绝，保留负向观察，不冒充恢复PASS。Windows155＋3 POSIX SKIP／Linux158。见[实测报告](community-android-stage2-device-validation-20261015.md)及[机器记录](community-android-stage2-device-validation-20261015.json)。产品/native/manifest/SQL/锁未改；默认USB隔离守卫保留，仅本轮显式批准既有身份。TalkBack关闭未验；任务3系统Passkey、任务4双实体、iOS和生产仍待验，模块/App不升级整体PASS。以下历史条目保留原日期范围。

> **2026-10-15 当前任务1实测完成：八自动点PASS＋人工IME USER_CONFIRMED。**真实vivo S18/Android15，中文/换行/emoji与草稿重开由用户对明确清单综合答“一切正确”；原自动PARTIAL记录未改，汇总另存。最终mobile327、分析0，Python Windows144＋3 POSIX SKIP／Linux147；历史失败及修复全过程保留。见[实测报告](community-android-device-validation-20261015.md)与[机器记录](community-android-device-validation-20261015.json)。normal/A会话、当前server/reverse/fixture与专用材料保留。任务2–4、iOS和生产仍独立未验；并行stage3准备保留原范围。

> **2026-10-15 第三项可独立主机准备完成：**七阶段、mobile322、Passkey Dart9、JVM24、Linux148／Windows145＋3POSIX SKIP及3未配置签名对照PASS。用户选定独立RP候选方案继续核实，具体文件/差异见[关联方案](community-android-stage3-rp-proposal-20261015.md)；DNS解析不证明控制权，配置应用/公开部署仍未授权，新独立lab与最终候选重建仍依赖审批。见[准备报告](community-android-stage3-preparation-20261015.md)。无ADB/手机动作；保留并行手机e0c1280及其后工作，不采用未提交USB代码，设备流程按其后固定交付重新确认。任务1–4设备、iOS和生产均未升级通过。

> **2026-10-15 手机窗口当前阻断：BLOCKED_KEY_ISOLATION。**用户已确认 vivo S18、30–45分钟窗口、认证会话释放、隔离包和专用USB key；原stage1实际等待90秒后exit1，未发现目标设备，未安装/启动App、注册或业务写入。Windows环境变量不能证明专用key隔离，已给stage1/2添加不可凭授权flag绕过的前置守卫；CA-A01–13全部NOT_RUN，stage2也阻断。Windows136 PASS＋3 POSIX SKIP、Linux139 PASS仅为host；自有60761 server已按exe/start/port核实后停止，既存5037未动；用户已结束本轮窗口，后续须重新确认。见[本轮报告](community-android-device-blocked-20261015.md)与[脱敏记录](community-android-device-blocked-20261015.json)。历史准备/指纹/APK证据保留原范围；先证明真正独立profile或验证专用key目录的ADB，再由原服务归属方安全释放USB并重验摘要/ready/空库。新增OS账户/安全配置或共享key例外须用户明确变更授权。

> **2026-10-15 第二项非手机准备完成：**第一项制品/空库与全部450输入不变；第二项已准备3个独立新签名包、35项原生精确选择及3组认证中断、实际插件SQLite跨进程/本地清理探针。新执行mobile322、分析0、Linux136／Windows133＋3POSIX跳过、199项镜像和制品边界核对通过；设备仍NOT_RUN。见[第二项报告](community-android-stage2-preparation-20261015.md)及[手机SOP](../../tools/community-android-stage2/README.md)。无需重做任务1，按两个现成窗口清单执行；整机重启仍另行许可，任务3/4不因准备完成而通过。

> **2026-10-15 第一项非手机准备完成：**修复 DELETE 首次核对失败后遗漏 poll 集合，以及 C 确认取消注销后的 UI 完成入口。最后产品修改后 mobile322/R05/F4 通过，真实 server/权限/runtime/vet 通过；新增整段 host 八检查点和最终隔离 Debug/标准未签名 Release 构建通过，实际设备与 IME 仍 NOT_RUN。见[准备报告](community-android-stage1-preparation-20261015.md)和[机器记录](community-android-stage1-preparation-20261015.json)。按用户要求保留专用环境、手机新空库和 APK；未调用 ADB 或创建真实账号/USB key。后续确认设备窗口、隔离包/USB 授权并补真实输入法，任务2–4、iOS和生产分别待验。

日期：2026-10-14，Asia/Shanghai。仓库 zewbby/HnuHole，分支 codex/community-flutter-pages，任务目录 E:/HnuHole-community-f4-20261012/repo。

用户要求：将单机社区流程、原生存储与生命周期、系统Passkey三个任务按顺序保留，再追加双设备验证，统一为一份任务单。**本次只整理计划与交接，没有执行新增测试或使用设备。**此前设备窗口仍为用户延期；新增双设备范围不代表已提供第二台设备、设备窗口或系统设置修改授权。

## 固定基线与已有证据

| 项目 | 固定版本／状态 |
|---|---|
| 任务单编写起点 | 1a0051297a4f8a046ca41191f1c47ab5d7b5b166 |
| 已整合产品源码 | 28cee4656edd710d60676a81794c20cd49f45351 |
| 认证来源 | d859cb05c772cdf8d8b75e439a2bfedf0414dd46 |
| 已验证运行输入 | 443项，SHA256 599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7 |
| 主机及构建 | 20261013七stage、mobile320及Android构建PASS；属于对应固定输入的证据 |
| 单机设备 | CA-A01–07/A10自动PASS＋人工IME USER_CONFIRMED；CA-A08/09/11/12及TalkBack限定PASS；CA-A13 PARTIAL，详见20261015实测记录 |
| 双设备 | NI-X01／NI-X02尚未执行；第二实体Android与两机窗口未确认 |

已有[联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)、[交付与清理回执](community-auth-integration-delivery-20261013.json)保留原日期与范围。本任务单追加双设备工作，不将旧认证22 PASS／0 FAIL／2 BLOCKED或社区主机结果改写成新设备通过。

## 开工条件

- 先只读核对本任务目录、分支、HEAD、未提交改动、C/E盘容量和工具实际路径。此前专用SDK副本、缓存、APK、调试私钥和CA材料已删除；只在确认容量与隔离后重建本任务专用环境，不调用共享SDK写缓存、不盲目安装整套工具链、不升级依赖或删除锁。
- 使用本任务独立日志、缓存、端口、新一次性C/V数据库和合成账号。保持认证会话环境、账号、签名、密钥、恢复材料与工作目录独立。
- 安装或使用设备前，确认具体型号/设备ID、归属、占用时段、认证会话已释放、包名/签名及现有App数据影响。整机重启、卸载、清数据、OEM搬家及provider/同步设置分别说明影响后确认；不默认获得这些操作授权。
- 隔离包沿用 org.hnuhole.hnuhole_mobile.communityf5 方案，执行前核对实际manifest/APK/签名。重建会生成新的本任务材料，旧APK哈希及旧调试签名仅为历史构建证据；不得复用认证签名凑关联。
- 准备公开RP/package/signature关联或其他安全配置时，先提供具体用途、文件差异与风险边界，等待用户确认。指纹、系统密码和同步账号操作由用户在手机上完成，秘密不进聊天、Git或原始证明记录。

## 按顺序执行的四个任务

| 顺序 | 任务 | 固定检查映射 | 当前状态 |
|---|---|---|---|
| 1 | 单台Android文字社区全流程 | CA-A01–A07、A10；A06/A08/A12/B02/B03/B05/B06/B10 | PASS：本轮八自动点＋USER_CONFIRMED IME |
| 2 | 原生存储与生命周期 | CA-A08/A09/A11/A12；N01/A12/A08 | PASS：35原生项＋3中断对＋实际重开/重启与用户确认 |
| 3 | 系统Passkey与单机回归收口 | CA-A13；N03/A07/A09，并复核前三阶段受影响检查 | PARTIAL：单机正向/原键核对PASS；provider两项明确拒绝及严格HTTPS403待收口 |
| 4 | 双实体Android迁移与恢复验证 | NI-X01／NI-X02；N01/A12/A07/N03 | NOT_RUN：第二设备及两机窗口未确认 |

### 任务1：单台Android文字社区全流程

执行实际main启动、登录、创建/选择身份、发帖、通道列表/详情、我的、删除、退出重进、A/B账号切换和正式注销清理。确认实际目录/auth/post HTTP、自动轮询、中文输入和插件注册。

重点故障：重复提交核对原commandId/digest；失败重试保留原identityId/channelId；账号切换后的草稿、未知命令与迟到结果隔离；DELETE响应丢失核对原命令；闭号清未公开载荷、回执关联及本地业务数据，保留另一账号。主机故障测试不能代替设备路径；需要补充设备故障控制/计数入口时，先在专用环境准备并审查，不修改认证协议或缩短不可变期限。

通过条件：正常流程与上述故障都有本轮真实设备、实际C/V/SQL和本地状态证据，无重复副作用、跨账号泄露或身份/通道漂移。七天注销可沿原规范用可信测试时钟推进，由普通worker处理；复核原SQL截止仍恰好七天，不称自然等待七天，不跳过worker。

### 任务2：原生存储与生命周期

执行AndroidBusinessStorageTest业务7项、认证vault16项、Passkey codec/错误分类12项，并按真实执行输出计数。验证实际Keystore与业务SQLite，强停/重开本任务包、跨进程恢复、获许可后的整机重启、备份排除和原生闭号key/file清理；检查中文输入与适用的IME/TalkBack行为。

原生测试必须使用匹配的instrumentation APK、testApplicationId、runner和专用namespace。现有只选认证类的脚本不代证business7；执行前核对选取范围并准备专用步骤。两台设备阶段前不复用不明测试包或直接运行旧runId、旧账号路径的设备脚本。

通过条件：各原生项和实际生命周期操作有本轮证据；失败或恢复未知明确保留，不把构建、内存vault替身、codec检查或单次重开外推为完整原生持久安全。

### 任务3：系统Passkey与单机回归收口

先准备并审批本任务独立RP、域名、package和签名关联，再用真实系统provider完成可发现Passkey创建/恢复正常流程。验证取消、拒绝、自然到期、响应丢失及原键结果核对的适用边界；未知结果保持原待办，不重放证明、不关闭校验、不绕过Gate。人工系统确认/指纹动作按阶段明确提示。

处理任务1–3实际复现的缺陷，并在最后一次源码修改后重跑受影响mobile、原生、R05、integration、server/权限/实际runtime与最终vet；是否复用已有未变源码证据须逐项说明版本和覆盖范围。标准构建与测试选择保持锁定，Release不添加开发信任旁路或生产签名。

通过条件：实际系统Passkey正向与适用负向、单机全流程和原生生命周期都收口，证据覆盖最后产品源码。此时只可登记“单机阶段完成”，**统一任务单仍等待任务4**；不提前写整个Android联合任务完成。

### 任务4：双实体Android迁移与恢复验证

任务1–3后执行，使用两个独立的实体Android。先确认第二台设备归属/型号、兼容provider、OEM可用路径和两机窗口；手机+模拟器、文件手工复制或人工确认均不能替代这两项。

| 固定ID | 实际验证与通过条件 | 模块 |
|---|---|---|
| NI-X01 | 经可用OEM官方搬家路径让第二实体手机接收本任务专用测试App，记录真实搬家机制及两侧行为。账号token、私有密文和Keystore能力不被复制成可用账号控制权，目标不自动登录。 | N01/A12 |
| NI-X02 | 经允许的真实系统同步或跨设备认证，在第二实体手机完成可发现Passkey恢复；仍须C验证与新凭据完整确认，不自动登录。按重设契约核对旧凭据/会话失效，记录真实provider及C/SQL事实。 | A07/N03 |

这两项沿[原固定非iOS清单](auth-privacy-non-ios-closure-plan.md) NI-X01/NI-X02定义执行，不扩成任意账号数据复制。OEM操作须能控制为本任务测试范围；若会覆盖用户数据或必须不安全地整机迁移，先停止该路径并记录具体阻塞及替代机型/机制条件，不降低通过标准。

当前没有已经验证可直接执行的联合源码双实体统一runner。执行前根据具体两机准备可审阅的操作/采证步骤并核对现有入口。tools/run-android-vault-transfer.py明确只接受target-emulator，证明范围为合成密文边界；不能放宽其断言后冒充OEM搬家或NI-X01/NI-X02证据。

通过条件：NI-X01、NI-X02均有本轮双实体证据；复现缺陷后修复并重跑受影响单机/原生/主机检查。缺第二设备、真实OEM路径、provider或必要授权时明确BLOCKED并说明解阻条件，保留前三阶段已成立的有范围证据，统一任务单不登记完整PASS。

## 最终交付与范围

四阶段统一收尾，交付固定源码SHA与输入指纹、APK/签名/manifest、两设备事实、命令/时段/退出码、SQL/本地布尔事实与计数、阶段报告、失败/阻塞及解阻条件。更新模块交接、台账、HANDOFF和progress；修复归属认证边界时提供最小复现与证据，未经单独授权不改认证协议或操作认证会话环境。

提交与推送仅按既有授权正常推进本分支，遇并行变更不重置或强推；不合main、不发布Release、不部署生产。仅清理本任务明确创建的资源，保留用户指定的设备数据。

验收口径：四阶段全部通过后登记“现有文字社区与固定认证候选的单机＋双实体Android范围通过”。iOS、生产部署/灾备/独立审计及未实现业务继续独立，完整模块/完整App不因本任务单通过而自动升级。F1–F3页面不重做，评论、私信、图片上传、搜索和推送不新增。

## 参考入口

- [单机详细13项清单](community-single-android-acceptance-20261013.md)：继续作为任务1–3的逐项细则，其原“排除第二设备”仅属于20261013历史范围；最新统一范围以上文任务4为准。
- [联合主机报告](community-auth-integration-report-20261013.md)与[机器记录](community-auth-integration-20261013.json)：已有版本证据，未追加设备通过。
- [原认证双设备固定定义](auth-privacy-non-ios-closure-plan.md)：NI-X01/NI-X02。
