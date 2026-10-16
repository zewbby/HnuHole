# AC06 匿名基础最终交接报告

日期：2026-10-05（Asia/Shanghai）。分支 `codex/auth-privacy-handoff`，基线 `cbc99b010ba23bba42f76e2523269e3952b14392`。任务单见[AC06计划](auth-privacy-final-handoff-plan.md)，源码与交接文件摘要、实际静态检查结果见[最终机器记录](../../services/api/authlab/final-handoff-verification.json)。

## 交付结论

**本地源码与交接准备完成，完整验收待补。** AC01–AC03 实现及有范围回归、AC04新增场景、AC05本机Android证据均已整理；AC06只完成当前状态统一和材料核对，不重跑或改写此前动态结果。AC05整项和B02整模块仍BLOCKED，完整匿名验收未闭合，生产未批准。

AC01–AC03已发布记录见台账publicationDelivery；当前基线之上的AC04／AC05及本轮AC06修改尚未提交／推送。本地材料可审阅不表示另一台机器已经能从远端取得这些文件。发布时以实际包含本轮材料的提交为准，不能把基线SHA当作已包含未提交源码的被测版本。

## 实现、证据和源码入口

| 项目 | 实际范围及状态 | 源码／测试与证据入口 |
| --- | --- | --- |
| AC01 V独立Gate | 实现完成；独立冻结／恢复、时间／旧快照／代次、迁移与受限角色的开发验收PASS | [VerifierStore](../../services/api/internal/authprivacy/verifier.go)、[V迁移4](../../services/api/verifier-migrations/0004_authorization_gate.sql)、[Gate测试](../../services/api/internal/authprivacy/verifier_gate_test.go)／[业务测试](../../services/api/internal/authprivacy/verifier_gate_business_test.go)；[AC01报告](auth-verifier-safety-gate-validation-report.md) |
| AC02 整账号关闭与身份联动 | 实现完成；正式关闭擦除活动资料、保留永久事实、独立占位契约及同邮箱新账号隔离PASS；内容／聊天消费者未集成 | [关闭事务](../../services/api/internal/authprivacy/community_closure.go)、[迁移12](../../services/api/migrations/0012_identity_account_closure.sql)、[关闭测试](../../services/api/internal/authprivacy/community_identity_closure_test.go)；[AC02报告](auth-identity-account-closure-validation-report.md) |
| AC03 隐私边界 | 当前字段／角色／HTTP／持久状态／诊断范围核对及差异修复PASS；未来业务契约固定 | [HTTP负向测试](../../services/api/internal/authprivacyhttp/privacy_boundary_test.go)、[数据库负向测试](../../services/api/internal/authprivacy/privacy_boundary_postgres_test.go)、[运行诊断](../../services/api/internal/authprivacyruntime/diagnostics.go)；[AC03报告](auth-privacy-boundary-validation-report.md)／[业务契约](auth-privacy-business-contract.md) |
| AC04 新增场景与受影响链路 | 测试源码补齐；Go／一次性SQL／race／vet、R03实际C/V、Flutter179项与R05真实Dart→handler→SQL PASS | [V客户端场景](../../apps/mobile/integration/verifier_gate_https_scenarios.dart)、[关闭SQL断言](../../services/api/internal/authprivacyhttp/mobile_closure_postgres_test.go)、[R03 runner](../../services/api/authlab/run-runtime-isolated.sh)；[AC04报告](auth-privacy-regression-validation-report.md) |
| AC05 当前平台 | 完整Android构建、native16＋3组、Passkey Dart9／codec5、原生Flutter身份／登出双进程PASS；整项BLOCKED | [身份设备场景](../../apps/mobile/integration_test/identity_device_scenarios.dart)、[双进程入口](../../apps/mobile/integration_test/auth_security_device_test.dart)、[设备runner](../../tools/run-android-auth-process-test.ps1)；[AC05报告](auth-privacy-platform-acceptance-validation-report.md) |
| AC06 当前交接 | 当前台账、历史／现行入口、摘要与文件一致性核对；结果以最终机器记录为准 | [模块台账](module-acceptance-ledger.json)、[最终检查器](../../tools/check-privacy-closure-handoff.py)、本报告与任务单 |

当前实现摘要沿用AC05的284个源码／资源文件，原字节与Git文本LF等价摘要分别保留。AC06未改变此集合中的实现或已有测试／runner；新增最终检查器和交接文件有单独摘要清单，台账本身单独计算摘要，避免自引用。AC01–AC05机器记录原文件摘要保留，不能改写旧测试日期、哈希或证明范围。

