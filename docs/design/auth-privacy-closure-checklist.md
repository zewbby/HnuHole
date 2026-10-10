# 匿名分支缺口与收口清单

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

> **2026-10-05 AC03 当前交付：**当前数据／角色／HTTP／客户端持久状态及日志已完成有范围核对，修复应用错误／HTTP、PostgreSQL普通错误和移动端通道诊断三项差异；后续匿名业务契约已固定。完整Go／SQL／race／vet、R03实际C/V角色／日志与AC01／AC02回归、Flutter analyze与179项测试、R05真实Dart→HTTPS→SQL均PASS。见 [AC03报告](auth-privacy-boundary-validation-report.md)、[三步任务单](auth-privacy-boundary-plan.md)、[后续契约](auth-privacy-business-contract.md)及[机器记录](../../services/api/authlab/privacy-boundary-verification.json)。B02整模块继续BLOCKED，公共内容／聊天／管理消费者尚未实现，原生设备／生产证据单列。未提交／推送／部署。

以下 AC02／AC01及更早记录保留原日期、摘要和证明范围；“AC03未实施”等仅描述历史版本。currentFeature旧SQL／Flutter等字段明确保留为历史快照；本轮结果见currentAC03，历史平台不代证当前native验收。

> **2026-10-04 AC02 当前交付：**在保留 AC01 的工作区中，整账号正式关闭与身份联动已实现，完整服务端 SQL／race／vet 和 R03 实际 C/V 验收均 PASS。正式关闭原子擦除活动身份资料，保留累计状态、已有墓碑和永久回执；11→12 前向升级、受限角色、冻结／并发／回滚及同邮箱新账号独立历史取得本轮证据。详见 [AC02报告](auth-identity-account-closure-validation-report.md)、[实施任务单](auth-identity-account-closure-plan.md)及[机器记录](../../services/api/authlab/identity-account-closure-verification.json)。AC03 尚未实施；B02 整模块仍 BLOCKED，帖子／聊天业务调用、客户端／设备与生产缺口单列。未提交／推送／部署。

以下 AC01 及更早交付保留原日期、源码摘要与证明范围；“AC02 未实现”等表述仅描述历史版本。当前服务端版本以 AC02 记录为准，历史平台结果不能代证当前回归。

> **2026-10-04 AC01 交付（历史版本）：**基于 `faf557d` 的本次工作区已实现 V 独立 Gate，最终完整 Go／SQL／race／vet 和 R03 实际 C/V 进程验收均 PASS。V 正式迁移 3→4、独立状态／材料／连接池、受限恢复角色、最终资格事务、后台外部调用代次复核和旧 V schema 快照阻断均已接通。详见 [AC01报告](auth-verifier-safety-gate-validation-report.md)、[实施方案](auth-verifier-safety-gate-plan.md)及[机器证据](../../services/api/authlab/verifier-safety-gate-verification.json)。AC02／AC03 尚未实施；B02 整模块仍 BLOCKED，平台与生产门槛单列。本次改动尚未提交／推送。

以下原有 2026-10-04 平台交付及更早记录保留其原版本和范围；其中“AC01 未实现”和工具未执行等字段描述历史状态，当前 AC01 以上述证据为准。

> **2026-10-04 最新验证与环境交付：**基于远端 `codex/auth-privacy-handoff` 的 `d624ea30943a2b12096c20dbeefd844ba0e5e840`。Flutter分析与175项mobile测试、真实Dart→HTTPS→PostgreSQL R05、Android完整app构建、16项vault＋3组跨进程探针、9项Passkey Dart／5项Android codec和真实Flutter双进程共享AuthStore探针均PASS；Go/SQL/race/vet、R03实际C/V进程及完整OpenAPI已在本轮复验。环境与可复验命令见[本机环境](local-test-environment.md)，精确证明范围／失败修复见[最新记录](../../services/api/authlab/identity-runtime-test-verification.json)。**B02整模块仍BLOCKED：AC01 V Gate、AC02身份整账号关闭尚未实现，iOS、真实Passkey ceremony和物理设备／B02设备矩阵仍未验。**用户要求保留D盘工具环境、删除全部测试缓存和临时产物，完成后直接推送对应分支。

