# 第三项三处剩余项集中补验

2026-10-16，Asia/Shanghai。本轮针对用户明确列出的三处缺口集中收尾：**错误关联的明确拒绝、脚本直连公开关联文件、主动取消及重设密码后撤销活跃旧会话**。手机补验已完成并恢复原设置；最终主机七阶段全部退出0，当前登记批准的单Android范围PASS，详见[机器记录](community-android-stage3-closure-20261016.json)。第二实体Android、iOS、生产与完整模块/App仍不在本轮通过范围。

起始 `4fc0ce873a576f7d83f3bd6dfb0db49ec5dcd939`，分支 `codex/community-flutter-pages`，origin 为 `https://github.com/zewbby/HnuHole.git`，独立目录 `E:/HnuHole-community-f4-20261012/repo`；起始工作区干净。认证固定来源仍为 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。未进入认证会话工作目录，不合并其他分支，不修改认证协议、权限、SQL、产品manifest、原生实现、业务页面或依赖锁。

## 三项结果及对应证据

| 用户要求 | 本轮结果 | 真实证据 |
|---|---|---|
| 坏签名明确拒绝 | PASS，Google provider限定范围 | 同RP、同包/非签名载荷、错误证书；当前请求的ValidateRpId→50152→terminal error，匹配已安装26.39.33版本的校验器栈；无网络错误；C绑定POST0 |
| 未关联包明确拒绝 | PASS，Google provider限定范围 | 同RP、批准证书、排除包名；独立当前请求的同类50152/终态错误/版本栈，无网络错误；C绑定POST0 |
| 脚本访问公开文件 | PASS，Windows及WSL Linux直接HTTPS | 不伪装浏览器，使用真实工具标识后，直接200、application/json、676字节精确内容/摘要核验通过；公有TLS、主机名、禁止跳转、64KiB界限均保留 |
| 主动取消 | PASS，真实单机系统页 | 用户明确点击关闭；正向控制包nativeBegun1/nativeCreateCancelled1/nativeErrored1，无timeout/success，C绑定及reset提交0，没有新凭据 |
| 重设后撤销活跃旧会话 | PASS，真实C/HTTPS/PostgreSQL | 同一token在重设intent前后均有效，真实提交后立即401；Passkey服务端生命周期另确认同一token提交前有效、提交后ErrSessionInvalid及未撤销会话数0 |

以上五个检查合并对应用户的三条要求。App/Android框架在两项关联负向仍只回泛化取消；**不把该取消计作关联拒绝**。明确结论来自同次Google provider的RP校验日志、唯一请求、进程/时间、实际安装版本、终态、栈与网络排除。没有将超时改成拒绝，没有改变产品错误分类。

## 设备与配置操作

用户本轮确认 vivo S18、45–60分钟、认证会话已释放、沿用已批准USB身份及现有第三项包，随后明确批准只恢复本任务两Gate及临时切换已安装Google provider；原vivo值在任何结果下都须恢复。实际手机窗口约18分钟，结束 `00:37:26 UTC / 08:37:26`，结束标记阻止进一步ADB；没有延用昨天已结束的窗口。

三个现有APK均核对昨天的固定SHA，未安装、卸载、清数据或换签名：坏签名 `.communityf5.passkey` 为 `b387216a…30a644d`，未关联 `.passkey.unassociated` 为 `12e48a96…9718b3`，正向 `.passkey.control` 为 `69a2894d…6b4b1d3`。完整包名前缀 `org.hnuhole.hnuhole_mobile`，完整摘要见机器记录及[昨天记录](community-android-stage3-device-validation-20261015.json)。正常task1/2 App摘要 `f9a2ea7ed783fc5051743ee220ed3087a204d42aed0ae35b94c81fa09c987a13` 未变，全部数据保留，TalkBack关闭。

ADB专属34881在本轮前已不存在；核对端口空闲后仅启动此前已批准的本任务ADB副本，保留新进程/启动时间/exe witness于本轮目录，不覆盖stage2旧state，不接全局5037。USB身份仅核元数据，无key读取/复制/生成/修改。46511/52813/42757反向映射仅恢复本任务精确端口，其他映射保留。

手机结束后仅通过Windows进程元数据核对并停止本轮新启动的专属ADB，释放USB占用；不执行窗口外ADB命令，不停止全局5037或其他服务。两次聚焦验证的自有PG临时根均在进程停止、精确绝对路径/创建时间/owner/启动参数核对后删除，仅保留日志；未清其他F4或手机lab。

