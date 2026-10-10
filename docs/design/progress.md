# 设计进度与剩余工作

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

## 历史记录与验收目录

以下记录保留原日期、版本及证明范围；“缺Flutter／未验／未提交”只描述当时状态，现行结果见顶部入口和机器台账。

> **2026-10-03 本机接续验证（历史）：**从远端codex/auth-privacy-handoff的87e603c3f54b2fc08d1501dd3a0d7db5b70d17cc拉取。AC04的B02 R03/R05测试源码已补；**Go全量SQL/race/vet、四份OpenAPI完整校验及R03实际非owner C/V HTTPS/mTLS进程验收通过**。R03覆盖身份CRUD、成功和拒绝回执、实际服务重启、Gate冻结/恢复后新会话核对、迁移10→11及缺表/缺DML拒绝。实际启动发现权限检查format()参数未指定类型，已补$1::text并通过实际进程和匹配race/vet复验。Go位于WSL /usr/lib/go-1.22/bin；PG/Docker可用，固定Goose仅在本次临时目录构建。**Flutter/Dart入口未找到，R05真实Dart→SQL及设备/原生Passkey仍BLOCKED/NOT_RUN，B02整模块未PASS。**AC01 V Gate、AC02身份整账号关闭仍未实现。逐项结果、失败修复/复验和源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。下方旧机器/版本和缺Go/未补B02测试链描述是历史状态。

> **2026-10-03 远端接续交付：**用户已授权将当前匿名收口材料、运行时／设备／B02源码与测试提交并推送到 `origin/codex/auth-privacy-handoff`，由另一台机器继续。先读[机器接续入口](auth-privacy-machine-handoff.md)，再按[匿名清单 AC01–AC06](auth-privacy-closure-checklist.md)执行；提交／推送不代表缺口已修复或动态验收通过。下方“未提交／推送”是历史记录，最新交付状态以本次提交及远端结果为准。

> **2026-10-03 匿名分支范围纠正：**本分支以匿名方案及其基础实现收口，停在 B02，不进入 B05/B03 等完整业务片。当前有限缺口和结束条件见[匿名收口清单](auth-privacy-closure-checklist.md)：先补 V 独立 Gate、现有身份的整账号关闭联动，再核对隐私边界、补真实测试链与集中验收。B02继续登记为“基础管理已实现，业务联动待实现”，动态／设备未执行项保持待验；本段覆盖下方历史开发顺序，不改写历史测试证据。

