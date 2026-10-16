# B6与单台Android范围最终验证报告

日期：2026-10-13（Asia/Shanghai）。仓库`zewbby/HnuHole`，分支`codex/auth-privacy-handoff`，Git基线`976c0048aaa40d9b7f589cb735f3bf9c47571486`。按用户“做完不需要第二台手机的其他所有事情”完成当前非iOS匿名基础范围。

**B6 PASS；单台Android可完成的范围已结束。固定24项为22 PASS／0 FAIL／2 BLOCKED，唯一固定缺口是NI-X01、NI-X02。**`b6WithoutSecondAndroidPassed=true`，`nonIOSDevelopmentAcceptancePassed=false`。第二实体手机缺口未被模拟器、代码完成或人工确认替代。

## 最终候选实际检查

| 检查 | 实际结果与范围 |
| --- | --- |
| R01 | 完整隔离SQL／Go race／vet，退出0；一次性C/V数据库，无真实用户库 |
| R03 | 实际cmd/api与cmd/verifier、正式迁移和受限角色、HTTPS/mTLS、Gate／重启／升级／关闭／日志共19项，退出0 |
| R05 | 真实Dart→HTTPS handler→SQL，退出0；覆盖注册、接替、撤销、重设、关闭和Gate故障，使用测试内存vault |
| Flutter | mobile／auth_passkey／auth_vault分析均退出0；mobile完整188项、Passkey Dart 9项退出0。vault没有独立Dart测试目录，不记成测试PASS，原生检查单列 |
| 标准Android | 未改产品源码／pubspec的main target：Debug ARM64、Release ARM64及专用模拟器Debug x64构建；标准Release未配置生产签名 |
| 原生Android | 实际Keystore／AtomicFile 16项，Passkey codec／错误分类12项；三个写读进程对PID不同，包含替换前和同步后主动进程中断；不宣称断电或真实Passkey ceremony |
| Release | 专用已安装Release探针13项均真；开发CA／RP被拒绝，原生driver／验收入口不可用，run-as被拒绝；两份实际Release APK的manifest／DEX无debug诊断Activity／policy，标准包无debug关联。原专用Debug APK恢复后关闭模拟器 |
| 工具／契约 | Windows与Linux各108项宿主守卫，诊断构建8项，JVM策略24项，四份完整OpenAPI；退出0。检查器防止缺设备、缺回归、错误摘要、取消或模拟器被升格为完整验收 |
| 候选与清理 | 源码／APK／runner摘要与24项、原14阶段均映射；私钥、真实DSN、原始证明和大日志未进入Git候选；本轮专用构建副本／AVD／APK／原始日志已清理，既有SDK／缓存／fresh环境保留 |

## 24项与模块映射

历史通过保持自己的APK、fixture／runner、设备PID与实际SQL证明，B6没有把它们改写为新APK的设备运行。当前候选相对Git基线的产品代码变化仅为debug诊断Activity；正常客户端／服务端／原生vault与Passkey共享实现未修改。本轮最终共享回归独立登记。

| 固定ID | 结果 | 模块 | 接受边界 |
| --- | --- | --- | --- |
| NI-L01 | PASS | N03/A12/B01 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-L02 | PASS | N01/N03/A12 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-L03 | PASS | N03/A12/B01 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-L04 | PASS | N03/A12/B01 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-U01 | PASS | N03/A07/B01 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-U02 | PASS | A12/B02 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-U03 | PASS | A12/B01/B02 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-A01 | PASS | A03/A09/N03 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-A02 | PASS | A03/A07/N03 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-A03 | PASS | A06/A09/A12/N03 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-A04 | PASS | A03/A06/A09/A12 | B1_B2_ACTUAL_APP_DEVICE_SQL |
| NI-C01 | PASS | A07/A08/A09/B02/N03 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-C02 | PASS | A08/A09/A12 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-C03 | PASS | A08/A12/B02 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-C04 | PASS | A04/A05/A08/A12/B02 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-D01 | PASS | A09/N03 | DIRECT_PROVIDER_AND_ACTUAL_PRODUCT_SQL |
| NI-D02 | PASS | A09/N03 | DIRECT_PROVIDER_AND_ACTUAL_PRODUCT_SQL |
| NI-D03 | PASS | N03 | DIRECT_PROVIDER_AND_ACTUAL_PRODUCT_SQL |
| NI-D04 | PASS | A02/A12/N03 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-D05 | PASS | A07/A09/B01/N03 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-K01 | PASS | N01/A12 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-K02 | PASS | N01/A12/B02 | B3_B4_ACTUAL_APP_DEVICE_SQL |
| NI-X01 | BLOCKED | N01/A12 | 缺第二实体Android |
| NI-X02 | BLOCKED | A07/N03 | 缺第二实体Android |

原十四阶段在[原矩阵](../../services/api/authlab/android-matrix-verification.json)的`batchVerification`保留；本轮[机器记录](../../services/api/authlab/b6-single-android-20261013-verification.json)逐项引用原节点、APK、module及摘要。B02整模块仍为业务联动待开发，不由基础回归升格为完整模块PASS。

## 分层失败与修复记录

NI-D01／D02／D03的实际SDK-only App结果仍为FAIL，vivo回调为通用取消、关联计数0。固定边界接受依赖Google实际50152及validator栈、实际APK／产品和独立SQL；原SDK失败、早期两次产品失败及PID14444的UNKNOWN均保留，不算已经解除。

本轮基础设施失败也保留原回执：初始源副本漏静态协议报告；SDK镜像缺扫描目录及一次错误WSL用户；编排器误跑没有Dart测试的vault目录；Release的`--no-pub`未更新插件注册表；跨文件系统复制mtime失败；离线原生JUnit依赖缺失；Windows POSIX权限断言及已改hosted-URL的镜像工具夹具失败。分别补齐真实输入、正确启动／命令／平台断言与必要依赖。没有修改协议向量、产品鉴权、失败结果、SQL期限或真实证明。移动端完整测试已经实际通过，只接受确实退出0的测试命令；不把空测试目录的退出1改成PASS。

最终交接检查核对了历史发布commit的原始`index.html`／`robots.txt`字节：发布版本为CRLF、本地为LF，只接受这两个辅助文本的换行转换，关联JSON仍要求精确字节。新摘要守卫的Windows夹具初次因隐式CRLF失败，改为显式LF字节后，Windows／Linux各108项实际通过；初次FAIL回执保留。最终工具同时登记原始摘要和Git LF摘要，源码内容变化仍会被拒绝。

## 接续与交付

只剩第二实体Android的NI-X01 OEM搬家和NI-X02真实跨设备Passkey恢复。原vivo三包和provider／autofill保持，旧8项归档密钥缺失不阻止已保留证明的范围复用；当前fresh测试环境未reset／rekey。后续按[固定计划](auth-privacy-non-ios-closure-plan.md)与[机器入口](auth-privacy-machine-handoff.md)执行这两个ID。

iOS本轮SKIP；生产分权、灾备、独立审计／签名关联／正式发布及帖子评论聊天等未来消费者独立，均未获本轮通过。HnuHole未提交、推送或部署。本地Git候选保留源码、测试及小型脱敏记录，原已有README改动保留且排除本轮候选。交接检查器只核对记录，不执行动态验收。

本地候选补丁位于`E:/Hnuhole-env/b6-20261013/auth-single-android-candidate.patch`，配套小型manifest保存Git基线、35个候选路径、补丁SHA与应用检查结果。使用专用临时Git索引生成，原仓库暂存区保持原样；候选可以按原HEAD核对和审阅。
