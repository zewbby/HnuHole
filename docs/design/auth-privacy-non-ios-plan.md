# 非 iOS 匿名基础验收任务单

> **2026-10-08 固定收口计划：**剩余非iOS匿名基础验收统一按[24项／6批次最终计划](auth-privacy-non-ios-closure-plan.md)执行；预算48–64有效工时，目标2026-10-19，前提为持续工作日推进且第二实体Android在10月15日前到位。10月15日核对B1–B4；每批报告固定ID累计结果，不再零散追加“下一步”。24项及最终候选回归／交接通过才可结束非iOS开发验收；缺第二设备不能算完整PASS。iOS、生产及未来业务联动独立，不阻止本分支按其授权范围结束。此为计划，新增项尚未执行。

日期：2026-10-05。用户要求先完成 iOS 以外的部分；仅在 `codex/auth-privacy-handoff` 完成匿名基础 AC01–AC06，不扩展帖子、评论、聊天或生产发布。保留原正常链路、三组故障证据及所有已有未提交实现。用户要求后续复用的环境／缓存／测试包保留。

**2026-10-08 批量验收交接：**十四个命名实际App阶段已PASS，每项保留自己的APK／夹具／runner摘要、设备PID和代理计数。覆盖真实注册、双端独立草稿／手机主动接替／账号隔离，真实Passkey成功响应丢失与原键跨进程COMMITTED核对，实际provider期间控制器取消与产品返回，C证据过期冻结后的旧会话401／主动登录／明确结束旧UNKNOWN，两次提前成功后的原回执确认与产品移除，未回应原生操作约60秒取消，篡改来源422拒绝及自然到期原键NOT_COMMITTED核对。旧来源拒绝在核对前遇USB及服务中断，仍按原版本保留，未迁成新会话原结果；新的完整负向／核对另有自己的证明。取消／超时后的OEM窗口清理由宿主在原生结果后执行，不宣称自动关闭或任意迟到回调；两秒观察范围保持。对应四组SQL/race/vet、R03十九项、R05及Flutter188项回归PASS，不代证新夹具；新夹具分析／ARM64＋x64构建与设备执行逐项PASS。Activity重建／旋转、原生等待期间Gate／接替、完整关联／签名负向及真实Passkey／未知迟到待办参与关闭仍需补入口和证据。仅有vivo，OEM实体搬家BLOCKED；iOS本轮SKIP；完整AC05／B02及生产继续未通过。工具、环境、缓存、原账号与草稿按用户指令保留；未提交／推送。见[报告](auth-privacy-non-ios-validation-report.md)和[机器记录](../../services/api/authlab/android-matrix-verification.json)。

2026-10-07 批量接续（历史快照，后续以2026-10-08交接段为准）：用户要求扩大单轮验收范围，确认仅有 vivo S18，无第二台实体 Android。使用新隔离根 `/var/tmp/hnuhole-android-live-batch-20261007`，保留原 boundary／closure 根及手机数据。完整 SQL／Go race／vet、实际 C/V 进程、R05 真实 Dart→HTTPS→SQL 和 Flutter 全量测试四个已启动进程均退出0；待导出其被测源码清单及脱敏详细记录，不把这些回归当成新增批量手机夹具的运行证据。

新增[统一实际 App 夹具](../../apps/mobile/integration_test/auth_android_batch_device_test.dart)、[故障代理](../../tools/android-auth-batch-proxy.py)和[计数核对工具](../../tools/control-android-batch-proxy.py)，runner 增加 `-BatchPhases`。首批阶段为 batch-register → batch-phone-draft → batch-companion-draft（模拟器）→ batch-phone-retake → batch-account-isolation；随后手机执行 batch-passkey-drop → batch-passkey-reconcile → batch-passkey-origin-reject → batch-passkey-rejected-reconcile → batch-passkey-route-cancel。手机和模拟器各用独立 DriverWorkspace、同一合包及批量配置；runner 不自动安装、清数据或混用阶段选择器。前五阶段自动执行，Passkey 创建需要现场指纹配合。代理各阶段先 prepare、后 capture；计数报告须与实际 App PID／APK 报告一起接受，不能单独算设备 PASS。