## 当前清单状态

| ID | 2026-10-05状态 |
| --- | --- |
| AC01 | IMPLEMENTED，开发范围 Go／SQL／race／vet＋实际 C/V 验收 PASS；生产边界单列 |
| AC02 | IMPLEMENTED，身份正式关闭与独立投影边界完成，Go／SQL／race／vet＋实际 C/V 验收 PASS；后续业务消费者未集成 |
| AC03 | IMPLEMENTED，当前隐私／日志核对、差异修复与后续契约完成，Go／SQL／race／vet、R03、Flutter179项及R05本轮PASS；未来业务／生产审计单列 |
| AC04 | IMPLEMENTED，关键场景映射完成，新增真实Dart V Gate／身份关闭与新账号隔离通过；完整SQL／race／vet、R03、Flutter179项及R05本轮PASS；原生／未来业务单列 |
| AC05 | BLOCKED；当前vivo S18实际App→cmd C/V→SQL／原生Keystore注册、身份创建改名、双进程恢复、退出及密码重登录PASS，分析182项／ARM64测试APK PASS；历史模拟器／codec范围保留。系统Passkey／iOS／备份／完整设备故障与Gate／注销矩阵仍未验 |
| AC06 | 当前本地源码／真机证据／交接及临时资源清理完成；历史AC04–AC06已发布，当前Android增量未提交／推送。AC05整项／B02／生产未闭合 |

## 2026-10-03收口范围与依据（历史盘点）

以下保留原清单及实现缺口依据；其中缺工具、缺B02 runner、未执行或未推送描述按原日期理解，当前执行结果以上表和最新机器记录为准。

> **2026-10-03 本机接续验证（历史）：**从远端codex/auth-privacy-handoff的87e603c3f54b2fc08d1501dd3a0d7db5b70d17cc拉取。AC04的B02 R03/R05测试源码已补；**Go全量SQL/race/vet、四份OpenAPI完整校验及R03实际非owner C/V HTTPS/mTLS进程验收通过**。R03覆盖身份CRUD、成功和拒绝回执、实际服务重启、Gate冻结/恢复后新会话核对、迁移10→11及缺表/缺DML拒绝。实际启动发现权限检查format()参数未指定类型，已补$1::text并通过实际进程和匹配race/vet复验。Go位于WSL /usr/lib/go-1.22/bin；PG/Docker可用，固定Goose仅在本次临时目录构建。**Flutter/Dart入口未找到，R05真实Dart→SQL及设备/原生Passkey仍BLOCKED/NOT_RUN，B02整模块未PASS。**AC01 V Gate、AC02身份整账号关闭仍未实现。逐项结果、失败修复/复验和源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。下方旧机器/版本和缺Go/未补B02测试链描述是历史状态。

日期：2026-10-03（Asia/Shanghai）。分支：`codex/auth-privacy-handoff`。这是依据用户范围纠正整理的有限收口清单，本轮只盘点与修正文档，不实施以下代码任务，也未执行动态验收。

## 目标与范围

交付已经确定的匿名方案、注册资格与账号控制权分离的基础实现，以及现有身份管理的隐私边界；每个缺口有源码位置、验证方式和结束条件。停止按 B05/B03、B06/B07、消息／私聊／治理顺序扩展本分支。后续业务开发顺序可以保留，但不构成本分支任务清单。

既定方案继续采用 V（校邮资格验证）与 C（社区账号控制）分离：邮箱 OTP 只用于注册准入；日常登录、恢复与旧号控制使用独立凭据。共享槽位允许两方串通或双侧数据／备份泄露时连接邮箱与账号；真实分权且双方不串通时，单侧不掌握完整映射。重复使用同一公开身份可以被识别为同一身份，不承诺全网匿名或不同帖子不可关联。以上是已确定的边界，不重新启动方案选择。

