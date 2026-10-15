# 第三项系统 Passkey 单机实测与剩余阻塞

2026-10-15，Asia/Shanghai。**PARTIAL：真实系统 Passkey 创建、可发现恢复、绑定丢响应后的跨进程原结果核对通过；第三项整体尚未通过。**坏签名/未关联包没有得到明确的关联拒绝，严格默认 HTTPS 抓取仍失败。设备操作已于 08:26:05 UTC（16:26）结束，后续使用须重新确认窗口。

本轮起始及实际被测产品均为 `9dda242b21694af1c4c33f11784958851c805fc4`；固定认证来源 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。目录 `E:/HnuHole-community-f4-20261012/repo`，分支 `codex/community-flutter-pages`，origin 已核对为 zewbby/HnuHole。本轮不改页面、AuthFlows、session/HTTP、closure、原生 vault/passkey、产品 manifest、Go/SQL/权限、协议或依赖锁。最终保存提交仅包含公开测试关联、实际执行的测试/实验源文件和脱敏交接。

完整计数、APK摘要、原始记录摘要和主机阶段时间/退出码见[机器记录](community-android-stage3-device-validation-20261015.json)。205 项 mobile/plugin 输入与构建镜像/固定 Git blob 核对，指纹 `5bc83b4d98a46a7db8ea0139fb76073bbc87e17efaa59aac0c324c8f5e677631`；主机回归和设备实测覆盖该产品状态，不能用准备阶段 mobile322、旧311或认证22/0/2代证本轮。

## 获准配置、隔离与制品

用户先批准独立 Cloudflare Pages 测试项目及独立 RP `hnuhole-community-passkey.pages.dev`，后明确批准仅新增正向 `.passkey.control` 关联与安装。原认证域名/签名/环境均未改变。当前[公开关联及审批范围](community-android-stage3-applied-20261015/proposal.json)只含两个包及证书 `3309ce001a5dfd93148c14e35159147a6711e4b61d881b7a223b3e8429665e34`；坏证书和 `.unassociated` 包仍排除。C 的 Android origin 固定为 `android:apk-key-hash:MwnOABpd_ZMUjBTjUVkUemcR5LYdiBt6Ijs-hClmXjQ`，新增包没有改变 C 的 RP/origin 配置。

当前部署 ID `f791f91a-4cc7-4bc0-8816-28fd32e84c33`，assetlinks 676 bytes，SHA256 `886f286883a7889c11acbcb3ec5a353aaee34e5287fd018b8ee70dc5692dc17b`。首次单条部署 `33244fe9-480d-48cd-90c0-afb70bdf701d`、旧文件摘要及其观察保留。Cloudflare UI 的 Production 标签属于此独立测试站点，不是 HnuHole 生产发布；未发布 Release、合并 main 或部署业务生产服务。

手机 vivo S18 / V2323A，Android15 / SDK35，ARM64，单实体。按用户明确批准沿用既有 USB 身份，仅核对元数据，不读取/复制/更改 key；使用本任务独立 ADB server 34881，并在操作前后核对监听进程、启动时间及 exe。新 reverse 46511/52813/42757 仅指向 task3。没有调用全局5037、手机模拟器或认证会话设备服务。

| APK | 包名后缀 | SHA256 | 实际状态 |
|---|---|---|---|
| 配置后的原正向包 | `.communityf5.passkey` | `af4354f3ad2652fd6b0a3891b2a4702911dbf271cae6a232958bb2034711d334` | 已构建未安装；同名坏签名结果未决，未卸载替换 |
| 坏签名对照 | `.communityf5.passkey` | `b387216a4fbcfc770c86bcd90da1470aaefe317e1beb7dbf8a8be1c8300a644d` | 已安装并保留；证书 `08cddd6d…412e849` |
| 未关联对照 | `.communityf5.passkey.unassociated` | `12e48a9643c232faea7b70d469d978816ea20ed4632015e72b14ed6ed79718b3` | 已安装并保留；批准证书但包未关联 |
| 额外正向控制 | `.communityf5.passkey.control` | `69a2894d22f36d337f5d485456a1c927d6231a0379668022e7695e4d26b4b1d3` | 已安装；本轮实际正向流程使用此包 |