来源负向只在测试代理的内存中改真实原生证明后发给实际 C，不修改生产验证规则，也不保存原始证明。它验证被篡改的原生来源拒绝，不代证错误 APK 的系统关联拒绝、完整签名负向或域名负向。拒绝后必须保留 UNKNOWN；等原 challenge 自然满五分钟并由原结果接口取得 NOT_COMMITTED 后，明确确认再启动下一操作，不重复原证明、不改 SQL 期限。路由取消阶段需先观察实际原生 provider 的后台转换，再触发产品返回和取消，核对凭据不变；两秒观察窗口不能声称覆盖任意迟到回调。系统超时／旋转、Gate／接替期间原生操作、真实 Passkey 参与正式关闭及未知身份待办关闭迟到场景仍需补专门入口与证据。

当前批量状态见报告和机器记录：配置、完整分析／合包及四组对应源码回归PASS；八个实际App阶段已接受，保留v1与v3的独立APK／夹具／runner摘要。原审批故障已解除。来源负向尚未形成HTTP证明，失败尝试保留；先执行新增 batch-passkey-remove-existing 的产品两步移除与原回执，后续创建用真实异步等待，不以原生失败误判服务器拒绝。取消采用宿主观察真实vivo provider后调用实际控制器取消，再产品返回；验收后才关闭仍在前台的OEM窗口，不宣称自动关闭。OEM缺第二实体Android仍BLOCKED，iOS本轮SKIP，生产单列。

1. 盘点现有 Android 真机／模拟器和实际 C/V 环境，补真实生命周期、锁屏／恢复、输入法／辅助服务、备份排除／卸载重装／跨设备、V Gate、会话接替、恢复与账号关闭场景；需要宿主造到期状态时仅操作本轮明确归属的合成账号，区分模拟截止与真实等待七天。补发现的实现缺口，运行适当回归。
2. 为系统 Passkey 准备免费 HTTPS RP 方案、真实 APK 签名和 Android 关联文件；部署前提供可审阅文件并取得当次发布授权。真实系统绑定、移除、可发现恢复、取消／迟到、会话接替／Gate、提交未知和关联负向均需自己的运行证据，不以 codec 通过代替。
3. 汇总本轮真实执行与外部阻塞，同步测试交接、台账、HANDOFF／progress 和源码摘要。iOS 按用户要求排除并单列，不能改成 PASS；生产分权／灾备／独立审计及未来业务消费者仍是各自任务。完整非 iOS 验收只有列出的必需场景取得证据后才能计 PASS。当前尚未执行的新场景保持 NOT_RUN／BLOCKED。

当前资源：vivo S18（V2323A／Android 15）、现有 Android SDK／AVD、Google Play Services／TalkBack 和系统备份传输。实际 C/V 及专用缓存在 `D:\zewbbyTest\Hnuhole-android-live-faults-20261005` 与 WSL `/var/tmp/hnuhole-android-live-faults-20261005`。仅对带本轮 OWNER／安装摘要的测试包操作，不清用户手机其他资料或未知数据库。

2026-10-06 接续：旧一次性数据库／材料在旧初始化器退出时被清理，原验证保留历史版本。现行实际服务重建于 WSL `/var/tmp/hnuhole-android-live-boundary-20261006`，使用显式保留模式；原工具／缓存继续复用。新的 boundary 配置及合成账号独立于旧端点，不擦除手机旧命名空间。先完成新实际App注册、双设备会话接替、V冻结／恢复旧OTP拒绝，逐阶段留脱敏报告，再继续其他矩阵。

本轮双设备登录／接替与 V Gate 实际 App 场景已取得证据。V 无确认锚点查询修复经 R01／R03／R05 当前回归及未过期旧代次 flow 的实际 App 核对验证。接着使用独立 [完整 App 存储夹具](../../apps/mobile/integration_test/auth_android_storage_device_test.dart)和[宿主 runner](../../tools/run-android-app-storage.py)补模拟器实际登录／身份草稿跨进程、卸载重装空状态和仅恢复旧密文缺钥时的产品拒绝页面；这不等于 OEM 搬家或物理手机卸载已验证。