实现原则沿用现有最终事务授权、会话／授权代次、资源归属、同意图重试和未知提交结果核对；先补具体缺口，再集中验收。保留已有测试源码和历史证据，不下载整套工具或拿未知数据库运行会 reset schema 的 fixture。

## 当前事实

- HEAD 为 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`，工作区有大量未提交实现。本次盘点沿用[模块台账](module-acceptance-ledger.json)中的源码摘要；HEAD 单独不能标识当前实现。
- 注册／退役／释放、密码登录、恢复、七天注销、C Gate、运行时、设备／凭据管理、原生桥和 B02 基础已有源码。历史隔离测试证据保留，但不能代证本次工作区。
- B02 状态保持 **基础管理已实现，业务联动待实现**。完整 Go／SQL／Flutter／设备验收仍为 `NOT_RUN`，不能写成匿名链路已通过。
- 明确未实现项与尚未取得证明的项分开。下表 AC03 是核对任务，不能据此推断当前已存在敏感数据泄漏；AC02 是源代码未接入的生命周期缺口，尚无真实运行复现。

## 2026-10-03有限清单与确认位置（历史快照）

| ID | 缺口／当前状态 | 工作与结束条件 | 对应模块 |
| --- | --- | --- | --- |
| AC01 | **V 独立 Safety Gate 未实现** | 补 V 自己的可信时间、库外高水位／旧快照检测、持久冻结、授权代次与显式恢复；盘点并覆盖 OTP、确认／签名、退役、收据／配额释放、邮件派发和清理的最终授权点。独立配置／密钥／迁移／受限角色与运行时均接通；不能只在 HTTP 入口检查或依赖 C Gate。保留回退、旧快照、锁等待、签名前后冻结、重启与多副本测试。 | P01、A01/A02/A04/A10 |
| AC02 | **已有身份尚未接入整账号正式关闭** | `finalizeAccountClosure` 当前处理认证凭据、会话和槽位，未处理 B02 身份；worker 也没有身份注销处理。按 ACCOUNT-CLOSE-01 补现有身份的正式关闭生命周期与统一注销投影边界：七天缓冲不提前变化，正式关闭后不可继续暴露原昵称／头像；各身份独立占位，不公开共同账号编号。与不能删最后一个、累计次数、永久回执和墓碑约束协调，避免简单删表破坏约束。保留零／一／三身份、关闭与改名／创建并发、重试／冻结及旧新账号不继承测试。具体帖子／聊天页面投影随业务模块实现。 | A08、B02；后续 X06/X07 |
| AC03 | **当前隐私边界及未来业务契约待集中核对** | 对当前数据库字段、运行权限、公开／内部响应、客户端持久状态和应用日志做一次有范围的核对；检查 C 不保存邮箱／邮箱哈希、V 不接收社区账号资料、两侧安装标识分离、敏感秘密不进入诊断、本人身份列表仅本人可见。把现有设计与实际实现的差异登记并修复。固定后续公开资料与注销占位契约：不得暴露共同账号／本体标记／其他身份，按账号＋帖子固定身份、按身份对隔离私信；禁止邮箱后台找回。当前接口保留负向字段／越权测试，尚无业务调用者的契约明确记为未集成。 | A01/A02/A04/A05/A08/A12、B02；后续 B05–B11 |
| AC04 | **B02 的实际进程与真实客户端测试链缺场景** | 当前 Go HTTPS／SQL 与 Dart TLS 替身测试源码存在，但 `runtimeprobe` 和真实 Dart→HTTPS→SQL fixture 尚无 B02 操作序列。补非 owner 实际 C/V 进程中的身份 CRUD／原结果核对、迁移 10→11／重启，以及真实 Dart＋SQL 的丢响应／会话变化场景；保留测试源码，不用原认证 runner 的成功代证新增身份链路。AC01/AC02 的新增迁移和链路也纳入相应 fixture。 | A01/A02/A13、B02；R03/R05/R10 |
| AC05 | **当前版本编译、数据库、客户端与设备验收未执行** | 对固定源码版本运行完整契约校验、Go 编译／race／vet、正式迁移／最小权限、真实 HTTPS/mTLS 与 SQL 故障链、Flutter 分析／测试，以及 Android/iOS 完整 app／真实安全存储／跨进程测试。原生 Passkey 需显式 RP、Android 签名与 iOS 关联身份，并取得系统绑定／恢复证据；配置未具备时保留禁用、标记 `BLOCKED`，不能冒称支持已验。失败先修复再复验；没有证据继续记 `NOT_RUN/BLOCKED`。 | A00–A13、N01–N03、B01/B02及已有设置／目录相关回归 |
| AC06 | **最终交付与状态统一尚未结束** | 本次已建立收口入口、修正下一步；最终还需消除现行文档“尚未实施”与实际源码进度的歧义，保留历史日期／证据范围；固定最终源码摘要／版本，逐项列实现、实际测试、未执行项及外部依赖。不新增通用业务模块。提交／推送／部署仍按用户当次授权。 | HANDOFF、progress、模块交接／台账、架构／评审入口 |

### 确认依据与验证入口

- AC01：`services/api/internal/authprivacyruntime/server.go` 只给 C 装配 `NewGate`，V 仍创建 `VerifierStore`／`Eligibility`；`eligibility_otp.go`、`eligibility_confirmation.go` 及 V 配额／收据操作使用数据库时间。现有 P01 为 `NOT_STARTED`，不是只差测试。设计基线见 [C Safety Gate](auth-authorization-safety-gate.md) 和[运行时计划](auth-privacy-runtime-business-integration-plan.md)；V 专用实施方案尚需在本项内明确，不假定 C 的 SQL／锚点可直接照搬。
- AC02：`services/api/internal/authprivacy/community_closure.go` 的 `finalizeAccountClosure`／`lockClosureDependents` 和 `workers.go` 尚未引用身份表；`services/api/migrations/0011_identity_management.sql` 约束已初始化账号至少一项活动身份且回执／墓碑不可变。规则见[账号 ACCOUNT-CLOSE-01](modules/accounts.md) 与[身份规则](modules/identity.md)。这里需要限定的身份生命周期修补，不要求先实现帖子或聊天。
- AC03：规格依据为[架构决策](auth-privacy-architecture-decision.md)、[数据/API 契约](auth-privacy-data-api-contract.md)、[跨方威胁模型](auth-privacy-threat-model.md) 和身份 PRIVACY-02。当前 worker 日志只记录任务类别／数量等摘要，不能从这一处推出所有应用、代理、供应商日志都已审计。检查范围为 `services/api/internal/authprivacy*`、当前 OpenAPI、`infra/postgres`、移动端 auth/identity 与原生 vault/passkey；外部日志／备份归下方生产门槛。
- AC04：确认位置为 `services/api/cmd/runtimeprobe/main.go`、`services/api/internal/authprivacyhttp/mobile_client_postgres_test.go`、`apps/mobile/integration/auth_public_https_postgres_test.dart`。已有 B02 测试及缺口记在[身份报告](identity-management-validation-report.md)。复用 R03/R05 的真实流程，不能发明现存 runner 没有的模块参数。
- AC05：命令与逐项证明范围见[模块测试交接 R00–R10](module-acceptance-handoff.md)、[设备／Passkey 报告](auth-privacy-device-credentials-passkey-validation-report.md)和[身份报告](identity-management-validation-report.md)。当前机器缺 Go／Flutter／数据库工具、完整 OpenAPI validator 等环境；本清单没有重新运行动态测试。将来按实际可用环境登记，内存 vault、同进程对象重建、Swift parse 和无 DSN 的跳过均不能代证设备／SQL通过。
- AC06：本次只做文档链接、台账状态、源码摘要和补丁检查；结果写在本页末尾，不改变功能验收结果。

## 后续业务模块承担的匿名联动

这些是实际未实现的业务匿名联动；登记不能替代实现与验收。本分支固定契约，业务模块实现调用与投影后，再取得相应证据。

| 业务范围 | 后续必须落实的匿名规则 |
| --- | --- |
| 发帖／评论 B05/B06/B07 | 首次公开发送才确定账号＋帖子身份；后续固定沿用；无身份时设置后恢复原输入；身份删除／账号注销的独立占位和资料更新，不暴露账号关联。 |
| 私信／消息 B08/B09 | 按身份对隔离会话和收件身份；改名不合并身份；删除／注销后的独立占位、停止发送与本地私人备注清理。 |
| 个人内容／治理 B10/B11 | 本人列表与对外展示分离；已删除身份相关内容权限、普通审核员不能查其他身份、任何管理角色不能查完整验证邮箱；处罚／申诉不泄漏身份关系。 |
| 媒体 | 自定义头像上传、审核、留存和资料更新。当前默认头像闭环保留。 |

## 单列的生产放行缺口

| 台账 ID | 尚缺事实／证据 | 本分支结束时应如何登记 |
| --- | --- | --- |
| P02 | 真实 V/C 不同运营／权限域，密钥与独立授时／库外锚点的管理与恢复权限 | 待真实主体与配置；同机分库不算。开发可交付，生产前提未证明。 |
| P03 | 真实备份／WAL／日志留存与清理、旧快照恢复演练 | 隔离故障测试与生产灾备分开，未演练项保持待验。 |
| P04 | 生产多副本共享限流、资格／恢复枚举和网络／时间侧信道校准 | 当前本地基础不能代证；不把无限性能优化加入本分支，也不声称侧信道已消除。 |
| P05 | 正式域名／证书／邮件供应商／原生关联／签名发布与持续验收流程 | 配置和真实集成未齐全；不自动部署或启用未验 Passkey。 |
| P06 | 最终实现版本的人类独立安全评审 | AI／源码自查不代证；未委托／未取得结论，不写生产批准。 |

P01 与上述外部事实不同：它是明确的代码缺口，必须在本分支源码收口前补齐。P02–P06 仍是生产放行门槛，不能通过本页将它们改成通过，也不靠继续实现一般业务功能解决。

## 结束条件与执行顺序

按 **AC01 → AC02 → AC03/AC04 → AC05 → AC06 最终交付** 推进。AC03/AC04 可随实现补充，但不启动 B05/B03 等完整业务片。

- **开发交付收口**：AC01/AC02 实现完成，AC03 的当前范围核对及未来业务契约明确，AC04 测试源码补齐，AC06 最终交付状态一致；AC05 按用户既定“开发先行、集中验收”方式如实列出已执行／未执行／阻塞项。存在未执行项时只能交付为“源码完成，验收待执行”。
- **验收收口**：AC05 当前版本所需关键测试取得证据，失败已关闭，不能用旧版本或替身通过代证。
- **生产放行**：再满足 P02–P06 与实际已启用业务模块的匿名联动验收；本分支交付不意味着产品已能上线。

只有能指出本清单具体匿名不变量被破坏的发现，才在对应 AC 项内追加修补；一般业务功能不以“匿名相关”为由加入本分支。2026-10-03 用户随后已授权整理、提交并推送当前源码与清单供另一台机器接续；见[机器接续入口](auth-privacy-machine-handoff.md)。该授权不代表匿名缺口已完成，也不包含部署或生产放行。

## 2026-10-03盘点检查（历史记录）

本轮只改文档与台账。实际执行结果：

- `git diff --check`：`PASS`，退出 0，证明补丁空白检查通过。
- `PYTHONDONTWRITEBYTECODE=1 python3 tools/check-identity-handoff.py`：`PASS`，退出 0，B02状态／路径／历史交接链接及230个文件的源码摘要保持一致；不验证应用行为。
- Python 文档／JSON核对：`PASS`，退出 0，清单链接存在、六个AC编号唯一、模块映射有效、交接入口范围一致，未将交付／验收／生产状态改为通过。

动态 Go、SQL、Flutter、原生设备与安全评审本轮均 `NOT_RUN`。没有创建服务、数据库、密钥、APK或大型缓存，未提交／推送／部署。
