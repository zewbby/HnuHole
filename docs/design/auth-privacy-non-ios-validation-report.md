# 非 iOS 匿名基础验收当前报告

> **2026-10-10 换机交接当前入口：**用户要求结束当前验收／排错、提交推送并交接全部任务缓存／测试秘密，远端确认后清理。B1＋B2 11 PASS；B3＋B4 8 PASS／3原执行FAIL；固定24项19 PASS／3 FAIL／2 BLOCKED，B6／iOS及生产未通过。Google直接诊断源码已保留，Java／debug APK编译成功但release及完整准备被D盘耗尽／WSL只读I/O故障中断；没有最终PASS manifest、未安装、API／系统UI未执行。手机原vivo凭据／自动填充已恢复。新机器先读[换机交接](auth-privacy-machine-transfer-20261010.md)及[交付／缓存清理实录](../../services/api/authlab/auth-privacy-machine-transfer-verification.json)，旧“缓存保留／未提交”仅为历史状态。

> **2026-10-10 ultra排错阶段历史快照：**B3＋B4保持8／11 PASS、3项原执行FAIL。用户确认本轮点“继续”，全局代理下Google批准正向仍未取得证明；原生7次失败与一次系统清理器在原生开始前强停分别保留。只读审手机实际vivo选择器v15.0：provider非RESULT_OK返回和内部失败会被统一上报selector取消，原错误信息未传到App。此机制已由安装APK静态代码证实，但Google上游失败根因和本轮精确分支仍未证实；27字符消息摘要仅作佐证，旧JDI原型未区分参数／堆对象，不作为验收证据。ultra子审触及用量上限后由主任务续审。新有界观察器源码已保留并编译，未发起新ceremony；产品APK未改、已通过8项不重验。当前Google凭据／自动填充设置临时保留，等待人工只查看密码管理工具设置，不清数据或登出；验收后须按原备份恢复，Clash全局模式须由用户恢复。固定24项仍19 PASS／3 FAIL／2 BLOCKED，B6／iOS未执行，未提交／推送。见[具体诊断记录](../../services/api/authlab/android-passkey-selector-diagnosis-verification.json)。

> **2026-10-10 Google 提供方初轮历史结论（本轮接续见顶部）：**B3＋B4仍为8／11 PASS、3项原执行FAIL。v17修正隔离账号的正常产品登录续办，分析／三包构建／四种签名核对通过；手机批准签名Google正向控制4次均在证明返回前取得原生取消，未新增绑定，新的Google三项负向未执行。系统Google账号存在，用户确认Chrome同步和实时搜索可用；Google远端关联检查批准签名为true、错误签名及未关联包名为false，这些不代证手机拒绝原因。具体根因未确认，不归咎用户，也不把通用取消计为关联拒绝。已恢复原vivo通行密钥及自动填充设置，主包v16与数据保留、隔离包v17保留，可复用环境不清理。固定24项仍19 PASS／3 FAIL／2 BLOCKED；B6和iOS未执行，未提交／推送。下一次须先取得具体原生原因或可用实际提供方的正向控制，禁止原样盲重试。见[Google对照记录](../../services/api/authlab/android-b3b4-google-provider-verification.json)。


> **2026-10-10 v16批次历史结束记录（Google重试见顶部）：**B3关闭组4／4通过，B4关联与存储组4／7通过，合计8／11 PASS、3 FAIL、0 NOT_RUN。C01／C03／C04和D05已在v16真实App通过，早期选择超时是历史记录；D05另一凭据保留由未变v15实际SQL证据补充，不宣称vivo双凭据创建。D01客户端固定RP、实际服务端422及原五分钟期限核对通过，原生错误RP与D02错误签名／D03未关联包名均只有OEM通用取消，不能归因为关联拒绝。批准控制组实际C204，负向未新增凭据；三项完整验收仍FAIL。批准隔离签名已恢复，主App／账号／草稿／环境保留，人工窗口已结束，不再自动弹安装、认证或追加关闭。固定24项累计19 PASS／3 FAIL／2缺第二实体Android而BLOCKED；B6未执行，iOS／完整非iOS／生产未通过，未提交／推送。当前细节见[本批脱敏记录](../../services/api/authlab/android-b3b4-batch-20261010-verification.json)。


> **2026-10-10 B3＋B4 逐项结果：**固定11项当前接受8项（NI-D04、NI-C01、NI-C03、NI-C04、NI-C02、NI-D05、NI-K01、NI-K02）。每项保留独立App／设备／SQL和启动版本；夹具失败与原成功前置记录保留，不重放证明。本轮11项均已执行；未通过项为NI-D01、NI-D02、NI-D03，具体缺口见本批记录。B1＋B2原11项PASS不改写。用户确认卸载后的旧本机状态不能续用，历史证据及可复用环境保留；完整非iOS／iOS／生产未通过，HnuHole未提交／推送。见[任务单](auth-privacy-b3-b4-plan.md)及矩阵JSON的`b3b4Verification`。


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

更新：2026-10-08（Asia/Shanghai）。分支 `codex/auth-privacy-handoff`；基线 `0eff47a21cd4f4ab1636b4468f7d5df9769a264f`，当前包含未提交修改。任务范围见[三步任务单](auth-privacy-non-ios-plan.md)，逐项结果见[当前记录](../../services/api/authlab/android-matrix-verification.json)。原 Android 正常、七阶段故障及 r1/r2/r3 结果保留各自 APK／源码范围，新数据库不能继承旧设备结果。

## 已实现与当前执行

