# Android候选手机最小链路实测：2026-10-19

结果：`PASS_SCOPED_SINGLE_ANDROID_MINIMUM_CHAIN`，11项限定检查通过；不是完整App、全部原生安全或正式发布验收。
本session用户开放手机窗口，随后明确授权“卸载旧App及其本机数据”，并亲自完成中文昵称输入和系统Photo Picker选图。
手机操作于2026-10-19 09:44:58（Asia/Shanghai）结束。后续文档和CI工作不再操作手机。

## 精确材料

| 项目 | 本轮实际值 |
| --- | --- |
| 设备 | 用户报告vivo S18 / OriginOS 5；实际读取vivo V2323A、Android15/API35、arm64-v8a/armeabi-v7a/armeabi；`ro.vivo.os.version=15.0` |
| 手机包源码 | `8691eb49d3863b911e04c4678512c1eb8d54aaca`，真实`lib/main.dart`，debug，Flutter目标android-arm64，附带其他ABI的JNI库 |
| 包及版本 | `org.hnuhole.hnuhole_mobile`，`0.1.0+2026101802`，测试label `HnuHole Prerelease Test` |
| APK | 98479040字节；SHA256 `d80c47283e22007dfbc5cebf6ccb96f82b70b917b9a1efe1a85af0cd971cd18a`；安装后从设备只读核对相同摘要 |
| 测试证书 | SHA256 `09309fe3ac7e4f817e81cdadd406ccae28ca465ab591701d233ea1527660397c`，不等同正式签名或Passkey来源身份 |
| 后端 | `14f5096bb65aa53743939031000d6df32e42ad4b`，本任务lab-09的非空恢复C/V，正式C0015/V0004；与8691的差异仅device构建脚本 |
| main核对 | `1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`；没有0016占位表或业务迁移修改 |
| HTTPS | C52045/V37073，仅App内CA，正常验链/主机名验证；CA PEM SHA256 `da2215084e59bc56c6aeca048eefd2c6f8b1de2505ae46f5e8edcfa932c7a3ac` |
| 合成PNG | 512×384，5049字节；SHA256 `994bd517ee5da474608ad4aa8d5d50fd6a68a69e1ad6e11f80a5b2d049e62e27` |

原[准备manifest](android-device-candidate-20261019.json)的NOT_RUN是构建完成时状态，保留原字节和摘要；
本轮新证据在[手机机器记录](android-device-validation-20261019.json)。CI release仍使用.invalid默认服务，是不同制品，不用于此次手机业务测试。

已有独立reviewer只读复核了11项编号、公开SQL/收尾/fixture回执、源版本与文档限定及链接，无阻断；
该复核没有重新观察原始UI、手势或读取凭据，不等于GitHub成员批准。原产品独立审查保留原精确SHA。

## 实际执行与证据

| 检查 | 实际操作与结果 |
| --- | --- |
| ADP01 | 核设备、APK摘要及旧包签名。已有旧同包证书`fd26b276…7389dc`与本包不同，先暂停；用户明确授权后才卸载旧App及本机数据，再全新安装和冷启动。PASS；不证明同包升级。 |
| ADP02 | 正常注册UI输入独立合成校邮；V收码/确认、Mailpit取该合成收件人的最新OTP、C账号设置、原码隐藏后完整确认恢复码。真实入库1个ACTIVE账号。PASS；没有宿主预注册、万能验证码或真实邮件投递。 |
| ADP03 | 登录后的正常入口读取通道和已有合成帖子。实际C/V HTTPS成功。PASS；本轮没有做手机端恶意证书负测。 |
| ADP04 | 用户在手机键盘输入“预发布验收”并创建身份；UI及SQL确认1个身份。PASS。 |
| ADP05 | 正常UI发布`PR16Text`及独立合成marker；worker真实发布，刷新列表后进入详情读回。SQL确认1个对应PUBLISHED事实。PASS。 |
| ADP06 | 只将本任务PNG放入专属临时目录；用户从系统Photo Picker选择它。正常UI发布`PR16Image`，详情出现缩略图。SQL验证图片payload原字节摘要与选入文件一致。PASS。 |
| ADP07 | 正常大图入口显示棋盘PNG；点击保存显示“已保存到相册”，只读查询本包归属MediaStore文件并核原字节摘要一致。PASS；不代证系统相册浏览UI、多图或动画。 |
| ADP08 | 只强停本测试包并重开，实际PID不同；无需重新登录，通道列表和两个原帖子保持，SQL活跃会话仍1。PASS，范围仅此进程会话保留，不是完整vault/Keystore硬件安全证明。 |
| ADP09 | 正常UI退出后SQL活跃会话0；一次自动填入的密码截短导致用户实际看到错误，保留FAIL。核对原40位凭据后，从正常UI完整输入并登录，SQL会话1且凭据版本仍1。PASS_AFTER_INPUT_CORRECTION。 |
| ADP10 | 重登后返回首页重新进入通道，读回两个帖子及棋盘大图，保留稳定截图/UI节点。PASS。旧的“我的”路由没有自动恢复，见下方观察。 |
| ADP11 | 只清本任务媒体/UI文件、两个reverse；停自有ADB及C/V/watch/mailpit，五PG均status3。PASS，测试App保留安装。 |