完整包名前缀 `org.hnuhole.hnuhole_mobile`。坏签名包与原正向包 560 个非签名条目完全相同。镜像只套用获准 applicationId/debug关联/RP及独立 TLS 地址，不复制认证工作树。正常 task1/2 App 摘要 `f9a2ea7ed783fc5051743ee220ed3087a204d42aed0ae35b94c81fa09c987a13` 前后相同，未卸载、清数据或换签名；TalkBack 保持关闭。

独立 Linux 根 `/home/hnuhole/community-android-stage3-execution-20261015`，Windows 根 `E:/HnuHole-community-f4-20261012/stage3-execution-20261015`，owner `HNUHOLE_COMMUNITY_ANDROID_STAGE3_EXECUTION_20261015_V1`。新项目 `hnuhole-community-s3-e974f2621f`：Cdb48999/Vdb49187、SMTP43747/mail42757、C54119/V52813、internal57151/39103、proxy46511。正式 C13/V4 迁移、最小授权、真实 cmd/Gate/watch，无测试认证或时钟 overlay。只创建两个本轮合成账号，帖子0，不连接认证/未知库。

Flutter SDK/cache 使用既有社区专用 `/home/hnuhole/community-android-stage1-20261014-tools`，经 owner 核对及 `community-build.lock` 串行；未使用共享 SDK、升级依赖、删除锁或安装工具链。开工容量已检查；大文件均在 E 盘/该盘 WSL，结束前主机观察 C 约13GB、E约121GB余量；未向 C 盘恢复大型缓存，未改全局 PATH、代理、证书或系统设置。

## 本轮手机结果

| 检查 | 结果 | 真实观察与边界 |
|---|---|---|
| S3-01 正向关联 | PASS（文档/API范围） | 浏览器内容精确匹配审阅文件；初次 Google Check 未给新包 linked，08:45:14 UTC 再查两关系均 `linked=true`。Google List 也含两包；这些均不单独代证 provider |
| S3-02 严格 HTTPS | FAIL | 原 checker 默认请求得到 HTTP403/Cloudflare1010 `browser_signature_banned`；未改 UA/TLS/代理或网站安全配置来转绿 |
| S3-03 坏签名 | BLOCKED | 实际 native begun1/timeout1/errored1；用户点继续但没有系统身份确认。没有明确 association rejection，未向 C 提交，包保留 |
| S3-04 未关联包 | BLOCKED | 实际 native createCancelled1、OtherCreateError1，非超时；没有明确 association rejection，未向 C 提交。普通取消不能算拒绝通过 |
| S3-05 正向创建 | PASS | control 包真实 provider 成功，nativeSucceeded1；C 校验证明后插入一条 Passkey，未注入/伪造证明 |
| S3-06 绑定丢响应、跨进程核对 | PASS | 仅丢真实 C 的204；POST1/唯一键1/Passkey1，进程15503→21391；核对两次原键+challenge hash匹配2、不匹配0，未新开 native 创建，App显示已确认提交 |
| S3-07 自然期限 | PASS（观察范围） | CREATE 和 RESET 正式 challenge 均观察到恰好五分钟后 EXPIRED；无缩短期限/改时钟。未发送过期签名证明，不称该负向端到端通过 |
| S3-08a 第一次可发现恢复 | FAIL（保留） | native 60秒超时，provider sheet仍显示；C reset提交0。仅关闭本轮已超时 sheet，等正式 challenge 自然EXPIRED后才新开第二次 |
| S3-08b 新挑战恢复 | PASS | 第二次 native succeeded，C消费RESET challenge；无输入校邮/用户名寻找账号，恢复目标在私有材料内核对一致。系统身份确认由用户操作，不推断具体用了指纹还是其他方式 |
| S3-09 新凭据确认 | PASS | 实际 App 隐藏后完整重输新恢复码、新密码，提交1次；显示密码重设成功且不自动登录；SQL version1→绑定2→重设3、resetGeneration1、Passkey0、reset intent消费1 |
| S3-10 后续登录与存储 | PASS（限定范围） | 新密码显式登录成功；进程21391→28628，真实原生 vault 恢复已登录通道页。主机真实 C 另拒绝旧密码、旧恢复码、原注册token，三项通过 |
| S3-11 活跃旧会话独立证明 | NOT_RUN | 原注册token在重设前已被后续登录替换，不能据其401断言本轮设备独立证明reset撤销活跃旧会话；服务端回归仍另有范围 |
| S3-12 其他负向 | NOT_RUN | 单独的用户主动取消、提交过期签名证明未执行，不用笼统取消/自然到期观察替代 |

