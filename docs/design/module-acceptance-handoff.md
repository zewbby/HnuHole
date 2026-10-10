# 分模块验收与测试交接

> **2026-10-10 换机交接当前入口：**用户要求结束当前验收／排错、提交推送并交接全部任务缓存／测试秘密，远端确认后清理。B1＋B2 11 PASS；B3＋B4 8 PASS／3原执行FAIL；固定24项19 PASS／3 FAIL／2 BLOCKED，B6／iOS及生产未通过。Google直接诊断源码已保留，Java／debug APK编译成功但release及完整准备被D盘耗尽／WSL只读I/O故障中断；没有最终PASS manifest、未安装、API／系统UI未执行。手机原vivo凭据／自动填充已恢复。新机器先读[换机交接](auth-privacy-machine-transfer-20261010.md)及[交付／缓存清理实录](../../services/api/authlab/auth-privacy-machine-transfer-verification.json)，旧“缓存保留／未提交”仅为历史状态。

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

当前App已有auth、channels、navigation、账号安全与身份管理源码；“我的”登录后进入设置，可打开身份及账号安全。服务端已有本人身份表／API，尚无帖子、评论、聊天、通知、举报／审核主链；通道点击仍是占位，消息未接线。B02基础管理已实现、业务联动待实现，所有当前动态验收延期。B03有树骨架、B04有通道目录，其余按实际状态推进。