免费 RP 候选为 GitHub Pages 用户站点 `zewbby.github.io`。公开发布内容只含实际测试签名的 assetlinks、空 `.nojekyll` 和静态说明，不包含 API、邮箱、令牌、数据库、私钥或运行配置。用户已授权创建并发布；站点及 Google Digital Asset Links 核验已通过，源码与域名证据见[当前报告](auth-privacy-non-ios-validation-report.md)。系统设备场景仍需实际运行，不由域名证据代证。

2026-10-06 OTP 续办增量：按现有注册协议第7节补原流程已清理时的明确用户入口及持久恢复。通过[实际App夹具](../../apps/mobile/integration_test/auth_android_otp_continuation_device_test.dart)和[宿主runner](../../tools/run-android-otp-continuation.py)分 start／finish 执行：真实发码、冻结拒绝、恢复后等待不可变期限及正常清理，再以原键确认／核对，独立进程主动续办并取得同公钥／槽位的新票据。只读计数证明明确操作前没有新发码／C账号或会话变化；不改 SQL 期限，不重装清除原操作。当前客户端分析、188项测试及R05已PASS；设备阶段只有机器记录中的实际接受项可计PASS。

真实输入法入口已补：[夹具](../../apps/mobile/integration_test/auth_android_ime_device_test.dart)通过产品昵称编辑器等待实际手机键盘的组合态和确认提交，不用 tester.enterText 或伪造 TextEditingValue。现已在 vivo 现有搜狗键盘上执行 phone-ime-write／phone-ime-read，核对未确认组合文字不入原生持久草稿、确认文字跨进程恢复且无身份创建，结果 PASS；精确 APK／PID／失败版本见当前报告和机器记录。TalkBack 另需自己的实际服务／手势证据。

真实输入法复跑命令（PowerShell；先保持手机解锁并完成摘要匹配的测试包安装）。写入阶段等待 `await-real-ime-touch` 时，需实际点击产品昵称框，夹具先断言设备指针能够聚焦；随后进入 `await-human-real-ime`，用实际键盘输入，组合时停留两秒再选候选，最终确认为 `输入法测试草稿`。不粘贴、不语音输入、不提交创建身份。读取阶段只重启 App 进程，使用同一 APK；两个阶段成功后 runner 会主动关闭测试进程，不执行账号退出或清除数据：

```powershell
$imeWork = 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix'
.\tools\run-android-live-device.ps1 -DeviceId 10CEAG17RY003M7 `
  -Apk "$imeWork\phone-real-ime.apk" -ConfigFile "$imeWork\boundary-device-config.json" `
  -DriverWorkspace "$imeWork\driver\apps\mobile" `
  -PubCache 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\pub-windows' `
  -ImePhases phone-ime-write
.\tools\run-android-live-device.ps1 -DeviceId 10CEAG17RY003M7 `
  -Apk "$imeWork\phone-real-ime.apk" -ConfigFile "$imeWork\boundary-device-config.json" `
  -DriverWorkspace "$imeWork\driver\apps\mobile" `
  -PubCache 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\pub-windows' `
  -ImePhases phone-ime-read