## 仍未验、未实现和外部依赖

| 项目／模块 | 状态与缺口 | 所需条件及下一入口 |
| --- | --- | --- |
| N02／R06／R09 | BLOCKED：iOS完整构建、链接、Keychain、跨进程及AuthenticationServices未验 | macOS／完整Xcode、Team／Bundle／签名和目标设备；[RunnerTests](../../apps/mobile/ios/RunnerTests/RunnerTests.swift)与模块R06／R09 |
| N03／A09／B01系统Passkey | BLOCKED：只有codec／适配器证据，系统绑定／移除／恢复闭环未验 | 实际RP、批准的Android签名／origin与assetlinks、Apple关联域及AASA部署；[包说明](../../packages/auth_passkey/README.md)与[关联生成器](../../tools/configure-passkey-associations.py)。只发现示例／测试配置，外部部署未独立盘点；不能用占位RP完成验收 |
| N01／N02／B02设备矩阵 | NOT_RUN：物理设备、真实OEM中文／日文IME、TalkBack等辅助服务、系统备份／跨设备恢复／卸载重装 | 专用可确认归属设备、系统备份材料；模块R09／R10。模拟器Keystore及合成composing／2倍字／semantics不代证这些场景 |
| A13／A12完整App→实际C/V | NOT_RUN：三类证据边界尚未整合 | 实际受信TLS／端点、RP关联与设备；R03＋R05＋R09需补整链入口。当前无一条命令已经完成此整链，不能虚构现成一键PASS |
| B02完整业务联动、B03／B05–B12 | 未实现或部分实现，整模块NOT_RUN／BLOCKED | 帖内绑定、公共内容／评论投影、身份对私信、本地聊天／备注／搜索关闭清理、管理消费者按后续明确任务开发，再验X06／X07；仅纯投影／CRUD或契约不代表已集成 |
| P02–P06 | NOT_RUN：分权／授时／库外锚点、日志与备份留存、灾备／侧信道、发布集成、人类独立审计缺证 | 实际运营与外部服务证据、固定最终实现版本及独立评审者；[评审输入包](auth-privacy-security-review-package.md)与匿名清单 |

## 另一台机器的执行顺序

1. 发布后再拉取指定分支；先确认仓库根、分支、HEAD及工作区，保留已有改动。阅读[机器入口](auth-privacy-machine-handoff.md)、本报告和[本机环境](local-test-environment.md)。本机历史路径是环境示例，不保证新机器存在。
2. 先做无需大型缓存的记录核对：`python -B tools/check-identity-handoff.py`、`python -B tools/check-privacy-closure-handoff.py`、`git diff --check`。摘要不同即重新确定被测版本，不把历史PASS迁移到新代码。这些命令不执行动态验收。
3. 只针对具备环境的缺口或实际改动重验。服务端与Gate文件放WSL2 Linux文件系统；R01／R02使用`sh services/api/authlab/run-isolated.sh`，R03使用`sh services/api/authlab/run-runtime-isolated.sh`，R05在设置现成`AUTHLAB_MOBILE_FLUTTER`后使用`sh services/api/authlab/run-mobile-isolated.sh`。runner建立一次性库／项目，不传未知或真实DSN；没有`--module`筛选参数。R03需要固定Goose3.22.1与已有Docker镜像，R05需要Flutter和PG工具。
4. Android构建／设备命令沿用[环境文档](local-test-environment.md)，双APK使用相同namespace／签名、中途不卸载或清数据；专用pub缓存可通过`-PubCache`传入。iOS与真实Passkey先补上表环境，不能靠重复codec测试补证。上一轮缓存／APK已清理；需要重新取得依赖时遵守AGENTS和新的当次授权，AC05下载授权只适用其当轮。
5. 记录每个模块／X场景的结果、源码版本及证据，保留旧记录；失败修复后再做受影响回归。清理自己创建的临时库、进程、密钥、缓存和APK，保留现成工具／AVD，不做全局prune。

## 本轮检查与清理

AC06只执行源码／证据／JSON／文档链接及补丁检查；Go、SQL、Flutter、原生设备和独立安全评审均未在本任务重跑。既有AC04／AC05通过记录及清理结论保留原范围；本轮核对专用临时目录不存在。没有创建服务、数据库、密钥、APK或大型依赖缓存。生产与未来业务模块状态不改变。

正式人类评审应固定包含最终材料的提交SHA和本轮摘要，明确实际评审范围。2026-09-28的规格快照及AI交叉评审是历史输入，不是对当前实现的独立签署。
