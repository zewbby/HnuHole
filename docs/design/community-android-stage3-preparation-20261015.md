# 第三项无手机准备报告

2026-10-15，Asia/Shanghai。**可独立执行的主机验证、签名对照和配置审阅准备完成；RP配置落地、最终设备候选和手机验收仍阻塞。**用户已选定独立RP方案继续核实，此选择不授权注册、公开部署或应用安全配置。没有把第三项、单机阶段或完整App记为验收通过。

本轮起始 `0c8e2470d6281785ba9e6ff647cfc2aa7fc19cc4`，origin核对为 zewbby/HnuHole，分支 codex/community-flutter-pages。期间检测到并行手机任务的已提交 `e0c128033682923d519ea99546d72503b085a99e`，完整保留；它只改手机守卫/交接，没有产品变更。产品仍固定 `b5accf36b90e27829b6d039cd58a5b9c189a3da8`，认证来源 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。第三项不复制认证会话或并行USB任务的未提交代码，不执行它们的设备操作。保存与推送见本轮交付回执。

## 新增与保留边界

新增 `tools/community-android-stage3/` 的 baseline build、APK核验、review-only proposal和获准部署后才可运行的只读DAL核验入口，及9项主机守卫测试。没有修改F1–F3页面、Dart/Go产品、AuthFlows、session/HTTP、closure、原生vault/passkey、manifest、SQL、权限、协议或依赖锁。没有新增业务功能。

已准备3个本任务新调试签名的ARM64 Debug APK：独立 `.communityf5.passkey` 控制包、同签名 `.passkey.unassociated` 包、同控制包但不同签名的对照。错误签名包560个非签名条目与控制包完全一致，199项镜像输入逐项核对；SQLite原始固定哈希与strip后APK文件分别核对。它们只应用applicationId overlay，保留原源码Debug资源，**没有应用新RP/CA/C配置，不能直接算正向Passkey验收候选**。公开证书为 `3309ce001a5dfd93148c14e35159147a6711e4b61d881b7a223b3e8429665e34`，私钥只保留于本任务外部材料。

具体域名、唯一package/cert、Android origin、两项DAL关系、新C初始化参数、XML/Dart差异、负向排除和配置/设备步骤已成套保存到[关联方案](community-android-stage3-rp-proposal-20261015.md)与[公开审阅目录](community-android-stage3-review-20261015/)。用户选择 `hnuhole-community-passkey.pages.dev` 方案后，只做公开DNS/HTTPS核查：DNS有解析，未取得可验证的HTTPS关联文档。**不证明项目名可注册、账号或域名控制权**。没有创建托管账号/项目、登记DNS、发布站点或应用安全配置。

## 本轮实际验证

外部日志根 `E:/HnuHole-community-f4-20261012/stage3-preparation-20261015/logs`。七阶段实际wrapper为同目录上级 `run-regression.sh`，依次执行仓库真实入口 `bash tools/run-community-flutter-f4-linux.sh <stage>`；命令、退出码、时间与原日志在 `logs/regression/<stage>.*`。本表最终结果须与[机器记录](community-android-stage3-preparation-20261015.json)及 `.exit` 一致，旧认证22/0/2和旧mobile不计本轮。

| 实际入口 | 本轮结果与范围 |
|---|---|
| checks | 分析0；mobile322非隐藏测试PASS、0失败/跳过，实际机器流在 regression/mobile-tests.jsonl |
| auth-regression | R05真实Dart→HTTPS→SQL PASS；主机native端口替身不代证Android |
| integration | F4-H01–H08本轮8项PASS，保住原命令/身份通道、删除丢回复、账号隔离与闭号清理 |
| server | 新一次性PG/private socket，六测试包含SQL/race和内置vet PASS；authprivacy约879秒，未放松安全检查 |
| posts-privileges | 受限runtime、PostSchema9顶层与4生命周期PASS，正式权限边界不变 |
| auth-runtime | 实际cmd、正式迁移C13/V4、独立证据与Gate/SQL的25断言PASS；包含本次临时资源cleanup |
| vet | 最终 `go vet ./...` PASS |
| Passkey Dart | mobile原锁依赖图下，库 `native_passkey_client_test.dart` 9项PASS，取消/迟到/忙碌/错误边界；不代证系统provider |
| JVM | 现有 GoogleFidoDiagnosticPolicyTest 24断言PASS，不调用Android API |
| Python工具 | 固定e0c1280主机快照＋本轮新增文件：Linux148 PASS；Windows145 PASS＋3 POSIX SKIP；新增9项两平台PASS |
| 构建核验 | 两次实际Flutter Debug构建、一次独立重签及3包验签/manifest/ARM64/SQLite/199镜像/560载荷条目PASS |
| 草案检查 | 新目录/拒覆写、精确域名/package/cert、两个关系、负向排除、无确认先拒绝联网、redirect拒绝、200/JSON/64KiB/精确文件等主机测试PASS |