> **2026-10-03 B02身份管理基础：**本人身份列表／创建／改名／删除、默认头像和我的→设置入口已写入；注册零身份仍能浏览，落实最多3个／不能删最后一个、累计创建及六个月／30天限制。全部访问最终Gate／会话／归属复核，账号串行及成功／拒绝终态回执保护未知提交与迟到重试。**基础管理已实现，业务联动待实现；编译、SQL、Flutter和真机验收待执行。**帖内绑定、旧帖／聊天投影随业务模块，自定义头像随媒体实现。见[任务单](identity-management-plan.md)、[报告](identity-management-validation-report.md)、[机器记录](../../services/api/authlab/identity-management-verification.json)和[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。后续按[匿名收口清单](auth-privacy-closure-checklist.md)补齐基础缺口并交付，不进入完整发帖／列表业务片；未提交／推送。

> **2026-10-02 设备／恢复凭据／原生Passkey：**当前／最近接替设备及退出、恢复码轮换全量确认与持久结果核对、Android/iOS绑定／两步移除／可发现恢复已写入工作区；runtime固定RP／签名origin已接。真机vault／跨进程与冻结／接替／迟到响应测试源码已补。**编译、动态和设备验收待执行，RP／平台关联配置未提供。**见[任务单](auth-privacy-device-credentials-passkey-plan.md)、[报告](auth-privacy-device-credentials-passkey-validation-report.md)、[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。缺工具不停止指定功能开发；源码完成不计验收通过；未提交／推送。

> **2026-10-02 用户决定可先开发后集中分模块验收：**无需等待另一电脑；[模块测试交接](module-acceptance-handoff.md)及[机器台账](module-acceptance-ledger.json)分别列出已有实现的待验／待复验、原生未验、尚未实现业务、安全与生产缺口。[AGENTS.md](../../AGENTS.md)要求每个功能任务结束同步未测项、原因、测试入口和影响模块。动态／设备验收可延期，代码实现不计为验收PASS；可用的必要检查仍按实际执行记录。后续任务照已收口规则开发并持续维护台账，生产放行前完成相关模块及跨模块验收。以下历史“先验收再进入下一片”的顺序已被本项更新，未通过记录不改写。

> **2026-10-02 T0–T6 实施已落盘，验收未完成：**只基于 `codex/auth-privacy-handoff`，按[C/V 开发服务与目录闭环计划](auth-privacy-runtime-business-integration-plan.md)加入正式迁移／受限角色、两个实际服务入口与开发引导工具、持久 worker、C Gate 同事务目录读取／续期、移动端权威截止持久更新和实际 cmd 一次性 runner。记录见[本轮报告](auth-privacy-runtime-business-integration-validation-report.md)及[机器记录](../../services/api/authlab/runtime-business-integration-verification.json)。本机缺 Go／gofmt、Docker／PostgreSQL 与 Flutter，动态命令因缺工具失败，尚未编译／验证 SQL／race／真实链路，也未提交或推送。下一步在现成工具环境完成格式化、生成漂移、全部回归和实际进程 runner，不把历史通过记录外推到本次改动。[第40轮](../discussions/2026-10-01-grilling-round40.md)确认的 V Gate 另片、全新开发库＋临时升级、Windows＋WSL2 及设备并行范围不变；大型运行时未重下，后续顺序以本段为准。

> **2026-10-01 原生存储与真实 C/V 联调：**真实 Flutter→隔离 C/V HTTPS／PostgreSQL 已跑通注册、会话接替／续期、未知结果核对、Gate 冻结／签名恢复和注销释放 ACK。Android 原生／测试编译与测试 APK 已完成，新增 16 项设备故障测试和跨进程探针；iOS 标记同步重试及跨 engine 串行修复，macOS 文件系统回归通过。本机未做设备执行、完整应用构建或 iOS Keychain 验证。用户要求删除大型临时验证运行时、缓存和 APK并推送远端给另一电脑复验，命令与实际证据见[本轮报告](auth-privacy-mobile-native-integration-validation-report.md)及[机器记录](../../services/api/authlab/mobile-native-integration-verification.json)。下一步先补平台验收，再做设备／恢复凭据管理页面和原生Passkey；生产路由授权接Gate、迁移、业务清理／通知及独立安全验收继续待做。

> **2026-09-30 移动端核心认证状态机（历史节点）：**指定分支 `codex/auth-privacy-handoff` 已接入校邮注册、恢复码隐藏后完整确认、密码登录、权威恢复／活跃续期、七天注销和持久结果核对。退出先确认登出标记持久化，再删除Bearer并以独立能力异步定向撤销，旧任务不影响新会话。系统安全存储适配器及Android/iOS工程已加入；完整Dart／TLS／组件回归和Go故障回归见[本轮报告](auth-privacy-mobile-auth-validation-report.md)及[机器记录](../../services/api/authlab/mobile-auth-verification.json)。下一步先做原生构建、真机安全存储故障与真实C/V整链联调，再补设备／凭据管理页面。原生Passkey、生产路由／迁移与业务授权接Gate、注销清理／通知、运营分权及独立安全验收继续待做。

> **2026-09-30 恢复凭据管理隔离实现（历史节点）：**当前分支 `codex/auth-privacy-handoff` 补齐新鲜密码复验恢复码轮换、可选 Passkey 的绑定／可发现恢复／两步移除，以及受限凭据清单。管理权限绑定原凭据版本、同一会话、固定RP策略及Gate代次，最终事务再次复核；普通变更保留其他凭据和当前会话，重设／关闭撤全部旧Passkey。交付与最终验证见[本轮报告](auth-privacy-recovery-credentials-validation-report.md)和[机器记录](../../services/api/authlab/recovery-credentials-verification.json)。下一步进入移动端安全存储、持久结果核对／登出待办及完整认证状态机；生产路由／迁移、真实平台Passkey演练、业务数据清理／通知及生产安全验收继续待做。

> **2026-09-30 恢复码与七天注销隔离实现（历史节点）：**在登录／会话切片之上加入恢复码证明、唯一重设意图、最终密码重设与无秘密结果核对，以及七天注销申请、截止前主动登录取消、到期关闭、受限状态与释放收据。密码重设不登录、不取消注销、不解除处罚；封禁受信命令即时撤会话，迟到封禁不能取消到期申请。新增授权与清理继续经过 Safety Gate。交付范围与证据见[本轮报告](auth-privacy-recovery-closure-validation-report.md)和[机器记录](../../services/api/authlab/recovery-closure-verification.json)。可选 Passkey、恢复码轮换、移动端、业务数据清理／通知和生产接入仍待做。

> **2026-09-30 登录与会话隔离实现（历史节点）：**在已落地的 Authorization Safety Gate 上，C 实验包增加用户名密码登录、单设备接替、权威会话恢复／同令牌续期、最近替代设备读取与独立撤销秘密定向退出；有界清理保留幂等墓碑与最终服务端到期后的摘要窗口。[本轮报告](auth-privacy-session-lifecycle-validation-report.md)和[机器记录](../../services/api/authlab/session-lifecycle-verification.json)说明真实 SQL／HTTPS／并发／冻结验证。下一步是独立恢复与七天注销的权威事务、处罚写入口，再接移动端和生产路由／迁移。`PENDING_CLOSE` 登录现先 fail closed，待注销截止模型接入后实现截止前主动取消；生产安全验收仍未完成。

> **2026-09-30 第 0 步隔离实现：**Authorization Safety Gate 已接入现有 C 注册意图、最终开户与初始会话、隔离认证读入口；含持久冻结、库外签名证据／锚点、可信时间高水位、授权代次及受限签名恢复。5 秒回退／5 分钟证据、旧快照、跨连接和提交途中冻结等故障测试见[本轮报告](auth-authorization-safety-gate-validation-report.md)。第 0 步隔离验收后可进入用户名密码登录＋完整会话管理；生产独立授时、恢复运营、真实灾备、人类审计仍未完成。

> **2026-09-29 第 0 步设计历史：**Authorization Safety Gate 设计在第 39 轮收口：FROZEN 时所有认证读写 fail closed；单个受限恢复角色执行显式恢复，不采用双人控制；允许 5 秒时钟回退抖动；可信证据 TTL 5 分钟。后续实现状态以上方 2026-09-30 记录为准。

> **2026-09-29 当前实现进展：**用户已授权进入 Phase E。[实验切片](../../services/api/authlab/README.md)在首条数据库验证后加入校邮发码／确认、最新码与预算、退役后的原确认续办、双方 HTTP／mTLS 和注册密码准备。实现、真实 PostgreSQL／TLS 故障验证及剩余门槛见[本轮报告](auth-privacy-eligibility-http-validation-report.md)。生产路由／迁移、用户名密码登录、独立恢复、七天注销、移动端及生产安全验收继续待做。

> **2026-09-28 规格阶段背景：**每次注册校邮收码，用户设置私有用户名和独立密码；日常用用户名和密码登录，不通过邮箱查找旧号。同一精确邮箱地址同时最多一个有效账号的配额依赖 V 按协议执行；正式注销后释放配额，再次收码建立全新账号。旧号找回需事先保存的独立凭据，邮箱验证码不能单独重置。V/C 通过本次资格槽位协调配额；串通或共同泄漏时能连接邮箱与账号。架构见[认证与隐私架构决策](auth-privacy-architecture-decision.md)，注册、退役与释放见[协议 v1](auth-privacy-registration-protocol.md)。[恢复策略](auth-privacy-recovery-decision.md)、[逻辑数据／API 契约](auth-privacy-data-api-contract.md)与[内部跨方威胁模型](auth-privacy-threat-model.md)已成稿；[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)、[C OpenAPI](../../packages/openapi/community-auth-api.yaml)与[迁移设计](auth-privacy-database-migration-design.md)已成稿；[固定向量与静态复验](auth-privacy-protocol-vectors.md)、[独立评审输入包](auth-privacy-security-review-package.md)已整理；仍须生产库／实际SQL验证、双主体运营与**独立**安全评审，生产认证代码未开始。

盘点：2026-09-20。消息身份切换展开 v2、收到的 v2、我发出的正常状态 v1、系统通知失败详情 v1、顶部失败提示 v1、系统通知时间流 v2、举报处理结果详情 v1、违规处理通知详情 v1、申诉待复核详情 v1、结果通过 v1、结果未通过 v1 均已确认。首次申诉 v2、补充材料 v1、私信举报选择原因配色 A v1 已生成待评审。新页逐张试不同黑底配色，用户明确锁色后才统一。直接给图、不附 prompt；用户同意页面定稿就直接制作下一张。已确认不表示已实现或图稿齐全。

## 2026-09-29 认证实现接续

用户已明确授权校邮确认、退役后的原确认续办及双方 HTTP／mTLS。实现与故障验证见[本轮报告](auth-privacy-eligibility-http-validation-report.md)，当前代码和实验迁移均在独立验证目录。此后按 Phase E 继续登录、会话与独立恢复；生产门槛另行验收。

## 开发阶段（2026-09-23）

- 用户已暂停 UI 设计讨论，进入工程方案阶段。
- 已确认工程基线：Flutter + Dart 移动端、Go 服务端、模块化单体后端；记录见 [ADR 0001](../adr/0001-engineering-baseline.md)。
- 已确认通信与持久化基线：`net/http` + `chi`、PostgreSQL + `pgx`/`sqlc`、REST/JSON + OpenAPI、前台 WebSocket 事件、Drift/SQLite 与系统安全存储；记录见 [ADR 0002](../adr/0002-communication-and-persistence-baseline.md)。
- 已确认仓库、认证和首条切片：单仓库 monorepo、`goose` + `oapi-codegen`、服务端不透明会话令牌、宿主机 Flutter/Go + Docker Compose 基础设施，以及文字内容主链；记录见 [ADR 0003](../adr/0003-repository-auth-and-first-slice.md)。
- 首条切片直接实现基础导航树，拆为两次开发任务；未登录只显示树入口外壳，已有账号登录或新账号注册并建立会话后，完整目录校验通过才加载节点；目录失败保留无节点树并可重试；默认无热度时先露出吐槽、避雷、安利、搭子、情感。
- 首条切片保留可选 `#标签` 字段但暂不实现输入、复用和筛选交互；已发布内容和身份写入服务端数据库，本机草稿写入 Drift/SQLite，重启后须可恢复。
- 任务 1 的通道目录 API 定为 `GET /api/v1/channels`，采用英文不可变 `code`；迁移、API、客户端加载和树交互四层自动化验收纳入首批测试。代码骨架已建立，但测试和生成链因本机缺少 Go/Flutter/Docker 尚未执行。
- 通道编码和冷启动顺序已固定为 `vent`、`warning`、`recommendation`、`buddy`、`emotion`、`mutual_help`、`technology`；目录接口成功/未授权/暂不可用分别使用 `200`/`401`/`503`，OpenAPI 源文件为唯一契约。
- 首版可能超过 10000 用户；该规模不改变 monorepo 决定，容量和运行时扩展另行设计。
- 已确认 CI、测试、开发验证与部署基线：本地 Git + GitHub Actions、Go 单元测试 + Docker PostgreSQL 集成测试、Mailpit + 开发验证适配器、容器化无状态 API + 托管 PostgreSQL + S3 兼容对象存储；记录见 [ADR 0004](../adr/0004-ci-testing-email-and-deployment.md)。
- 用户不熟悉 Git/GitHub；后续提交、推送和 Actions 检查会提供逐步操作说明。
- 本地 Git 已初始化为 `main`，当前开发分支为 `feature/engineering-baseline`；远程 `origin` 已绑定 `https://github.com/zhubaozhenshuai666-lang/HnuHole.git`，并跟踪对应远程分支。
- 尚未确认：聊天本地加密方案、生产推送供应商、具体云厂商/区域、CI 密钥与发布流程、第一条切片之外的功能顺序。
- 已建立任务 1 的 Go API、PostgreSQL 迁移/OpenAPI 契约和 Flutter 入口树代码骨架；本机没有 Go/Flutter/Docker 可运行环境，测试与生成链尚未执行。
- 后续认证切片范围已确定：V 的每次新注册校邮验证与配额、C 的新号创建和用户名密码登录、事先设立的独立恢复方式、服务端会话恢复／退出，以及登录后加载通道；首次注册不自动创建身份，无身份账号仍可浏览。[协议 v1](auth-privacy-registration-protocol.md)、[恢复策略](auth-privacy-recovery-decision.md)及[数据/API 契约](auth-privacy-data-api-contract.md)已成稿，当前已按新规格开展隔离实现；生产接入仍须完整链路验证、双主体运营及安全评审。
- 认证主链的行为边界已补齐：账号可无身份浏览；首次公开发言时才创建/选择身份；服务端接受有效发送任务时原子绑定帖内身份，后续主评论和楼中楼回复直接复用；身份设置前保留原操作输入。主动退出保留按账号隔离的本机草稿和文件；恢复 `401` 清令牌与节点，`503`/超时保留本地状态重试；新设备接替旧设备返回 `401/session_replaced` 并保留本地文件。
- 旧“四接口、验证码确认即恢复旧号”设想已废止。新客户端认证主链须覆盖 V 的验证码申请／确认、C 的新号注册、用户名密码登录、独立凭据恢复、会话恢复／退出；通道目录仍为 `GET /api/v1/channels`。跨方资格、退役与释放的流程见[协议 v1](auth-privacy-registration-protocol.md)，精确调用契约见[数据/API 契约](auth-privacy-data-api-contract.md)，精确schema见[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)及[C OpenAPI](../../packages/openapi/community-auth-api.yaml)。认证成功后恢复原入口意图；V/C 各自使用本方幂等与重试规则，不能跨方共享幂等键。
- 2026-09-23 至 2026-09-25 的邮箱唯一登录和稳定匿名凭证方案已被当前决策替代，原始过程仅见[历史 ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)及[第三十二轮](../discussions/2026-09-23-grilling-round32.md)。仍有效的产品规则：生产 V/C 必须实质独立；禁言可申请注销但正式注销后随旧号终止；封禁期间不可注销，缓冲期内新封禁取消申请。现有生产服务尚未接入这些认证路由；隔离包已实现发码、确认、账号创建和初始会话签发。
- 注册验证码申请的邮箱枚举保护已确认：格式和域名合规的申请对配额状态返回相同受理状态及通用提示；验证成功后才可能签发新号资格，不得返回已有账号或恢复旧号。实际投递、时延、限流侧信道及用户名登录枚举风险仍待安全评审。
- 2026-09-26 用户选定“校园资格与旧号控制权分离”的架构方向：恶意 V 可伪造新资格或阻止注册，但不能只靠邮箱接管已有账号。V 持邮箱→槽位，C 受限认证库持槽位→账号；共同槽位使串通可直接关联。旧 [GPT-6 交接](auth-privacy-gpt6-handoff.md)仅作为问题背景，当前可执行决策见[认证与隐私架构决策](auth-privacy-architecture-decision.md)。
- 2026-09-27 完成注册、退役与释放的[协议 v1](auth-privacy-registration-protocol.md)：槽位由客户端一次性公钥散列导出，C 验真实挑战的持钥证明；私钥丢失时先退役未开户旧槽位，正式注销后 C 保留最小终态拒旧票重放。协议尚未实施或经过独立安全审计；恢复体验及数据库/API 的规格见下条进展。

- 2026-09-27 完成[独立恢复策略](auth-privacy-recovery-decision.md)与[逻辑数据／API 契约](auth-privacy-data-api-contract.md)：恢复码注册前确认，Passkey 可选；全凭据丢失则旧号与同邮箱配额都无法找回。V 当前槽位全局唯一，C 关闭与释放事件共事务；注销状态秘密须申请前保存。仍未实施或通过独立安全评审。

- 2026-09-28 完成[内部跨方威胁模型](auth-privacy-threat-model.md)与规格复核：注册资格升级为限时 `REGISTER/V2`，严格校验持钥公钥；重设意图须原子替代且旧凭据证明在账号锁内复核；注销截止使用取锁后的数据库实际时间，申请后取消尚未公开的任务；登出及重设未知结果有重启后的安全核对路径。灾备还须守住时钟与受信钥单调性。该威胁建模轮次只改文档；当时 OpenAPI／迁移及其他门槛未完成，后续规格进展见下条。

- 2026-09-28 完成[V的5个操作](../../packages/openapi/verifier-auth-api.yaml)、[C的22个操作](../../packages/openapi/community-auth-api.yaml)和[数据库迁移设计](auth-privacy-database-migration-design.md)：固定二进制票据、独立16B安装ID／32B操作键、原结果核对、恢复管理、同令牌续期和内部mTLS边界均有机器可读schema；表约束、锁顺序、签名outbox、留存及演示会话升级顺序已写清。幂等原结果到期原位收缩为无身份永久摘要锚点，迟到旧操作不能重执行。三份OpenAPI通过完整规范静态校验；未创建／执行认证SQL，未写认证代码，未通过独立审计。该轮之后的向量与评审包进展见下条；双主体运营和真实客户端／迁移证据仍待核实。

- 2026-09-28 完成[固定协议向量与内部静态复验](auth-privacy-protocol-vectors.md)及[独立安全评审输入包](auth-privacy-security-review-package.md)：8组协议有效签名、3组RFC控制在PyNaCl1.6.2与Node24.11.1/OpenSSL3.5.4中逐字一致，11组错误签名拒绝。4组裸验签弱点反例说明库Verify不能代替公钥准入；明确A/R均规范、非单位元且处于主素数阶子群的项目配置。22组点、规范编码、域分离及时间算术已核对；12组事务案例未执行，独立审计未开始，未写认证代码或SQL。下一步确定实际评审者和V/C运营关系；获实施授权后以最小SQL约束、注册／退役竞争及提交后签名outbox产生真实证据，避免继续只扩文档。

- 2026-09-28 将19份认证评审材料锁定为提交 `41fba7761035ee5aafb0e3beb55bf7b8d21f539a` 的[送审快照](auth-privacy-review-snapshot.json)，导出逐文件哈希与压缩包并核验来源；[评审包登记](auth-privacy-security-review-package.md)已填入可自主确认的版本项。用户报告学校邮箱可用；已解释V是验证码与注册配额服务、C是Hnuhole后台、独立评审者是未参与设计的安全工程师或机构。V/C具名运营安排与独立评审仍待确认，不能因有校邮账号即认定V已独立运营。未外部发送、未签署独立结论，未进入认证编码；下一步先明确服务搭建和权限安排，再落实真实评审，新增模板不能补齐这些事实。

## 当前阶段

- 2026-09-28 将修正后的21份规格／评审材料锁定到 `05dc4a4b88797f5532829c1f2953484f7ac86c90`，形成[新快照清单](auth-privacy-review-snapshot.json)及逐文件摘要／压缩包；旧 `41fba77` 初审快照保留不改。新包包括退役ACK修正、AI交叉评审和本轮接口静态记录；版本登记补充不改已锁定协议或向量。实际SQL／服务和G1–G6缺失证据仍未验收。

- 2026-09-28 根据用户确认登记邮箱可用、C 正式后台未建、暂无人类独立评审者；完成不继承前文的新上下文 subagent 初审并记录[AI 交叉评审](auth-privacy-ai-cross-review.md)。确认并修正 RETIRED 收据缺少 V 持久 ACK 的规格闭环，新增内部退役收据入口，V 当前 6／C 22 个操作；保留原固定签名帧与向量。拉取／推送、原确认续办、重签、单调 ACK、清理与灾备均补入验收。评审 agent 对实际补丁回归复核结论为规格阶段 APPROVE WITH NOTES；三份 OpenAPI 结构及新请求／ACK Schema 已[静态核对](../../packages/auth-protocol-vectors/retirement-ack-static-verification.json)。Claude 九份固定源材料披露已获授权，调用因本机 CLI 未登录失败，没有模型评审结果；用户随后决定本轮先不做 Claude，采用 subagent 规格评审，不再等待外部登录。实际 SQL／服务、独立运营证据和人类第三方结论未验收，本轮未写认证代码。

- 当前新图（2026-09-21）：长按对方图片 M v1 重试生成成功，待评审；黑底灰青，同组两图仅单张选中，菜单删除／举报。无新增业务，额度失败不再是当前阻塞。
- 最新定稿：首发身份选择 L v2 紧凑弹框，已归档；L v1 大字大框被否决，灰褐不锁全局。J v2 居中撤回＋重编辑已确认，点击直接回填，不自动发送；K 回填图不再制作，替换确认不再提问。重编辑期限与本机临时原文清理仍待细化。
- 本轮定稿：长按本人文字 I v1 页面经用户“可以，下一个图”确认，复制／删除／两分钟内撤回结构有效，灰橄榄不因此锁为全局配色。
- 已认可的候选配色：长按对方文字 H 的黑灰＋低饱和蓝灰，用户明确要求纳入考量，未锁定全局主题；后续新图仍须换色。该答复未额外声明整页定稿。
- 此前试稿：首次私信等待回复 G、举报进度森林绿 v3 与陶橘暖砂 v2 均待明确评审；正常聊天 F 配色被否决为花哨，不作主题基准。
- 举报进度旧 E 版只改小图标被否决；C v2 已修订左右聊天，D v1 证据预览已交付。举报进度仍从系统通知进入，不改变提交后返回原页的规则。
- UI 评审同步检查业务影响；收到的 v2 图稿及对方头像／昵称随整条提醒回原帖已确认，消息与私信模块已同步；身份隔离、未读及固定身份回复规则不变，详见[评审记录](../discussions/2026-09-20-replies-ui-review.md)。
- 首版标题手写、文字搜索；旧生成和意图理解方案已清理。首版无视频、投票、聊天迁移或交易功能。
- 注册邮箱固定后缀、允许前缀别名、禁止空格、区分大小写；资格无周期复核。日常用户名密码登录、独立凭据恢复、单设备和三十天会话已定。
- 发帖可取消上传发布；旧帖编辑退出丢弃修改。评论回复关系可跳转、本人成功滚到评论区域顶部、分页约五十条已定。
- 离线待收持续保存到本地确认；首次保留图片入口并在发送时限制。热榜整五分钟更新、权重不公开已定。
- 第二十轮十项已确认：私信不备份导出、未发送文字本地保留、正文可搜、图片可主动保存、推送范围、拉黑在途消息、举报进度、删帖无回收站、通道热度删除口径、浏览量不参与排名。第二十一轮已收口：不做交易、违规昵称头像可重置、下架帖不允许整改重审；分类专项也已收口。UI 设计暂缓；认证主链当前只推进实施前规格化与安全评审。

## 模块现状与剩余

| 模块 | 已确认主干 | 尚需处理 |
| --- | --- | --- |
| [账号](modules/accounts.md) | 每次注册校邮验证、用户名密码登录、恢复码必配与可选 Passkey、资格协议 v1、逻辑数据/API 契约、内部跨方威胁模型、V/C OpenAPI与迁移设计、固定向量和评审输入包、单设备、三十天会话、七天注销 | 契约／实际SQL审阅、移动端 Passkey 适配、两组织运营安排、独立安全评审 |
| [身份](modules/identity.md) | 一至三个、服务端接受任务时绑定、同帖主评论/楼中楼回复复用、字符校验及十二字上限、删除范围 | 资料编辑交互、默认头像、输入法实现、图稿 |
| [导航](modules/navigation.md) | 七通道、默认五通道、两次任务的二维导航树边界 | 内容接入、文字搜索分组排序、历史范围及同步实现、最终树形视觉 |
| [标签](modules/tags.md) | 通道必选、#标签选填、无中间分类与统一治理；主题屏蔽后续设计 | #标签输入、筛选画面与检索实现 |
| [热度](modules/popularity.md) | 七天前二十、整五分钟刷新、权重不公开、浏览量只展示、通道删除后按有效内容重算 | 权重及衰减值、无数据呈现 |
| [发帖](modules/post-composer.md) | 标题手写、图片齐全公开、可取消、失败处理、新帖草稿 | 取消/发布并发实现、存储和正式图 |
| [详情](modules/post-detail.md) | 分屏可调、头像联系、图片查看、主动保存相册、赞藏反馈 | 点赞未知同步、图稿和屏幕适配 |
| [评论](modules/comments.md) | 分层删除、无引用块、对象定位、成功滚顶、约五十条分页、图片失败保文字 | 评论分页实现、输入法和图片状态图 |
| [消息](modules/messages.md) | 身份隔离、站内分类、预览开关、隐藏恢复、备注与正文搜索、推送范围 | 消息子页图、目标失效与陌生会话细节 |
| [私信](modules/messaging.md) | 首条文字限制、自动本地保存、未发送文字本地保留、补收与撤回规则 | 聊天页设计、保存格式与加密 |
| [我的](modules/personal.md) | 两页签、分别空状态、草稿混排、返回保位、删帖无回收站 | 卡片与设置图 |
| [管理](modules/moderation.md) | 处罚申诉、证据授权、待复核、举报进度、拉黑在途消息、旧帖编辑丢弃修改 | 证据保存期限、审核网页 |

## 继续顺序

第二十二轮业务主干已收口；用户确认屏蔽留到后续版本。UI 讨论暂缓，任务 1 的通道功能骨架可依既有工程决策维护；认证主链须先完成上方的实施前规格化和独立安全评审。旧 UI 评审记录仅用于追溯，不作为当前认证决策依据。

## 剩余图稿按八组推进

新增图稿包括消息身份切换展开 v1、v2，评论与回复收到的 v1、v2，以及我发出的正常状态 v1 和失败状态 v1。身份切换 v2、收到的 v2 与我发出的正常状态 v1 已确认；失败状态 v1 已作废，旧稿保留用于追溯。图片数量不等于完整流程已定稿数量。

1. 入口、登录与导航树。
2. 通道列表、筛选、搜索历史、热榜和结果。
3. 发帖编辑、确认、身份选择和图片状态。
4. 消息首页主布局、身份切换展开 v2、收到的 v2、我发出的正常状态 v1、系统通知失败详情 v1、顶部失败提示 v1、系统通知时间流 v2、举报处理结果详情 v1、违规处理通知详情 v1 已确认；旧分类列表及原发言列表内失败稿作废。
5. 私信聊天、首次联系、图片和失败状态。
6. 我的、收藏、草稿和设置。
7. 手机端举报、通知和申诉：待复核详情、结果通过、结果未通过 v1 已确认；首次提交 v2、补充材料 v1、举报原因配色 A v1 已生成待评审；电脑网页审核管理后台仍待设计。
8. 已有阅读、分屏和回复图同步新规则，补关键异常状态。

组数不等于页面数。当前按[UI 评审记录](../discussions/2026-09-20-replies-ui-review.md)推进申诉流程；旧稿仅作对照。

## 后续工程工作

认证主链已有规则、协议、恢复、数据/API、威胁模型、OpenAPI 和评审材料，并已按用户授权进入隔离实现：槽位／开户／ACK、校邮确认、原确认续办与 HTTP／mTLS 的证据见[资格报告](auth-privacy-eligibility-http-validation-report.md)；登录、会话接替／续期／撤销及 Gate 故障验证见[会话报告](auth-privacy-session-lifecycle-validation-report.md)；恢复码重设、七天注销、截止裁决与受信封禁联动见[恢复／注销报告](auth-privacy-recovery-closure-validation-report.md)。下一切片补齐恢复码轮换与可选 Passkey 的凭据管理，再串联移动端持久待办、设备通知与生产授权。每次实现提供必要的真实事务／故障验证；生产接入仍须完整迁移、可信灾备、运营权限事实与独立安全验收。旧 [ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)不再是实现规范。

随后按任务 2 接入文字内容主链，再安排身份/内容/会话数据关系、可见性和账号去重等验证、联调内测与分发上线。这部分须单独估算，不把设计成熟度当成上线进度。