**2026-10-08 批量验收交接：**十四个命名实际App阶段已PASS，每项保留自己的APK／夹具／runner摘要、设备PID和代理计数。覆盖真实注册、双端独立草稿／手机主动接替／账号隔离，真实Passkey成功响应丢失与原键跨进程COMMITTED核对，实际provider期间控制器取消与产品返回，C证据过期冻结后的旧会话401／主动登录／明确结束旧UNKNOWN，两次提前成功后的原回执确认与产品移除，未回应原生操作约60秒取消，篡改来源422拒绝及自然到期原键NOT_COMMITTED核对。旧来源拒绝在核对前遇USB及服务中断，仍按原版本保留，未迁成新会话原结果；新的完整负向／核对另有自己的证明。取消／超时后的OEM窗口清理由宿主在原生结果后执行，不宣称自动关闭或任意迟到回调；两秒观察范围保持。对应四组SQL/race/vet、R03十九项、R05及Flutter188项回归PASS，不代证新夹具；新夹具分析／ARM64＋x64构建与设备执行逐项PASS。Activity重建／旋转、原生等待期间Gate／接替、完整关联／签名负向及真实Passkey／未知迟到待办参与关闭仍需补入口和证据。仅有vivo，OEM实体搬家BLOCKED；iOS本轮SKIP；完整AC05／B02及生产继续未通过。工具、环境、缓存、原账号与草稿按用户指令保留；未提交／推送。见[报告](auth-privacy-non-ios-validation-report.md)和[机器记录](../../services/api/authlab/android-matrix-verification.json)。

本轮十四项的实际接受结果如下。`v1／v3／v5／v6` 只表示本轮归档测试包版本；精确 APK、夹具与 runner 摘要及代理增量以机器记录 `batchVerification.phases` 为准。阶段名与进程 PID 不替代结果断言。

| 实际 App 阶段 | 设备／PID | 测试包 | 已验证的边界 |
|---|---|---|---|
| batch-register | vivo／16252 | v1 | 真实 V 邮件与 C 注册、完整恢复码确认 |
| batch-phone-draft | vivo／16718 | v1 | 手机原生持久草稿，未创建身份 |
| batch-companion-draft | 模拟器／4643 | v1 | 同账号主动接替、独立本地草稿 |
| batch-phone-retake | vivo／11306 | v1 | 旧会话401、明确登录及手机原草稿恢复 |
| batch-account-isolation | vivo／11936 | v1 | 新账号与原账号的草稿／待办／历史隔离 |
| batch-passkey-drop | vivo／12991 | v1 | 真实指纹创建、C成功后丢失响应、UNKNOWN持久化 |
| batch-passkey-reconcile | vivo／15400 | v1 | 新进程原键COMMITTED核对，没有再次提交证明 |
| batch-passkey-route-cancel | vivo／18612 | v3 | 实际provider期间控制器取消、产品返回及两秒无提交观察 |
| batch-gate-session-recover | vivo／7697 | v5 | 真实Gate过期／签名恢复后旧会话401，主动登录并明确结束旧UNKNOWN |
| batch-passkey-ack-interrupted-success | vivo／15567 | v6 | 中断测试留下的已知成功回执明确确认，无新原生请求 |
| batch-passkey-remove-existing | vivo／15859 | v6 | 产品两步移除测试Passkey，当前会话保留 |
| batch-passkey-timeout | vivo／16912 | v6 | 实际系统操作未回应，60.516秒原生取消，无C提交 |
| batch-passkey-origin-reject | vivo／17230 | v6 | 真实证明仅篡改来源，C以422拒绝，原待办保持UNKNOWN |
| batch-passkey-rejected-reconcile | vivo／17650 | v6 | 自然到期后新进程原键NOT_COMMITTED核对及明确确认，无证明重放 |

十四项均为 PASS；它们不代表完整设备矩阵通过。超时前两次人工指纹提前完成了真实绑定，不能计等待超时通过；成功结果均经过原回执确认与产品移除，再执行最终无人操作的超时。第一组确认／移除PID为12589／14124，第二组为上表PID，原记录保留。用户已纠正早先“系统自动完成”的描述为实际按了指纹，没有据此登记平台自动认证或阻塞。

本轮本地交接校验和 diff 检查 PASS；最后实际 C/V readiness 均为200。该交接结果只覆盖当前源码与有版本的接受记录，完整AC05／B02、剩余平台场景及生产继续未通过。

以下2026-10-07批量段落保留中途八阶段快照及失败诊断，不能作为2026-10-08的当前阶段数量或待验清单；后续“设置页增加”起的记录继续保留各自实现及历史证明范围。

2026-10-07 批量接续（历史快照，后续以2026-10-08交接段为准）：四组隔离回归PASS并已采集对应源码摘要：完整SQL／Go race／vet、R03实际C/V的19项有界检查、R05真实Dart→HTTPS→SQL、Flutter188项。源码清单在运行后采集，明确不是运行时抓取；缓存对应源码在运行与采集间未改变且与当前工作区对应源码一致。新批量夹具独立验收，不由上述回归代证。

批量实际App八阶段已接受，详细PID、每阶段APK／夹具／runner版本与代理计数见机器记录 batchVerification。v1 APK `8e68d0607908db955d7449a67866af6def0fbdf952a00e9c3bc854103563f7fe`覆盖注册／双端独立草稿／主动接替／账号隔离／真实创建响应丢失／原回执跨进程。绑定阶段实际C返回204，代理丢一次响应；新进程只查询原键／原意图，没有再次提交证明。v3 APK `3a91923c5976791d5d95d02df4ff19ce2ed4920e1ead54ce352c0fe56789e551`取消阶段PID18612：宿主先确认真实vivo CredentialSelectorActivity，再实际控制器取消，随后产品返回；两秒内原生待办空、服务端凭据未增、绑定提交增量0。OEM系统窗口仍在，验收完成后宿主Back关闭，不宣称系统自动退出或任意迟到回调通过。