Passkey库没有单独跟踪lock：最初错误地要求其 `--enforce-lockfile` 被工具拒绝后，改用已锁定mobile依赖图运行库测试，没有删锁、生成新仓库锁或升级依赖。为隔离并行工具编辑，Git archive初次导出受Windows autocrlf转换影响，5个历史byte-exact fixture测试拒绝；已在自有导出目录用**单次命令级**LF归档恢复原始blob，未改常量/依赖/源锁，最终148项通过。原失败日志保留，不冒充产品缺陷。

新public bundle最初在drvfs chmod时中断；删除其不完整目录被自动审批拒绝（仅返回blocked by policy）。保留该目录，改用新的 `review-bundle-final` 成功生成，工具已移除对Windows ACL的错误POSIX推断；正式审阅目录和版本化副本均完整。没有绕过删除拒绝、清理未知资源或应用草案。

## 固定输入与最终源码覆盖

[本轮指纹](community-android-stage3-source-fingerprint-20261015.json)包含452项未变产品/构建/运行输入＋本轮5项工具/测试，共457项，SHA256 `e185849eaac2d37d5b2988f21b54a2edb3d9f3326ecd71e2d5487f74f02c6ca9`。并行手机任务的4项runner/test单独固定在e0c1280、以快照完整测试；其后续未提交USB变更不读入/复制/计算为本轮覆盖，也不覆盖或回滚。验收记录明确区分此快照与工作区其他会话的实时改动。

七阶段与本轮构建覆盖最终未变产品输入；新工具实际核验及两平台9项新增守卫覆盖最后工具内容。仅交接/审阅文档变化后不重复执行产品测试。历史task1标准Release构建及task2原生35项的**构建**证据保留原版本，本轮不将其写成新Release/原生设备通过；没有改Release配置或发布。

本轮没有ADB或手机操作。task1/2的manifest、APK、公开CA和artifact proof在本轮前后hash相同。并行手机任务自己的设备/日志/USB状态归其会话，不宣称其状态未变，也不把其授权外推给task3。

## 工具与资源隔离

本轮Windows root `E:/HnuHole-community-f4-20261012/stage3-preparation-20261015`、WSL root `/home/hnuhole/community-android-stage3-20261015`，owner均为 HNUHOLE_COMMUNITY_ANDROID_STAGE3_V1。只顺序复用现有社区专用SDK `/home/hnuhole/community-android-stage1-20261014-tools` 及当前社区pub/Gradle cache，独立HOME/调试key/镜像/temp/log。先完成F4涉及Flutter的checks/R05/integration，再构建；没有调用原共享SDK或安装工具链。

七阶段使用当前任务root及独立55446端口、每次新建private-socket PG或runner自建新Docker项目/一次性库；清除继承DSN，未连接认证或归属不明的库。任务1现存待验环境不用于task3回归或Passkey配置；未操作其他服务、ADB5037、系统证书/代理/PATH、手机/模拟器。C盘开工余量19,078,238,208bytes、E盘154,125,262,848bytes，大型制品/缓存都留在E盘及其WSL。

按用户“提前准备”保留本任务签名、候选、日志与缓存，APK/key/数据库/大制品不进入Git。仅新增公开配置草案和小型脱敏记录。临时回归资源按原runner只清理本次归属；不做全局prune、停止未知服务或清理父任务材料。

## 剩余阻塞与解阻顺序

1. **RP配置／托管控制权 BLOCKED。**用户已选方案，但需确认可用的托管账号与项目名控制权，并明确授权独立测试站点创建/发布和新task3 C配置。DNS有解析不能消除此阻塞。之后才创建独立一次性C/V、套用获准debug配置、重建最终正向/负向候选及补受影响检查；当前没有已部署环境或新系统端到端统一runner，不能称仅差手机。
2. **USB／窗口以手机会话固定交付为准。**e0c1280下Windows默认阻断，后续获准USB方案若仍在并行未提交状态，本轮不采用。待其给出明确固定SHA/验证后重新确认task3设备窗口、认证释放、安装包及数据影响；不自行新建OS账户、读取/复制/生成共享key或尝试ADB。
3. **CA-A13及单机收口 NOT_RUN。**实际系统可发现创建/恢复、UV、取消/拒绝/自然到期、丢响应后原键核对、实际插件/进程、任务1/2的App流程/重启/IME/读屏仍须设备事实。原生60秒与C五分钟分别自然计时，不缩短期限；未知不盲重试、不伪造证明或SQL结果。
4. 第二实体Android NI-X01/NI-X02、iOS、生产/完整App验收未纳入本轮通过。若设备阶段修复产品，最后修改后重跑受影响mobile/R05/F4/server/权限/runtime/vet，不能使用这份旧输入报告替代。

下一入口为[RP方案](community-android-stage3-rp-proposal-20261015.md)、[工具README](../../tools/community-android-stage3/README.md)及[四阶段任务单](community-android-unified-acceptance-plan-20261014.md)。当前结论为“固定产品基线主机范围可复验，第三项独立准备完成；配置审批及设备仍待完成”。