```

只有写入阶段确认实际非折叠 composing、未确认文字未入原生草稿、确认后草稿落盘，且独立读取进程恢复同会话／草稿，才计完整真实 IME 场景 PASS。只看到最终文本、用户回复完成、构建通过或模拟 TextEditingValue 均不能代证上述检查。

夹具须在本测试期间显式开启 `shouldPropagateDevicePointerEvents` 并在 finally 恢复，否则 Flutter 测试绑定默认丢弃手机真实触摸。首次失败及分项诊断保留，不根据其超时推断厂商键盘不支持 composing。此次没有新装键盘，临时切换测试后已恢复原 vivo AI 输入法；未来换键盘／版本需自己的实际运行记录。

2026-10-07 TalkBack增量：通过[实际夹具](../../apps/mobile/integration_test/auth_android_talkback_device_test.dart)和[宿主服务证据工具](../../tools/control-android-talkback.py)验现有TalkBack真实绑定、Flutter平台无障碍开关、系统发来的焦点／激活事件，以及设置→身份编辑器→取消→设备凭据→返回的实际手势路径。辅助功能原设置先保存，人工开启，验收后只恢复本轮设置。朗读准确／可理解需用户现场确认，不能由语义树或服务开启代证。

`phone-talkback-prepare` 核对原账号和原生草稿；保留环境跨日恢复若按Gate协议撤销旧会话，先通过真实登录页明确登录同一合成账号，不绕过Gate或重置数据。`phone-talkback-navigate` 只在人工阶段记录真正平台动作，不调用 performSemanticsAction、不注入焦点／昵称；`phone-talkback-read` 用同APK新进程恢复同会话和草稿，需再次实际焦点朗读。完整接受后对应A12／N01／B02及X05／X08的有限范围；账号隔离、错误／恢复码页面朗读、全部认证界面和其他辅助服务需要各自场景，不能由本导航场景泛化。

PowerShell入口（复用现有配置、同一APK；prepare阶段在开启TalkBack前运行，navigate／read期间要求已启用且实际绑定的TalkBack）：

```powershell
$talkBackWork = 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix'
python tools/control-android-talkback.py status --phase phone-talkback-navigate
.\tools\run-android-live-device.ps1 -DeviceId 10CEAG17RY003M7 `
  -Apk "$talkBackWork\phone-talkback.apk" -ConfigFile "$talkBackWork\boundary-device-config.json" `
  -DriverWorkspace "$talkBackWork\driver\apps\mobile" `
  -PubCache 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\pub-windows' `
  -TalkBackPhases phone-talkback-navigate
# 独立进程读回使用完全相同参数，改为 -TalkBackPhases phone-talkback-read。
```


2026-10-07 正式关闭／同邮箱再注册增量：使用独立服务根 `/var/tmp/hnuhole-android-live-closure-20261007`，原 boundary 账号、手机原加密命名空间和环境保留。[实际 App 夹具](../../apps/mobile/integration_test/auth_android_closure_device_test.dart)依次覆盖零身份账号的产品昵称草稿／注销申请／原状态核对／同邮箱新码新号，以及三身份账号正式关闭后的资料擦除和新号独立创建历史。原密码、恢复码和 Bearer 在重新注册之前做拒绝检查，避免把用户名重用误算旧凭据失效证据。

测试时间只通过[构建专用覆盖生成器](../../tools/prepare-android-closure-clock.py)替换测试二进制的 Gate.Clock 和开发证据签发时间。生产源码、运行配置契约、手机／宿主时间、SQL 七天截止、单调触发器及业务函数不改。两个周期分别由[受限宿主控制器](../../tools/control-android-closure.py)先验证精确项目／数据库端口／角色／原截止和四个进程归属，再停机、单调推进模拟时间、签发更高版本的正常证据并恢复同一普通后台 worker。不能称为实际等待七天或原生产二进制的无覆盖验收；结果必须同时列出覆盖文件及原源码摘要。没有关闭／释放数据库 DML。

PowerShell 使用 `tools/run-android-live-device.ps1 -ClosurePhases <阶段>`，APK为专用 `phone-closure.apk`，配置为专用 `closure-device-config.json`，其 `AUTH_MATRIX_ACCOUNT_RUN_ID` 固定为上述 closure 根。按 closure-draft-request → closure-draft-released → closure-draft-register → closure-profile-request → closure-profile-released → closure-profile-register → closure-new-read 顺序；两次 released 前分别在 WSL 执行 `python3 tools/control-android-closure.py capture --cycle 0/1` 和 `advance --cycle 0/1`。正常顺序复用同一 APK，不逐场景重装、不清手机数据。本轮中途修复夹具的界面等待、登录键长度和禁用输入时序；已通过阶段保留其原 APK／源码摘要，剩余阶段按修复包单独记录，不能改写早先通过版本。续跑原收码流程时先读回实际持久状态；新收码还需排除同邮箱上一封测试邮件。旧未知身份／凭据待办的迟到回调、Passkey 关闭关联及未实现帖子／聊天消费者均需自己的测试，不能由本夹具的空待办断言代证。