最初只启用vivo的Cipherchain provider。用户批准后临时将已安装Google PasswordAndPasskeyService设为首选，vivo仍保留启用；没有安装provider、创建/登录Google账号、读取个人密码库、修改同步或系统验证设置。结尾两个 `credential_service` / `credential_service_primary` 值已逐字恢复原vivo值，回滚watchdog仅用于本次已批准窗口并随恢复记录退出。配置前后值、审批方案及恢复证据在本轮外部目录；公开机器记录仅含组件名和恢复事实，不含账号。

同一手机的正向创建/可发现恢复已经由昨天vivo provider与真实C验证，本轮两项负向由获准临时Google provider给出明确结论；这不是“所有OEM/provider均通过”。Google安装版本实际为26.39.33（versionCode263933035）；现有host verifier保留原历史默认规则，新增显式版本profile `cvtf/cvte.a/cvtg.g`，要求日志帧中的实际版本一致。未知版本、缺终态/栈、混进程、过期/重叠请求、任何网络错误仍拒收；9项verifier测试通过。

第一轮 `bad-google-01` 同时出现 `ERR_NETWORK_CHANGED` 和50152，明确不计PASS。用户要求重试后保留首轮记录，以新挑战、新App进程的 `bad-google-02` 得到无网络错误的明确拒绝；未关联包的 `missing-google-01` 独立通过。系统返回后OEM selector一度留下覆盖层，仅对已确认取消/错误的本轮selector返回，再强停重开获准任务包；不把仍在执行的native请求强行替换。旧未知记录不删除、不倒改。

主动取消由用户在正向控制包的系统创建页明确关闭，不自动按指纹或系统密码。C代理本轮累计options4、bindingSubmits0、resetSubmits0；SQL账号仍2、Passkey0、帖子0，无新副作用。新增challenge按正式五分钟规则自然结束，不缩短期限、不改时钟。

后续只读SQL核对正向/负向账号凭据版本仍为3/1、resetGeneration仍为1/0、各有1条未撤销会话；没有因取消而变更凭据。该观察不访问手机、不导出账号标识。

## HTTPS修复与边界

独立RP仍为 `hnuhole-community-passkey.pages.dev`，公开关联仍只有先前获准的两个包/同证书，文件SHA256 `886f286883a7889c11acbcb3ec5a353aaee34e5287fd018b8ee70dc5692dc17b`。本轮没有重部署、添加关联或降低Cloudflare规则。

对照实验：Python默认标识得到403/1010；真实工具标识 `HnuHole-DAL-Checker/1.0 (+https://github.com/zewbby/HnuHole)` 得到直接200及精确原文件。`check-association.py` 仅补此诚实User-Agent，未使用浏览器标识、cookie、代理、TLS忽略或挑战绕过；默认urllib失败历史保留。新的10项stage3测试同时核对工具标识、空代理、NoRedirect、TLS主机名/证书、响应界限与精确JSON。

Windows与Linux均实际执行以下命令并PASS，不以浏览器/Google结果替代直连检查：

```powershell
E:/acanda/python.exe -B -X utf8 tools/community-android-stage3/check-association.py --bundle docs/design/community-android-stage3-applied-20261015 --confirmed-approved-domain-control-and-deployment
```