原生 provider 故障归属边界：Dart/Android桥没有成功证明就不会构造 C 提交，超时/取消不转换成功；服务器未绕过证明验证。当前证据不足以把坏签名/未关联结果认定为 DAL 拒绝。有限 vivo provider 日志未提供明确拒绝栈，Google provider UI 进程当时未出现；不改产品错误分类、关联白名单或认证验证条件以让测试通过。

首次恢复的60秒超时与未自动关闭的系统 sheet 是实测问题，后一次成功不抹去它。下一窗口需定位当前 vivo provider 生命周期/错误返回，取得有时间、包、进程对应的明确拒绝；必要时在用户批准后用支持的 provider/另一设备复验。禁止在未知 native 创建结果仍可能留有孤立凭据时卸载、换签名或盲重复创建。

## 主机回归与复验入口

日志根 `E:/HnuHole-community-f4-20261012/stage3-execution-20261015/logs`。最终七阶段实跑记录在 `final-host/commands.tsv`，本轮08:29:02–08:51:14 UTC七阶段全部exit0；具体时间/退出码见机器记录的 `hostRegression.stages`。

```bash
# 本次实际使用的顺序 wrapper（已执行，有 started 标记，不能直接再跑）
bash /mnt/e/HnuHole-community-f4-20261012/stage3-execution-20261015/run-final-host.sh
# wrapper 实际逐项调用；无 module 等虚构参数
bash tools/run-community-flutter-f4-linux.sh checks
bash tools/run-community-flutter-f4-linux.sh auth-regression
bash tools/run-community-flutter-f4-linux.sh integration
bash tools/run-community-flutter-f4-linux.sh server
bash tools/run-community-flutter-f4-linux.sh posts-privileges
bash tools/run-community-flutter-f4-linux.sh auth-runtime
bash tools/run-community-flutter-f4-linux.sh vet
```

checks 为 mobile334、分析0；R05实际 HTTPS/SQL、F4-H01–H08 八项重新执行；server 使用新一次性 PG/private socket 和 race（authprivacy约984秒）；posts-privileges检查受限runtime及生命周期；auth-runtime运行真实cmd/正式迁移/Gate；vet为最终Go静态检查。不得把前三阶段完成时的中间记录当作七阶段已通过；最终机器记录须有七条exit0。

最后交接时另运行现有 `python -B -X utf8 -m unittest discover -s tools/tests -p test_community_android_stage3.py -v`，9项守卫PASS，未改checker或批准边界。配置构建前另实跑 Passkey Dart9 与 JVM24，输出 `logs/passkey-dart-tests.jsonl`、`logs/jvm-policy.log`；全量mobile亦单独通过334项。新建账号夹具只跑一次：`bash .../create-fixtures.sh`，真实AuthFlows/C/V/SMTP，1项PASS；实际密码重设后 `bash .../run-post-reset-host.sh` 三项PASS，日志 `post-reset-host.private.jsonl`。它使用文件vault只取原夹具，不代证原生；原生会话证明来自手机强停重开。

本次实际实验/测试源码归档于 [execution-20261015](../../tools/community-android-stage3/execution-20261015/README.md)，其与外部执行文件原始字节摘要逐一登记。`lab.py` 只为本轮 owner/loopback/独立库服务，proxy真实转发、只丢204并暂拦GET核对，不伪造proof或成功响应；原始键/challenge只记hash，日志不保存token/proof。手机UI与有秘密的原始截图/fixture留在外部，Git无账号/恢复材料/数据库/私钥/APK/cache。

本轮构建过程曾因DrvFS权限和 Windows CRLF/LF直接cmp失败；保留日志，按Git canonical blob/符号链接语义核对后通过，没有删锁/改比较常量。最终SQL审计初误期望version2，读未修改绑定/重设源码及事件后更正为1→2→3，原失败输出保留，不归为产品缺陷。未关联包输入时曾丢首字符，UI确认纠正后登录成功；不计成认证故障。新增独立控制包的Google早期未确认记录同样保留，后续API显式true另存，不能倒改历史。