来源负向两次未接受（PID16405／21617），服务端都没有收到新增证明；后者有原生框架错误，用户确认回到App，具体原生错误原因尚不确定。初版夹具遗漏真实触摸传播，已修复；原HTTP-only等待会忽略系统错误，已补真正异步等待和只含状态／错误码的诊断。新版本先通过产品两步移除已有合成账号测试Passkey并核对原回执，再重建；不清账号／草稿、不重放旧证明。失败版、尝试和计数锚点保留。

用户开启完全访问后，原自动审批额度故障已解除；私有配置正常导出，实际代理运行源摘要匹配，ARM64＋x64构建及安装通过。秘密、证明和大日志继续只留归属的私有环境，公开机器记录只含脱敏结果。

系统超时／旋转、原生操作期间 Gate／设备接替、完整关联／签名负向、真实 Passkey 参与账号正式关闭及未知身份／凭据迟到回调仍需独立入口和证据。两秒路由取消观察窗口只证明该窗口，来源篡改负向不能替代错误 APK 的系统关联负向。缺第二台实体 Android 的 OEM 搬家保持 BLOCKED；iOS 本轮 SKIP，生产单列。当前 APK 和旧账号数据继续保留，本轮无提交／推送。接续顺序及命令约束见[任务单](auth-privacy-non-ios-plan.md)，脱敏准备记录见当前机器记录的 `batchPreparation`。

设置页增加“账号与注销”，连到现有 AuthScreen／实际注销状态机；没有增加业务模块。Android 12+ 的云备份、设备迁移规则明确排除所有应用数据域，保留 allowBackup=false、fullBackupContent=false 和 noBackupFilesDir／Keystore。Debug 变体加入已部署测试 RP 关联；release 变体不带这项测试关联。

客户端新增显式 RP 固定校验，适用于公开测试 RP 与 USB 私有 HTTPS API 分离的本轮环境。没有指定 RP 时仍校验 API 域名关系；指定后只接受完全一致的 RP。应用的开发 RP 配置要求 debug、显式开发 CA、独立 loopback C/V；正常证书链与主机名验证保留，任何服务端响应不能更改 RP 权限。负向测试覆盖其他 RP、子域、伪装后缀、非规范 DNS 与缺少开发信任。

原 r1 Flutter 分析、184项测试及 ARM64/x64 APK 结果保留；其摘要为 `143572c6b83e38d8da3e825600ad0d2e70afa8f40d250965d4fa9f3fe84db6d1`。r3 分析、185项测试及 ARM64/x64 构建 PASS，APK 摘要为 `a0af72d67d04c7e35fc9d64f50ce675e30c055232e1cfb19c13c86b31d414b7a`。新增双设备／V Gate 使用独立 boundary APK 和[夹具](../../apps/mobile/integration_test/auth_android_boundary_device_test.dart)，编译及各阶段执行以机器记录为准；不能将旧 r3 的运行结果改成 boundary 包通过。实际 debug 签名与已发布关联一致；Manifest 已实读备份排除与测试关联。

实际 App 夹具为 [auth_android_matrix_device_test.dart](../../apps/mobile/integration_test/auth_android_matrix_device_test.dart)，使用真正 `app.main()`、产品导航、HttpAuthApi、C/V／SQL 与原生 vault，不替换产品 API。只使用上一轮已验证的合成账号；测试恢复码仅存于单独加密测试 namespace，脱敏报告不含密码、恢复码、令牌、校邮、系统证明或 VM URI。宿主 [runner](../../tools/run-android-live-device.ps1) 核对 OWNED marker／已安装摘要后连接，阶段间只停启进程。

原 r1 注销申请／主动登录撤销、恢复码轮换及恢复码重设逐项保留。正常七天注销申请按真实服务器截止核对；正式到期关闭尚需独立场景。r3 原绑定核对、真实后台恢复和 Keyguard 前置已通过；Keyguard 只证明 secure/unlocked，不代表实际锁屏／重启／解锁。

真实 vivo Credential Manager 已完成绑定→取消→可发现恢复→设置新密码及完整确认恢复码→明确登录→再次绑定→移除。第一次成功绑定 PID 31563，取消 31855，恢复 32273，再次绑定 4847，移除 6621。实际 C 验签和 SQL 读回证明：两次创建提交，取消没有新增凭据；重设后旧会话 401、旧 Passkey 清空，不自动登录；明确登录保留同账号身份；移除保留当前会话。它们属于 r3 与原开发库的接受范围，完整系统边界矩阵仍未完成。

vivo 独立 vault 探针16项、3组实际跨进程及 Passkey codec5项 PASS。实际单 App 备份请求返回 `Backup is not allowed`，不改变手机备份配置。新增[迁移 runner](../../tools/run-android-vault-transfer.py)在手机生成合成密文，只将密文复制到模拟器；缺少原设备 Keystore 密钥时，读取和覆盖均拒绝，原字节保留且不创建密钥。模拟器独立探针卸载后，记录／密钥均消失；恢复旧密文仍拒绝。手机主 App 未卸载。这些证明原生存储边界，不代证完整 App 或 OEM 搬家。

完整 App 模拟器存储增量已 PASS：实际登录并保存初始身份草稿 PID 10418、独立进程恢复 PID 10530、真实卸载重装空状态 PID 10728、仅恢复旧密文缺钥拒绝 PID 11034。会话／草稿跨进程保持一致，草稿未创建身份；重装后无会话、草稿或待办，未自动登录；缺钥时产品读写均停止，显示安全存储不可用并无社区权限。仅恢复605字节密文，启动前后逐字节一致，无密钥导出。APK摘要 `5359c9516e110c2ed0d305da0708ab681dd464e31aeb01e21f6ddc579d8c32bd`。这只证明模拟器完整 App 和受控密文恢复，不代证 vivo 卸载、OEM 搬家或真机全流程。

