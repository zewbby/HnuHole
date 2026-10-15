# 单台 Android TalkBack 实测与修复

2026-10-15，Asia/Shanghai。结果：**PASS_APPROVED_TALKBACK_SCOPE**，属于任务2补充读屏范围；不升级完整模块或 App 为 PASS。

起点 `436ef294b6f51bc5da186737d0fcd931bcc0e8ef`，固定认证 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。最终运行源码为本提交内的源码，205项输入指纹 `62f9860ca60cf6c711f87a9af3a13b7ac5890729962c7293f88fdb6d1275dd4c`；提交后可用 Git HEAD 与该指纹共同定位，不将旧测试计入本轮。精确机器记录见[JSON](community-android-talkback-validation-20261015.json)。

## 实测问题及修复

- TB01：通道父语义与子 Text 合并导致名称重复。保留一个名称并显式保留语义点击回调，用户确认每个只读一次、双击可进入、深处通道可到达。
- TB02/TB03：我的入口和 SDK 自动返回原为英文。改中文 tooltip 和最小 Material Back 覆盖；不改布局、协议、依赖和锁。
- TB04：身份虽然画有勾号，实际语义 selected=false。先用回归复现失败，再设置 ListTile.selected，并保留原颜色。用户明确确认“已选中”。
- TB05：空白下一步实际显示行内必填校验，原无 liveRegion。用户报告无语音；回归先失败，再补 liveRegion。早先“按钮被空内容禁用”的口头判断错误，源码并非如此，已更正。
- TB06：用户在上一候选听到15和3000按英文朗读。为中文界面子树声明 zh_CN 语义语言，不改变数值限制；新增测试证明默认英文 locale 下中文节点也继承中文语言。

源码：`apps/mobile/lib/main.dart`、`lib/src/navigation/channel_tree.dart`、`entry_screen.dart`、`community_material_labels.dart`、`lib/src/posts/post_screens.dart`；回归：`test/talkback_semantics_test.dart` 和 `test/post_screens_test.dart`。三份 integration harness 仅同步“我的”选择器，没有取消检查。

## 手机证据及边界

vivo S18 / Android15，TalkBack17.0.1.926549743，由用户手动启用并听取。未用 UIAutomator 或自动化辅助服务干扰读屏，控制器未录音。最终人工反馈：

> 正常了

第一固定候选 `00d1beda77b92c61bed67f4d32dc55f0a1f8914bfe7d16674bfc3fb30f666c87` 上用户确认导航、草稿/输入框/身份面板、删除确认取消均正常；`ade09316…` 上明确确认“已选中”；`8e707cc2…` 上仍发现数字英文，保留为历史未通过；最终 APK `b924f853931ee1cbb70d645cb81e6dce87049d8abfae4d4f4f0afab97b7b2708` 的复验单独记录，不改写旧事实。

最终包 `org.hnuhole.hnuhole_mobile.communityf5`，证书 `b92a9ab262aad4e96365bf4f81a44ac9235a5f69cdc9c7ede380c4e5c0e0eb77`。各次均同包同证书原位更新，无卸载、清数据或换签名。首轮安装出现 INSTALL_FAILED_ABORTED，保留失败回执；仅用户明确“再弹一下安装”后执行第二次，不盲重试。原账号、草稿与本任务材料保留。结束时用户明确要求代为关闭 TalkBack；控制器仅移除本轮 TalkBack 启用项，无其他服务时关闭总开关，保留其他无障碍服务并只读核对结果。首个关闭脚本在写脱敏记录时因本地编码失败，尚未执行任何 settings 命令；保留失败记录后使用显式编码完成。

曾按下一次通道列表 GET 注入一次503：实际显示“请重新核对登录状态／登录或恢复”，截图确认，与现有 `sessionUnavailable` 安全边界一致。该试验**不能证明普通列表错误的“重新加载”朗读**；不为读屏放宽安全边界。故障前后合成SQL和写入计数完全一致，未发帖/删帖；原39375→39375转发恢复，新增临时代理正常退出，原服务/Gate/数据库未改。后续正常重开及草稿结果以最终人工反馈为准。

## 最终代码检查

| 检查 | 实际命令／结果 | 原始日志 |
|---|---|---|
| 分析 | `flutter analyze --no-pub`，0问题 | `analyze-chinese.log` |
| 全量mobile | `flutter test --no-pub --machine test`，333 PASS、0 FAIL、0 SKIP | `mobile-chinese-tests.jsonl` |
| 导航语义 | `flutter test --no-pub --machine test/talkback_semantics_test.dart`，4 PASS | `focused-chinese-tests.jsonl` |
| Android ARM64 | `flutter build apk --debug --no-pub --target-platform android-arm64 --target lib/main.dart --dart-define-from-file=<本任务原normal-defines私有路径>`，PASS | `build-chinese.log` |
| R05 | `AUTHLAB_MOBILE_TEST_PATTERN='^TestMobileClientHTTPSPostgres$' bash authlab/run-mobile-isolated.sh`，真实HTTPS/一次性PG PASS | `auth-regression-chinese.log` |
| F4 | `AUTHLAB_MOBILE_TEST_PATTERN='^TestF4MainAppHTTPSPostgres$' bash authlab/run-mobile-isolated.sh`，H01–H08 PASS | `integration-chinese.log` |

日志根：`E:/HnuHole-community-f4-20261012/talkback-validation-20261015`。可复验包装入口为该根的 `build-chinese.sh`、`verify-chinese.sh`、`host-regressions-chinese.sh`；所有运行均限定自有 SDK/cache/lock，`GOTOOLCHAIN=local`、`-mod=readonly`，无升级或删锁。APK唯一构建覆盖为已有隔离 applicationId；205项逐文件核对一致。R05/F4使用自有短TMPDIR、独立Unix socket、关闭PG TCP监听及新一次性库；fixture退出清理，不连接手机保留库或认证库。

F4原始summary的八个checkpoints均true；原runner的finalAuthenticationCandidate=null/finalF4Result=BLOCKED_DEPENDENCY为既存汇总字段，原值保留在本轮JSON，不把主机八点通过扩写为完整F4/App通过。固定认证来源另由本报告精确SHA记录。

最终运行源码修改后上述检查全部重跑。Go/SQL/权限/原生存储未改，本次没有重跑 server/posts-privileges/vet、35原生项或整机重启；这些保留此前固定版本的通过范围。长临时目录导致PG启动失败、语义测试handle回收失败和早期弃用API提示均保留历史日志，已分别修正自有路径、测试清理和当前API，没有降级断言或安全边界。

## 未验与复验

普通网络中断下列表重试的自动朗读、所有未访问认证页和完整 Material 中文翻译不计本次通过。复验应在批准设备窗口、同包同证书候选上，使用普通传输失败（不是503授权不可用）检查错误提示、重新加载及恢复，不改变会话保护。

任务3系统Passkey仍需确认独立RP控制权与关联/部署配置；任务4须第二台实体Android及两机窗口；iOS须Mac/Xcode与iOS设备。生产部署、Release发布和合并main均未执行。此前原生/重启证据保留原版本；详见[任务2报告](community-android-stage2-device-validation-20261015.md)与[四阶段任务单](community-android-unified-acceptance-plan-20261014.md)。本轮专用材料按用户要求保留，不执行全局清理。