Google独立Check补充矩阵：正向包明确linked=true；坏签名/未关联未返回true，保存原响应而不捏造显式false。它只辅助核对公开关联，负向通过仍须实际provider证据。[Cloudflare1010说明](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1010/)与本次默认客户端类别一致；[Android错误说明](https://developer.android.com/identity/sign-in/credential-manager-troubleshooting-guide)也要求区别取消、DOM错误与关联配置，不能凭取消判断拒绝。

## 活跃会话补验与最终源码覆盖

新增源码只有两处真实回归断言：

- `apps/mobile/integration/auth_public_https_postgres_test.dart`：保留token，实际HTTPS校验在恢复intent前后仍有效；真实C重设已提交但响应被丢弃后，同token立即拒绝。随后原未知结果核对/无自动登录/新密码流程继续执行。
- `services/api/internal/authprivacy/community_credentials_test.go`：既有Passkey生命周期已经证明intent不撤销会话、提交后SQL无未撤销会话；追加相同token必须返回ErrSessionInvalid。

后者WebAuthn证明来自测试签名器，数据库/C逻辑是真实代码；不宣称本轮手机又做了一次Passkey重设或持有另一台设备的活跃会话。用户要求的“活跃旧会话撤销”由真实HTTPS/SQL与Passkey服务端路径分别补证；手机昨日的真实Passkey重设和本轮取消/拒绝保持各自版本范围。

先行聚焦Go验证因临时DSN遗漏与runtime tag匹配的application_name，被原隔离守卫拒绝，未执行schema reset；失败日志保留。未放宽守卫，改为新private-socket一次性库及正确tag后，目标测试race PASS。随后完整server阶段再次覆盖同一最终测试源码。Dart只保留21行聚焦新增，未引入无关格式改动。

本轮所有产品编译输入与已实测APK来源9dda242保持一致；205项旧设备输入指纹 `5bc83b4d98a46a7db8ea0139fb76073bbc87e17efaa59aac0c324c8f5e677631` 仍对应旧APK。新增测试及host工具属于最终511项tracked运行/测试输入，完整清单和新指纹在机器记录；不将205旧指纹称作新测试源码指纹。最终交接/台账变更不影响运行输入。

## 实际命令、日志与隔离

本轮外部根 `E:/HnuHole-community-f4-20261012/stage3-closure-20261016`，owner `HNUHOLE_COMMUNITY_STAGE3_CLOSURE_20261016_V1`。日志在其 `logs/`；脚本源码摘要在机器记录 `executionSourceSha256`，不将本机账号fixture、原始provider日志、截图、私钥、数据库、APK或cache入Git。

| 执行 | 结果/日志 |
|---|---|
| 先行auth-regression/checks/integration/vet | 四项PASS，`logs/commands.tsv`；不替代最后七阶段 |
| 最终checks/auth-regression/integration/server/posts-privileges/auth-runtime/vet | `logs/final-seven/commands.tsv`逐项起止/退出码；mobile334/分析0、F4八项，真实SQL/race/权限/runtime/最终vet |
| 定向Passkey生命周期race及vet | `logs/passkey-lifecycle-02.log`、`logs/final-vet.log`；目标1项PASS；首轮守卫失败另留 `passkey-lifecycle.log` |
| Windows Python全量 | `python -B -X utf8 -m unittest discover -s tools/tests -v`，162中159 PASS、3 POSIX SKIP，`logs/python-windows.log` |
| Linux Python全量 | `python3 -B -m unittest discover -s tools/tests -v`，162 PASS、0 SKIP，`logs/python-linux.log` |
| 手机三类补验 | `ui.py`、`observe-case.py`、`verify-provider-cases.py`、`finish-phone.py`；当前进程/时间/版本/行摘要记录，无原始证明 |

最终七阶段实际wrapper：`wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/stage3-closure-20261016/run-final-seven.sh`，顺序调用仓库 `tools/run-community-flutter-f4-linux.sh <stage>`。已经有started标记，不删除后重跑旧窗口。继续使用核对owner的社区专用SDK/bin/cache及community-build.lock，未安装工具链/升级依赖/改全局配置；C开工余量约14.55GB、E约128.87GB，大制品不回C盘。

手机使用的是本任务昨日新建的一次性项目 `hnuhole-community-s3-e974f2621f`，其明确归属/端口/容器/卷核对后仅恢复原数据服务。起初ready503；用户批准后原命令恢复C/V两Gate到200，原账号及数据数量不变，旧第三项会话按代次正常拒绝后重新密码登录。不是认证/未知库，不重置schema，不生成新签名材料。主机回归另建全新的private-socket PG或自有Docker项目；测试schema reset从未传入手机保留库。

## 验收结论边界与后续

本轮三处缺口在上述限定范围已补齐；结合先前未改变的真实正向证据，第三项可登记“批准的单Android范围通过”。模块A07/A09/N03完整平台状态仍BLOCKED，不能将临时Google负向结果外推vivo所有错误路径、iOS、双设备或生产。

不新增本轮通过条件：第二实体Android NI-X01/NI-X02仍按第四项单独执行；iOS/生产另行安排。先前自然五分钟到期观察保持原范围，未另发过期签名证明；昨日OEM超时/sheet生命周期及旧未知调用保留历史，不宣称已修复所有provider。三个测试包及旧未决材料保留，无卸载/换签名/清数据；手机窗口已结束，后续任何设备使用重新确认。本轮提交/推送仅正常更新当前分支，不合并main、发布Release或部署业务生产。