宿主首次拒绝本地阶段的 `actualCV=false`，已修正为按阶段核对真实调用边界；随后 Windows ADB shell stdin 复制密文被截断，改用二进制 push／同 UID 复制，并在启动前核对原字节。前三项通过记录保留，恢复部分从本地加密检查点续做，完整结果才登记 PASS。原生迁移 runner 同步修正后重新实跑 PASS。

当前服务端包含同证书来源兼容及 V 无确认锚点结果核对两项修复，修改共享 V 查询后重新执行 R01 全量 Go／独立 SQL／race／vet、R03 实际 C/V 正式迁移与角色、R05 真实 Dart→HTTPS→独立 SQL，退出均0。旧来源修复回归保留原摘要，不代证新 V 查询。三份隔离 runner 使用自己的库；没有把手机运行库传给 reset fixture。

新的实际 App 双设备链已 PASS：手机正式注册与源会话 PID 27298／30006，模拟器明确密码登录接替 PID 7517，手机旧 Bearer 401、启动清会话／不自动登录、明确重新登录 PID 31801。同账号及身份累计数保持一致；该账号此时尚无身份，所以这项不代证有草稿或多身份的接替隔离。

新的实际 App V Gate 链已 PASS：模拟器发码 PID 8811、冻结确认 PID 8914、签名恢复后原确认与核对 PID 9014。C 一直 OPEN／generation1；V 从 OPEN2→FROZEN2→OPEN3。SQL 读回仍有1个未过期的旧代次 flow，确认／票据均0。旧 OTP POST 返回422 `OTP_EXPIRED`，原结果查询返回需重新验证，产品清原确认／申请，没有新发码、资格或会话。boundary v1／v2 APK分别保留自己的实际阶段版本；V 二进制摘要为 `3de2f9a86ba10f3fa6406903001b845d4123ec00b174ed9753a85767d01e6aa7`。

## 公开测试关联站点

