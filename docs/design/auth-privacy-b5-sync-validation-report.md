# B5 同步恢复与非iOS匿名基础最终记录

2026-10-16（Asia/Shanghai），分支`codex/auth-privacy-handoff`，产品基线`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。

**NI-X02已通过，固定24项累计24 PASS／0 FAIL／0 BLOCKED。** 在保留B6原回归及匹配产品源码的范围下，`nonIOSDevelopmentAcceptancePassed=true`。这是当前分支的非iOS匿名基础开发验收终点；iOS延期、生产批准及未开发的社区业务继续独立登记，不提升为完整项目或上线批准。

## 实际链路

原vivo S18（V2323A／Android15）创建的`HnuHole test 26ac0016`，经用户在真我RMX3366（Android14）登录同一Google账号后，同步到真机本地Google密码管理工具；两台实际工具详情均核对了相同合成标签。没有再次创建源端Passkey，没有扫码或蓝牙hybrid连接，没有导出／重放证明。NI-X01的官方OEM迁移PASS保持原APK和证据，未重跑或把新APK冒充迁移包。

| 阶段 | 实际产品与独立SQL |
| --- | --- |
| 目标原生断言及C恢复意图 | 真我本机选择测试Passkey并完成用户验证；nativeBegun1／nativeSucceeded1，实际产品C创建意图。1账号／1 Passkey／1旧有效会话／1活动恢复意图；应用未登录 |
| 完整确认与重设 | 实际产品先隐藏新恢复码，再完整重输并提交新密码。显示重设成功；应用无会话且未自动登录。SQL为1／0／0／0，全部旧Passkey与有效会话被移除 |
| 旧权限与新登录 | 同一实际App依次验证旧会话401、旧密码401、旧恢复码401，再从“前往登录”使用新密码显式登录；账号ID与原合成账号一致，实际凭据列表无旧Passkey。SQL为1／0／1／0 |

旧Passkey失效依据是重设事务后的独立SQL零凭据及实际新会话凭据列表为空，未另发一次旧Passkey原生断言，也不把列表为空表述成“旧断言实测401”。其他22项和NI-X01保持各自原版本，B6的原共享回归没有在这轮重跑；本轮核对其实际已测产品输入摘要仍匹配，新增代码只在夹具与宿主工具。

## 失败与修复保留

原4次跨设备请求超时、Bitwarden在真我ROM缺少第三方CredentialManager支持的BLOCKED均原样保留。第5次目标请求已经原生成功并创建真实C意图，但夹具在生成新测试密码时错误调用`AuthCrypto.randomEncoded(24)`，被现有16／32字节守卫拒绝；该成功证明与未提交意图单独存证，没有把整个场景升格为PASS。

新夹具`auth_android_b5_sync_test.dart`唯一内容变化是把该调用改为32字节，未放宽产品守卫。分析、ARM64构建和批准签名核验实际PASS，只更新真我隔离包。第6次请求期间用户未点选／验证，GMS记录流程超时，App收到other-DOM错误；保留该FAIL。用户明确要求再来一次后，第7次新挑战实际完成完整链路，才接受NI-X02。新意图由真实C按现有事务规则取代旧活动意图，没有直接修改SQL或复用旧证明。

原[23／24记录](auth-privacy-b5-validation-report.md)、[B5原机器记录](../../services/api/authlab/android-b5-20261016-verification.json)、[Bitwarden预检](../../services/api/authlab/android-b5-bitwarden-20261016-verification.json)与[B6历史回归](auth-privacy-b6-validation-report.md)保留原状态。当前[最终机器记录](../../services/api/authlab/android-b5-sync-20261016-verification.json)逐项派生24项，分列设备、实际APK／fixture、各阶段PID／SQL和失败历史。

## 交接与保留范围

真我本轮临时Google自动填充设置已恢复为原密码本，credential／primary原值核验一致。vivo当前首选Bitwarden，较更早vivo-only备份已有变化；本轮同步未写源机provider，故保留当前设置，没有用旧备份覆盖。用户新登录的Google账号、Bitwarden登录、个人凭据及主HnuHole数据未删除。

两台隔离测试包、私有合成账号材料、测试环境与现成SDK／缓存保留便于复用；新密码和恢复码只保存在目标UID的no_backup及ACL保护的宿主私有目录，不进入Git。未恢复较早APK，也不声称完成临时材料清理。搬家时由用户调整且未采集原值的网络助理／后台高耗电设置需本人恢复。

入口：`tools/control-android-b5-sync.py`是有界单次操作器，不自动重试；`python tools/check-android-b5-sync-evidence.py`只核对交接、固定24项与实际输入摘要，不运行新的设备认证。相关模块A07／N03／N01／A12均追加限定范围记录，未覆盖原整模块状态。本轮尚未提交／推送／部署。