最终SQL为1个ACTIVE合成账号、1身份、1活跃会话、2个PUBLISHED帖子、1张verified且payload摘要一致的PNG；
账号凭据版本为1。没有对产品表执行诊断写入，没有重设密码或通过宿主HTTP登录替代手机操作。
UI dump、截图、ADB命令日志及计数回执的摘要见机器记录，原件含账号/状态栏等内容，仅保存在本任务私有runtime。
用户名、密码、恢复码、OTP、设备serial及原始日志不进入Git。

## 失败与接续限制

第一次重登实际显示“用户名或密码不正确”。字段证据为38位，原fixture为40位。
只读Argon2id核对确认原fixture与合成账号已存hash匹配；此诊断没有建会话或改库。
重新聚焦空密码框、等待IME、核对完整40位并滚动表单后，正常登录成功。不推断丢失输入的精确根因，
也不把离线比较当作手机登录通过。安全键盘/自动填充使部分选择器不可见，曾出现密码管理器锁定提示；仅关闭提示，没有解锁/读取密码库或改相关设置。

退出/重登后退回已打开的“我的”页，该旧路由仍显示需要核对登录的AccessClosed状态；
其捕获的authority已失效。本轮按现有流程回首页再进入通道，创建新路由后内容/大图可读。
保留这个导航观察，不声称旧路由自动恢复、全App无缺陷或已修复该体验；没有修改路由/认证代码。

安装和收尾的宿主runner还遇到：包不存在时`pm path`返回1、初次显式host的ADB listener不受支持、
MediaStore删除回显与预期文字不同、空reverse-list尾行比较不同。均先核实际状态再继续，没有自动重放卸载或删除未知文件。
实际专用listener PID/可执行路径已在停止前核验，绑定loopback5049；不触碰5037或其他session的SDK/缓存/服务。
Windows ADB使用既有OS profile USB身份，操作者仅核metadata且前后不变；不声称新建了隔离Windows USB key。

## 复现入口与当前收尾

继续沿用[运行手册](android-prerelease.md)中的干净源码构建和保留lab启停路径。新窗口必须先获用户开放、核目标手机与同包归属，
核APK/签名/CA和叶证书有效期，再显式start/recover/health；不能对lab-09重跑init。
用新下载到任务目录的官方platform-tools，专用非5037服务和明确serial，只对C/V两个端口使用`reverse --no-rebind`。
逐项通过实际正常UI执行上表，不复用其他任务账号、手机或库；前述卸载授权仅属于本轮明确的旧包，不可推定为以后清除其他数据的授权。

09:44:58前已收回本任务临时合成图片和Gal输出、UI临时文件、C52045/V37073映射及专用ADB；
其他映射的非空条目与开始一致。后端进程记录为空、C/V端点关闭、五个PG均status3。
没有系统CA安装、明文TLS、Gate/权限放宽、全局代理或手机安全设置变动。
本任务工具、APK、签名和非空恢复库私有保留；测试App仍安装但后台已停，不具备持续在线服务。

未验：同包升级、手机端负TLS/Gate冻结、完整原生存储安全、整机重启/OEM、多图/动画/大图矩阵、
系统相册浏览UI、当前APK完整TalkBack和Passkey、物理设备部署回滚、非空处罚/申诉/管理员/audit恢复及生产。
跨设备Passkey和iOS继续延期。PR #16仍未合并、未正式发布；证据提交后的最终head检查另在PR按精确SHA核对。