最终交接/归档源文件之后没有产品、SQL、manifest、锁修改；七阶段覆盖最终提交中的全部实际产品运行输入，源码归档与已执行版本按hash一致。没有将旧322/311或旧八项主机结果重复计数。

## 解阻条件与保留材料

1. **严格公开HTTPS仍FAIL。**原命令 `python tools/community-android-stage3/check-association.py --bundle docs/design/community-android-stage3-applied-20261015 --confirmed-approved-domain-control-and-deployment`；默认TLS/头部未改。需继续定位独立测试站点403，提出具体托管/规则方案再审批；不擅自降低Cloudflare保护。当前浏览器和Google检查通过不覆盖该失败。Cloudflare对[1010的说明](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1010/)与本次响应类别对应；不据此推断所有provider都被拦。
2. **provider两项负向仍BLOCKED。**已保存同包同载荷坏签名对照和未关联包的时间/进程/native计数、无C提交与有限日志。下一窗口先核源/APK/关联/所有权，取得真实明确拒绝，再决定坏签名包生命周期；不删除未知结果。
3. **补独立单机负向。**按新窗口做主动取消、活跃旧会话的重设撤销，过期签名证明若有安全且不重放的现成测试入口再做；无法执行仍明确NOT_RUN。必要产品修复后重跑受影响测试。
4. **任务4、iOS、生产。**NI-X01/NI-X02需要第二实体Android和两机窗口；macOS/Xcode/iOS与生产运营部署证据单独待验。本轮用户接受单机范围不等于豁免这些任务。

三个新手机包及其数据未卸载/清理。原生超时可能残留孤立provider凭据，因此保留本轮独立lab、签名和必要日志/APK以定位，后续清理须先确认终态/实际资源归属和所需保留材料；不得全局Docker prune、清SDK或停止其他服务。较早 `lab-failed-01` 项目 `hnuhole-community-s3-464484e038` 也保留独立标记，未复用其库。七阶段自己新建的临时PG/Docker资源由各runner仅按本次归属清理。手机窗口已结束，工具有结束标记阻断后续ADB。

Google API依据：[Check](https://developers.google.com/digital-asset-links/reference/rest/v1/assetlinks/check)、[List](https://developers.google.com/digital-asset-links/reference/rest/v1/statements/list)。仅明确的 `linked=true` 计作Check通过；List、浏览器文档和实际ceremony各有独立证明范围。

当前验收口径：固定源码的主机检查可复验，单机正向Passkey及关键未知结果恢复已有证据；第三项部分完成，等待公开HTTPS和provider负向收口。任务1/2的限定通过保留，完整模块/App未升级PASS。

## 修改与最小复现交接

本轮修改清单为四份要求的交接 `HANDOFF.md`、`progress.md`、`module-acceptance-handoff.md`、`module-acceptance-ledger.json`，另更新 `community-flutter-f4-machine-handoff.md`、统一四阶段任务单及 stage3 README；新增本报告/机器记录、当前 applied 目录下公开 manifest/assetlinks，以及 execution 归档的8份实际源文件和README，另在仓库.gitattributes仅为当前公开DAL与归档源码固定LF，避免Windows换机破坏字节摘要，共21文件。无产品实现变更；最终HEAD、推送回执和未提交状态在最终交付时另核对，起始SHA不变。

provider负向最小复现：在新确认窗口内核对本轮包/证书、当前公开关联及专属lab；用本轮合成账号正常登录坏签名包或未关联包，在凭据管理点击一次绑定，用户只操作本轮RP系统页。对照实际native开始/终态计数、当次provider进程/时间与C的绑定提交计数。当前坏签名终态为60秒超时、未关联为取消，C均未收到绑定POST；这只能证明未提交，不能证明provider明确验证并拒绝关联。旧Google诊断脚本的认证RP/包硬编码不适用，未运行或放宽其守卫。

阶段归属：A07为可发现恢复/完整确认与无自动登录，A09为绑定/原结果核对/正式C校验和SQL清理，N03为真实native/provider及未决负向，N01/A12仅增加实际新会话原生重开证据；这些模块整体继续BLOCKED，任务2的既有限定PASS保留。更早固定认证d859cb0的交付不因本轮vivo差异被擅自改写；若需认证改动，先交付上述最小复现、计数和实际边界，再由认证责任方确认。