| ID／模块 | 规则与当前实现 | 开发后必须交接的关键场景 | 主要依赖 |
| --- | --- | --- | --- |
| B01 账号安全管理页面 | [账号](modules/accounts.md)／[恢复策略](auth-privacy-recovery-decision.md)；[管理页](../../apps/mobile/lib/src/auth/security_management_screen.dart)／[controller](../../apps/mobile/lib/src/auth/security_management_controller.dart)已接设备、退出、轮换、绑定／移除及原结果核对；Flutter未编译／运行 | R04/R05/R08/R09；controller28场景、widget4、恢复流程与嵌套路由回归源码；新鲜密码、新码一次展示隐藏后完整确认、进程重启原键核对、旧会话记录分流、接替／Gate／迟到围栏、系统Passkey闭环；没有邮箱接管 | A06/A07/A09/A12、N01–N03 |
| B02 预设身份／帖内身份 | [身份](modules/identity.md)；[基础管理报告](identity-management-validation-report.md)，**基础管理已实现，业务联动待实现** | R10：本人CRUD／默认头像、零身份可读、累计与日期、归属／并发／Gate／会话、成功和拒绝终态幂等／未知核对；首次昵称草稿持久恢复。未实现：首次公开操作恢复、帖内绑定及删除后的帖子／聊天／失败任务投影 | A01/A03/A06/A12；业务依赖B05/B06/B07/B08/B09/B10，媒体上传后续 |
| B03 入口／导航／列表／文字搜索 | [导航](modules/navigation.md)，二维树有骨架；feed／搜索未实现 | 无权限无节点；初始五项、拖动到达另两项；树返回与重启／新登录位置；通道feed／分页、返回不跳位；搜索标题正文标签、按通道分组与相关度／最新、无正文预览；分作用域历史去重／20词／换机同步；不可见内容不命中 | A11/A12、B02/B05/B04/B12 |
| B04 通道与自定义标签 | [标签](modules/tags.md)，七通道有代码；标签／筛选未实现 | 一帖一个通道、发布后不改通道；0–3自定义标签、允许空；当前通道多标签AND筛选与清筛选恢复；标签编辑不重发、不跨通道、不复活删除／下架内容；主题屏蔽不纳入首版 | A11、B03/B05/B11 |
| B05 新建帖子／草稿／后台发布 | [新建帖子](modules/post-composer.md)，未实现 | 标题／正文／图片限制与编辑确认保持；草稿按账号持久、重启恢复、保存失败留编辑页；受理任务参数／图片清单固定；未知结果查原任务、取消与成功竞争；退出后已受理任务按规则续办、注销／处罚停止未公开任务；身份删除后草稿可重选、已提交任务不可换身份 | B02/B04、A03/A06/A10、本地业务／媒体存储 |
| B06 帖子详情／赞藏／分享 | [帖子详情](modules/post-detail.md)，未实现 | 正文／评论分界与独立滚动；账号级点赞／收藏去重、失败回退与未知核对；删除扣正确数量；分享与深链登录后直达、外链预览不泄露标题正文；作者身份联系、图片顺序／缩放／主动保存 | B02/B05/B07/B09、媒体、深链 |
| B07 评论与回复 | [评论](modules/comments.md)，未实现 | 实际目标关系、同帖固定身份；分页定位与一层缩进；浏览不自动重排／插入别人新评论；本人成功定位；主评论删整楼／回复删本条；文本／单图；未提交输入离帖清、已受理任务重启核对；删帖后不可发送、失败入口在系统通知 | B02/B05/B06/B08、A10 |
| B08 消息中心／互动／系统通知 | [消息](modules/messages.md)，未实现 | 身份切换防串箱、隐藏／置顶／新消息／未读排序；打开实际对象才清未读且换机同步；当前身份备注／本地正文搜索；点赞按内容合并，系统通知按时间逐条且同类各占一条；失败评论不混发言；目标失效、定向跳转；推送默认不展示内容身份、预览设置与当前会话免打扰 | B07/B09/B11、A06、推送平台 |
| B09 私信与会话 | [私信](modules/messaging.md)，未实现 | 双向身份对跨帖唯一；首次来源／首次一条文字与图限制；撤回／删除不恢复首发额度；接收端持久后ACK、空间不足不ACK、重启幂等补投；本地历史不由云端恢复；接替不丢旧机文件；两分钟撤回／未知核对；账号级拉黑但前台不暴露其他身份；不对外提供已读／在线／输入信号 | B02/B05、A03/A06/A10、本地存储／媒体 |
| B10 我的／个人内容／设置 | [个人内容](modules/personal.md)，我的→设置→身份／账号安全已接；个人帖子／收藏、黑名单和通知设置仍未实现 | 私有帖子／收藏页签与位置；草稿／发送中／失败／成功卡片不重复；删除身份内容归属规则；全身份收藏共用、原帖删除占位可移除；保存／删除故障；设备／身份／黑名单／通知设置各归属正确 | B01/B02/B05/B06/B08/B09 |
| B11 作者编辑删除／举报／审核／处罚申诉 | [管理](modules/moderation.md)，完整流程未实现；C restrictions不是审核后台 | 作者权限与编辑未保存弃改、整体保存通道不变；删帖停讨论不关闭已有私信；举报未知结果查原工单；私信证据授权／快照与缺口；双角色、原处理人回避、不泄露邮箱／其他身份；同事实／多审核员竞争不重复处罚；处罚期限与恢复、申诉次数与唯一待处理、通过仅撤对应处罚 | 全内容模块、A08、独立后台／证据／通知 |
| B12 热度／热榜／浏览量 | [排行](modules/popularity.md)，未实现；权重／衰减等仍待设计收口 | 整5分钟、近7天前20、先过滤后补位；停留不重排、返回刷新失败保留仍有效旧榜；同分稳定序号；正文打开才计数、账号每日去重、作者自看不计；热度排除作者自互动、账号级人数去重、删除／取消后重算 | B03/B05/B06/B07/B11、A10；具体参数实施前核对真正待决项 |

上述是已有规则的测试摘要，限制数值、状态与删除范围以所链接模块为准。后续新增业务需在此表附上真实源码／测试入口；目前不能提供不存在的帖子／私信runner或API命令。

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
| P05 CI、完整发布、平台与外部服务 | 尚无 `.github` 工作流；正式签名／生产端点等未配置 | 可重复CI和完整契约／DB回归；Android/iOS标准release签名／安装／升级；固定端点与平台关联、推送／媒体／本地业务加密等实际集成。未选的供应商／云区域等仍需实施前设计，不能仅填测试通过 |
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