用户明确允许创建并发布测试关联站点。已创建[独立公共仓库](https://github.com/zewbby/zewbby.github.io)，Pages 来源 `codex/android-passkey-associations` 根目录；发布提交 `1ff129f5a479c1bbd8cde59a4f0d27e9732fb9a4`，构建[完成成功](https://github.com/zewbby/zewbby.github.io/actions/runs/37310274552)。仅四个文件，源码副本见[静态目录](../../infra/passkey/android-debug-test-site)，细节见[RP方案](auth-privacy-android-passkey-domain-plan.md)和[域名证据](../../services/api/authlab/android-passkey-domain-verification.json)。

[公开 assetlinks](https://zewbby.github.io/.well-known/assetlinks.json) 实测正常 TLS、200 application/json、无重定向、内容一致；Google Digital Asset Links 返回 linked=true。实际 debug 证书 `FD:26:B2:76:CB:17:0B:F0:84:A9:32:D3:B3:91:9B:D3:AA:44:87:43:95:80:99:68:BD:D7:4D:DA:B8:73:89:DC`，只授予当前包名的 common.get_login_creds。依据：[Android关联要求](https://developer.android.com/identity/credential-manager/prerequisites)。真实 C 仅在本轮 OWNER 环境启用该固定 RP／Android origin，并正常重启就绪；V／数据库／私有 CA 不公开。

## 失败修复与未执行边界

首次分析发现新夹具两处 lint，修复后完整分析和184项测试通过。生命周期首次宿主控制不识别 vivo Android15 的 topResumedActivity 字段，App等待超时；修正识别后，Windows PowerShell 又把 am start 的正常“当前任务已带到前台”stderr警告当成失败。宿主改为对该命令检查真实退出码，并在读取阶段文件前检查存在；失败尝试保留，不重跑已通过的账号变更。最终重试结果见机器记录。

真实绑定首次先暴露客户端 Base64URL 证明字段共用2048字文本限制，改为对应3072／4096字节边界并补超限不发送测试。随后 C 返回422 `CHALLENGE_INVALID`：vivo 把同一受信证书哈希编码为无填充标准 Base64。C 从已配置的规范 Base64URL 哈希派生一个精确别名；不从请求扩充信任、不修改已签名 clientDataJSON。错误证书、混合编码、填充、空格、前缀大小写及修改签名字节仍拒绝。密码学测试和上述真实绑定通过。依据：[Android来源规范](https://developer.android.com/identity/passkeys/create-passkeys)；标准 Base64 是本轮实测兼容行为。夹具原失败清空 widget 导致黑屏，r3 改为失败保留产品页面；这项失败页面的真机复验单独保持未验证。

V Gate 首次恢复阶段先暴露夹具错误预期：未受理的旧 flow 返回 `OTP_EXPIRED`，并非已有确认锚点的 `REVERIFY_REQUIRED`。修正夹具后发现真正实现缺口：冻结拒绝故意不分配永久确认键，但原结果查询只看键，导致仍存在且已失效的原 flow 一直 `PENDING`。修复[查询](../../services/api/internal/authprivacy/eligibility_confirmation.go)核对 flow 安装归属、不可变代次和可信截止，并经 V 最终 Gate 事务复核；未知 flow／归属不符／仍有效的当前 flow 保持 PENDING，不分配永久键或签名任务。[SQL 测试](../../services/api/internal/authprivacy/verifier_gate_business_test.go)覆盖这些正负边界、冻结查询与零副作用。修复部署前原试验 flow 已正常清理，重试返回 `OTP_FLOW_INVALID`，这次原操作核对不计 PASS；仅重装明确归属的模拟器 App 后，使用新 flow 在仍未过期时完成上述完整链。手机没有重装或擦除。

仍需系统 Passkey 超时／迟到／回退／旋转、Gate／接替／提交未知及实际错误关联／签名负向；正式关闭／同邮箱再注册及不同账号草稿隔离已取得下文有限证据；未知待办迟到结果、真实 Passkey 关闭关联、OEM迁移及物理手机卸载恢复仍需独立验收。真实 IME、已列TalkBack导航／草稿恢复、新双设备登录和 V Gate 已实跑；完整 App 卸载／受控密文恢复只取得模拟器范围，锁屏／重启和 release 实际结果按下方及机器记录理解。iOS按用户指令本轮排除，生产分权／灾备／独立审计另列。完整非iOS矩阵、AC05整项、B02整模块仍未通过。

2026-10-06 首个 boundary 手机阶段返回503；核对发现旧初始化器退出trap已删除原一次性服务材料及项目数据库。失败尝试 APK `55c21bef266a4ca229463c73483244d2c99508684a05e6cf1366319b0dbeab15` 保留，不能登记为设备通过。修复[服务启动器](../../tools/run-auth-device-services.sh)增加显式 `AUTH_DEVICE_RETAIN=1`（默认仍清理自身资源）；在新 OWNER 环境实际验证初始化器 SIGTERM 正常退出后，C/V、双 evidence watcher、私有材料均保留且 TLS readiness200。新的开发端点／CA／合成账号另行验收，手机旧端点的加密状态保留，已接受证据不重写。

现行服务根为 WSL `/var/tmp/hnuhole-android-live-boundary-20261006`；构建／driver／缓存仍复用原 `D:\zewbbyTest\Hnuhole-android-live-faults-20261005` 和 WSL 原同名根。只操作带 OWNER、安装摘要匹配的测试包／库。SDK、AVD、缓存及可复用测试 App 按用户指令保留，私钥／配置／大日志保持本地私有。HnuHole 本轮未提交／推送，生产未部署；公开关联站点已按当次授权发布。

独立 release 边界探针已实际安装运行 PASS：非 debuggable Manifest 不含 debug asset association，run-as 被拒；即使携带同样调试 intent，原生 owned driver 仍不可用；显式开发 CA 和开发 RP 在实际 release Dart 中拒绝，普通客户端仍可创建。使用同一已验证 debug 测试证书签独立探针，仅用于本轮模拟器，不是发行签名或生产完整 App 批准。原缓存下载代理失效曾导致构建 FAIL，恢复带 OWNER 的隐藏下载桥后构建通过；未签名 APK 首次安装被 Android 拒绝，随后只用现有专用测试证书签名、核对精确证书 SHA 后实际验收通过。

物理 vivo 新生命周期包摘要 `77bb3cab25302818eb372c5fa87ab87ef429a11bc7cb82449788c286acf45312`；准备会话／原生身份草稿 PID27911，真实安全 Keyguard 锁定→用户解锁→App 恢复 PID28640 已 PASS，同会话及草稿保持。重启已由宿主启动次数102→103独立证明，App 重启后 PID16449 读回已 PASS，同权威会话与草稿保持；不能用 PID 改变代证系统重启。

OTP 续办增量已实现：正常清理已移除且从未建立确认锚点的 flow，原键 GET 仍按未知结果契约返回 PENDING；不将它改判为未提交。按现有注册协议第7节，V POST 的明确422无效／过期拒绝或410结果过期可持久授权用户主动结束原V操作，保留原私钥／公钥／槽位，随后另行请求新OTP。超时／503／输错OTP不授权，C未知提交、已有票据及其他待办不能绕过。状态机、重启后无瞬时错误的组件入口和负向回归已补；分析、188项Flutter及当前R05真实Dart→HTTPS→SQL PASS。负向回归发现禁止操作在原AuthStore写回边界被误报为存储失败，已在读取后先做业务校验，同时保留写队列内状态复核。实际模拟器四阶段均PASS，独立PID为11945／12063／12292／12402。宿主等待623秒后，只读确认正常清理已移除旧flow；原POST422 `OTP_FLOW_INVALID`、原GET仍PENDING，并保留原键和明确许可。新进程在没有瞬时错误时恢复按钮，明确结束不会发码；另行请求新OTP、确认后取得同公钥／槽位的真实票据。SQL发码预算事件仅增加两次，确认票据由0变1；C账号1、活跃会话1、已撤会话6全程不变。原发码／冻结APK与修复后核对／续办APK分别保留摘要，不把前两项改写成后两项版本；更新没有清除原产品状态。最终续办APK摘要 `fc3a5661072842f69984f472b4acf584709ee783e55bc9efe0a91eb769dceb87`。

## 真实 vivo 输入法验收

2026-10-06，vivo S18／Android15 使用手机已安装且启用的搜狗键盘，在产品昵称编辑器实际输入。最终 ARM64 测试 APK 摘要为 `fafc5a1906998edae43aea336d99205b8f15fab4a91f1a3aecbfa6518aaed521`，[夹具](../../apps/mobile/integration_test/auth_android_ime_device_test.dart)及[runner](../../tools/run-android-live-device.ps1)的分析／构建、实际写入／跨进程读取均 PASS。

| 实际检查 | 版本／进程与结果 |
|---|---|
| 原先人工输入的中文草稿确实已在原生存储保存，且在更新后的新进程恢复 | 诊断 APK `6a13e1f…`，PID29332，PASS；保留这个版本，不改写成最终 APK 的结果 |
| 真实设备触摸能聚焦产品编辑器，实际键盘传入组合态 | 最终 APK，PID7275，18次编辑事件、10次非折叠 composing；没有 tester.enterText 或伪造 TextEditingValue，PASS |
| 未确认组合文字不进入原生持久草稿，确认后的“输入法测试草稿”落盘 | 最终 APK，PID7275，PASS |
| 停启 App 进程后恢复同一权威会话及已确认草稿 | 同一最终 APK，独立 PID7968，PASS；没有创建身份 |

首版 APK `6dc311f…`、PID30999 的联合检查超时：UI显示最终文字，但组合态／存储条件未单独记录，因此这次写入保持 FAIL。诊断 APK 的写入阶段 PID32138 收到用户“点不动、键盘无法出现”的反馈，主动停止，保持 FAIL。实读当前 Flutter 源码确认测试绑定默认 `shouldPropagateDevicePointerEvents=false`，夹具遗漏开启，真实触摸被丢弃；这是夹具问题，不能推断产品保存失败或某输入法不支持 composing。修复只在本夹具期间开启真实触摸，并在 finally 恢复测试绑定；增加设备指针聚焦前置断言和安全的编辑／组合事件计数，之后才接受人工输入。宿主触摸检查首次也暴露 Windows 默认GBK解码中文UI失败，已改UTF-8；最终前置记录来自App自身通过的真实指针断言，未注入文字。

本次只能证明上述现有搜狗键盘及昵称草稿边界，不能代证其他输入法的组合态、TalkBack或全部设备矩阵。原 vivo AI 输入法已恢复，没有安装新键盘。测试成功后 runner 主动 force-stop 测试进程，随后同包新进程读回；这个停启不是账号退出／清除数据。初版、诊断版、最终版和失败记录各自保留，原生草稿及测试环境继续保留。

本任务没有修改产品或服务端实现；实际执行 Flutter分析、ARM64夹具构建、上述设备阶段和交接校验。此前188项Flutter测试及R01／R03／R05保留原版本与执行范围，本轮未重复执行这些完整套件。机器证据的 `realImeVerification` 分别映射 A12／N01／B02；AC05／B02整项仍 BLOCKED。

## 真实 vivo TalkBack 验收

2026-10-07 使用手机现有 Google TalkBack `17.0.1.926549743`，测试 APK 摘要 `914f96495f9d0017629a1d6246b85e69a4bf15c3929a590f0357c82fa3bff1a7`。[实际夹具](../../apps/mobile/integration_test/auth_android_talkback_device_test.dart)观察 Flutter 收到的真正平台焦点／激活动作，不调用 performSemanticsAction、不注入昵称或辅助功能特征；[宿主工具](../../tools/control-android-talkback.py)同时核对启用列表、vivo实际绑定的朗读服务及Google组件运行记录，保存原设置供恢复。[runner](../../tools/run-android-live-device.ps1)同APK运行 prepare／navigate／read，人工阶段不自动点击目标。

原服务跨日停止后，先启动现有Docker Desktop和明确归属的三个旧容器，保留原数据库卷、CA、配置和相同C/V二进制，未reset schema。按已有协议恢复C/V Gate后旧会话失效，prepare经真实登录页明确登录同一合成账号；PID7158确认昨天的中文草稿保持，身份累计创建数仍0。第一次Gradle构建因昨日专用下载代理离线而停止；使用已保留缓存的离线Gradle构建及Flutter分析PASS，构建镜像的wrapper在finally恢复，未修改仓库wrapper或下载整套工具。

导航进程PID15069记录47次实际平台焦点事件、6次tap和29个不同焦点节点，设置三项遍历→身份管理→添加身份→昵称焦点→取消→返回设置→设备与恢复凭据→返回均通过。独立进程PID15488确认同权威会话和“输入法测试草稿”恢复，并记录5次实际焦点事件、4个不同焦点节点。用户分别确认设置三项、昵称／草稿／取消及重启后的草稿朗读清楚、凭据页朗读正常。未创建身份、未执行账号退出、轮换或Passkey操作。以上有限TalkBack场景最终PASS；实际服务绑定、Flutter平台特征、平台动作、真实C/V及原生存储与人工朗读确认分别保留证据。

测试前辅助功能开启标志0、启用服务列表为空。结束后按基线恢复 `accessibility_enabled` 与 `enabled_accessibility_services` 两项；本轮启用的Google TalkBack及误开的精确vivo VisionAid组件均关闭。对任何其他新启用服务，工具会拒绝覆盖其偏好；没有修改朗读音量、录音或保存敏感朗读内容。原设置已实读核对恢复，同一APK、原生草稿及可复用服务／SDK／缓存继续保留。机器记录的 `talkBackVerification` 为当前证据入口。

初次导航等待PID14273中，宿主误按单行组件名称解析Bound services；vivo该节输出多行服务标签，改为实际绑定的TalkBack朗读项与运行组件共同确认。期间实际启用列表变成vivo VisionAid且Google TalkBack关闭，主动结束等待，不计设备接受。用户重新开启Google TalkBack后使用同一个APK完成上述导航／读回；这项失败不归因于产品状态或朗读实现，原日志及脱敏原因单独保留。导航成功后runner主动结束App进程，显示此前系统TalkBack页面，不代表账号退出。

此场景只覆盖已列的设置／身份草稿／凭据导航及恢复朗读。全部认证、密码／恢复码／错误页面、其他辅助服务和账号隔离需自己的场景，不能由本次导航泛化。对应A06／A12／N01／B02及X05／X08有限范围；完整AC05、B02和非iOS矩阵继续BLOCKED，iOS按用户要求排除，生产门槛保持独立。此前188项与R01／R03／R05保留原执行范围，本轮不重复执行。

## 正式关闭、同邮箱再注册与账号隔离

2026-10-07 在独立服务根 `/var/tmp/hnuhole-android-live-closure-20261007` 完成七个实际 vivo App 进程。正式 C12／V4 迁移、受限运行角色、实际 HTTPS C/V、普通关闭／签名回执 worker、V durable ACK 及真实 Android 原生加密存储均参与。结果为下表所列有限范围 PASS，完整 AC05／B02／非 iOS 矩阵仍 BLOCKED。

| 阶段 | 结果 | 实际 PID | APK SHA256 |
|---|---|---:|---|
| closure-draft-request | PASS | 20762 | `3d6e7616dfd4ba0e4037d83a08108c6780067e6e2e21aebb26a375f6a6a96482` |
| closure-draft-released | PASS | 790 | `e9ca35c1a38df495a3310ee213d9b5b9d68e3f980ca0e24ab94926fcdc1b5909` |
| closure-draft-register | PASS | 7451 | `16fed0c732c6367bc3d8c37b18f3ad202c7eea932e23b170e31fd9d52bffcd28` |
| closure-profile-request | PASS | 11321 | `16fed0c732c6367bc3d8c37b18f3ad202c7eea932e23b170e31fd9d52bffcd28` |
| closure-profile-released | PASS | 15060 | `16fed0c732c6367bc3d8c37b18f3ad202c7eea932e23b170e31fd9d52bffcd28` |
| closure-profile-register | PASS | 15534 | `16fed0c732c6367bc3d8c37b18f3ad202c7eea932e23b170e31fd9d52bffcd28` |
| closure-new-read | PASS | 16015 | `16fed0c732c6367bc3d8c37b18f3ad202c7eea932e23b170e31fd9d52bffcd28` |

第一周期覆盖零身份账号：真实产品昵称编辑器的“注销前草稿”落盘、七天注销申请、Bearer 清除、正式关闭及 V 资格释放、原 Bearer／密码／恢复码分别获得服务器 401、重复核对未恢复会话。同一精确邮箱经新验证码注册为新 accountId，新号身份累计数0、无冷却、新号草稿与身份待办为空、无继承 Passkey，实际昵称面板为空。本场景的字段由夹具自动填入，验证实际产品控件、服务和原生持久状态；人工输入／IME证据仍按此前独立版本理解。

第二周期先经产品界面创建三个身份并核对累计数3，再完成注销申请、资料擦除、关闭／释放及原凭据拒绝；同一精确邮箱再次经新验证码注册全新账号。新进程保持该新号权威会话，使用相同昵称“关闭身份1”创建新的身份 ID，标为原始身份且累计数1，旧 ID 未被复用。空的新号待办只证明账号隔离，不证明旧未知待办或迟到回调已验收。

时间通过 [构建覆盖](../../tools/prepare-android-closure-clock.py) 单调推进 Gate.Clock 与开发证据签发时间；[宿主控制器](../../tools/control-android-closure.py)只对精确归属的测试进程／数据库做停启及 SQL 只读核对，普通后台 worker 执行正式关闭与释放。两个周期 SQL 均确认原截止恰好七天、截止未改、密码与用户名擦除、身份资料擦除、恢复码／Passkey 为空、永久身份操作收据不变及 V 邮箱额度在 ACK 后释放。时钟原源码摘要和被测二进制摘要保存在 `formalClosureVerification.clockOverlay` 与 `testedBinarySha256`；本轮没有修改生产源码、手机／宿主时间或 SQL 截止，没有实际等待七天，不代证无构建覆盖的七日运行。

首包 PID18095 因 C Gate `INDEPENDENT_ANCHOR_FROZEN` 未开户；签名恢复后接续原 V 资格，冻结具体触发根因尚未独立证明。随后夹具失败分别为 PID24694 的 RELEASED 落盘后未等待界面帧、PID400 的登录幂等键错误使用16字节而非32字节，以及 PID3608 在输入框禁用时填码导致页面提示空验证码且 V VERIFY 计数0。随后 PID6929 的原收码流程因修复／安装等待而自然过期，普通清理后无新账号；补齐原确认核对与产品显式续办后再验。失败均保留原版本／日志及脱敏原因；修复只涉及夹具，成功阶段保留各自原 APK／源码摘要，未用最后一包改写早先阶段。中途安装被取消也保留原记录，未清手机数据或重复未知提交。

Flutter 分析、离线 ARM64 构建、覆盖版 runtime／authdev Go 测试及 vet、Python／PowerShell语法检查、实际设备阶段和交接一致性检查实际执行。此前188项 Flutter 及 R01／R03／R05保留各自原执行版本与范围，本轮没有重跑完整套件。原 boundary 账号的加密命名空间在本轮前后字节数与摘要完全一致，未导出明文、原始证明或私钥；工具、缓存和独立环境按用户要求保留。

对应 A03／A06／A08／A12／N01／B02 及 X02／X05／X06／X07／X08 的上述有限范围已记录。真实系统 Passkey 参与的关闭、未知身份／凭据待办的迟到结果、其余系统 Passkey／OEM矩阵仍需独立证据，iOS按用户指令排除，生产分权／灾备／独立审计保持单列。入口见 [机器记录](../../services/api/authlab/android-matrix-verification.json) 的 `formalClosureVerification`；本轮 HnuHole 未提交／推送。


## 2026-10-10 v16最终设备批次

本轮固定11项均有实际执行记录，接受结果为8 PASS／3 FAIL，未执行0项。B3四项全部通过；B4剩余失败只涉及NI-D01、NI-D02、NI-D03的原生关联拒绝归因。当前证据以矩阵`b3b4Verification.acceptedStageEvidence`、`currentNegativeVerification`和本批脱敏记录为准，历史4／11及“停止人工窗口”记录不再表示当前进度。

| 固定项 | 当前结果 | 实际证据与版本边界 |
|---|---|---|
| C01／C03／C04 | PASS | v16主App，PID19326；真实可发现断言预检、正常关闭／V释放、已关闭凭据C401、同精确邮箱新账号、原身份响应迟到及原结果查询不复活权限 |
| C02 | PASS | 保留v12完整App原版本；首次真实绑定UNKNOWN、正式关闭、同邮箱新号及同进程迟到响应 |
| D04 | PASS | 保留v6实际设备错误CA／hostname拒绝及前后正常HTTPS对照 |
| D05 | PASS | v16主App，PID11391；同一实际凭据产品移除后系统assertion被C拒绝，会话及恢复码可用性保留；另一凭据保留由v15未变后端实际SQL249范围补证 |
| K01／K02 | PASS | 保留v8／v9各阶段实际完整隔离App、卸载重装、精确旧密文缺钥拒绝、真实Keystore／AtomicFile及独立进程故障恢复 |
| D01 | FAIL | v16客户端固定RP不启动原生、实际服务器错误RP哈希422和原五分钟期限结果查询通过；原生错误RP只返回通用取消，具体关联拒绝原因未证明 |
| D02 | FAIL | v16同源码／同package批准证书控制组C204；错误证书无证明提交、SQL凭据数不变，但只取得通用取消，缺可归因的provider拒绝 |
| D03 | FAIL | v16正确证书且未关联package；公开HTTPS关联前置通过、用户确认继续、无证明提交／无新增凭据，但只有通用取消 |

提供方为`com.vivo.cipherchain` 2.6.0.3，框架为`com.vivo.credentialmanager` 15.0，Android15。三项原生回调均为`CreateCredentialCancellationException`，没有typed SecurityError或明确关联错误，当前provider进程logcat也没有可读日志。批准控制组与公开关联差异能排除部分前置问题，但不能把通用取消直接记为关联拒绝PASS。本轮不改接受条件，不重复同样的安装／取消来累计“通过”。后续只在取得提供方具体拒绝证据或具备可归因的实际provider／设备条件后补这三个原ID，无需重做已通过的关闭和移除组。

可复核入口：`tools/run-android-b3-b4.ps1 -Phase ni-d01 -Variant main`、`-Phase ni-d02 -Variant control|bad-signature`、`-Phase ni-d03 -Variant missing-package`。真实系统失败会保留原请求；ni-d01的实际证明拒绝后只查原结果，按原期限结束，不重放证明。相同phase旧证据必须保留后才允许新执行，不能覆盖历史PASS。当前不自动启动这些入口。

本轮修正宿主观察器对PowerShell命令末尾引号的识别，且仅对已核对包名／摘要／同一证书的隔离包原位更新；签名变化仍仅卸载隔离UID。两个宿主修正均未改变已编译产品APK。唯一合成标签定位及选择守卫原PID／阶段，真实UV和签名证明仍来自系统，未导出账号列表。源码及执行入口见`tools/control-android-b3-b4-device.py`、`tools/operate-android-b3-b4-isolated.py`、`tools/reveal-android-b3-b4-target.py`和`apps/mobile/integration_test/auth_android_b3_b4_device_test.dart`。

影响模块按台账原ID：A02／A04／A05／A07／A08／A09／A12／N01／N03／B01／B02；原跨模块范围不扩展。本批报告与台账把已失败执行和未执行分开。真实SQL最后为关闭账号12、待关闭0、已关闭秘密／Passkey／有效会话／身份资料残留均0，Gate OPEN。隔离批准签名已恢复，主App APK保持v16，未清理用户要求复用的环境／SDK／AVD／缓存，未提交或推送HnuHole。

固定非iOS清单24项累计19 PASS／3 FAIL／2 BLOCKED（NI-X01／NI-X02缺第二实体Android）；B6最终版本回归与交付NOT_RUN，iOS NOT_RUN，生产未批准。当前缺口不能写成“只剩iOS”。188项Flutter／249项SQL保持各自v15未变源码范围，v16原生12／Release13保留原执行记录，本轮设备收尾没有重复运行这些自动检查，也没有将旧版本PASS迁移为当前全模块PASS。

## 2026-10-10 v17 Google 对照重试

本轮只修正测试夹具：保留先前批准控制账号，经真实产品登录复用；不丢弃未知操作，不注入会话或绕过认证。源码为 `apps/mobile/integration_test/auth_android_b3_b4_device_test.dart`；宿主观察器 `tools/control-android-b3-b4-device.py` 增加实际Google活动组件记录，并只在原生已终止后短暂保留Google页面供诊断；`tools/control-android-b3-b4-provider.py` 备份／临时切换／精确恢复通行密钥和自动填充设置。签名切换工具仅对同证书已审阅隔离APK进行原位更新。

v17实际执行Flutter分析、三种ARM64构建和四包签名／仅签名载荷对比，结果PASS。共享188项、实际SQL249项保持v15未变产品范围，原生12项／Release13项保持v16原范围，本轮未重新执行；主包未更新，隔离包为v17。4次实际Google正向控制均返回 `CreateCredentialCancellationException`，原生成功数0；真实绑定提交计数保持19、数据库Passkey数保持3，未向C提交新的证明。最后一次统一自动填充配置后在人工验证前即结束。Google远端DAL正／负向检查通过，但不代证实际手机关联拒绝；具体根因仍未知。新的Google D01／D02／D03负向为NOT_RUN，累计三项仍保留v16实际FAIL，累计8／11保持。

证据为 `services/api/authlab/android-b3b4-v17-preparation-verification.json` 和 `services/api/authlab/android-b3b4-google-provider-verification.json`；原始App／设备／版本及SQL计数在有OWNER的matrix缓存attempt-28至attempt-31保留。影响模块A02／A04／A05／A07／A08／A09／A12／N01／N03／B01／B02，跨模块范围不变。已核对恢复原vivo两个credential设置及autofill设置，主App／数据／SDK／AVD／缓存保留。下次先取得具体Google／系统错误原因或合适实际提供方的正常创建，再在同提供方／同版本重跑固定三项，不再原样盲重试；不更改通过条件。
