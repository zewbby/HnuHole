# TalkBack 普通网络错误与重试补验

2026-10-15，Asia/Shanghai。**PASS_TALKBACK_NETWORK_RETRY_SCOPED**；补齐此前明确遗漏的普通网络错误读屏项目，不代表完整 App／平台验收通过。原[读屏报告](community-android-talkback-validation-20261015.md)及其333项证据保留原版本，新增问题与最终结果见[本轮JSON](community-android-talkback-network-retry-20261015.json)。

起点 `eee3fa8089af3832bc6685c373d7656e14433c4e`；固定认证 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。最终源码为本提交内的两处修改，205项移动端/插件输入指纹 `5bc83b4d98a46a7db8ea0139fb76073bbc87e17efaa59aac0c324c8f5e677631`。Go/SQL/权限/原生插件和锁未改。

## 真实复现与修复

此前503测试进入会话恢复保护，不能代证普通网络错误；结束前没有补验是执行收尾遗漏，不是设备或工具阻塞。本次获准新的5–10分钟vivo S18窗口、临时启用及结束代关TalkBack。沿用既有批准USB身份和隔离App，不安装新工具或操作认证环境。

第一轮仅对一次通道帖子列表GET关闭连接，不返回HTTP503、不碰写请求。用户确认错误页出现，提示及“重新加载”能逐项朗读，但“进去通道没有自动朗读错误”。记录原答：

> 1. 出现
> 2. 正确
> 3. 进去通道没有自动朗读错误

新增回归先复现 liveRegion=false；首个外围包装方案仍没有落到实际文字语义节点，自动测试继续失败，保留日志并调整位置，没有降低断言。最终只给帖子列表首次加载失败的标题添加 liveRegion；`_PageState` 默认关闭该属性，不为其他使用_PageState的页面新增主动播报。重试动作、会话保护和HTTP处理逻辑不改。

源码 `apps/mobile/lib/src/posts/post_screens.dart`；新增 `apps/mobile/test/post_screens_test.dart` 的“列表读取失败向读屏通知错误并保留重新加载操作”，检查真实语义节点、语义点击执行、原账号保持和零发布。

## 最终手机复验

最终APK `f9a2ea7ed783fc5051743ee220ed3087a204d42aed0ae35b94c81fa09c987a13`，包 `org.hnuhole.hnuhole_mobile.communityf5`，证书 `b92a9ab262aad4e96365bf4f81a44ac9235a5f69cdc9c7ede380c4e5c0e0eb77`；同包同证书原位更新，账号/原草稿保留，无卸载、清数据、改签名。205项镜像输入逐文件核对，唯一覆盖仍为已有隔离 applicationId。

修复后再执行一次同类只读连接中断；每轮仅命中一个列表GET、转发写请求为0。用户对“不滑动自动读出暂时无法加载帖子／逐项提示与重新加载仍可读”答“正常”。随后恢复原39375→39375转发并退出临时代理，用户对“点重新加载恢复正常列表或空态、错误消失、无需重新登录、原草稿仍在”答“是的，一切正常”。至此本轮普通网络错误与重试清单通过。

按既有授权立即代关TalkBack，逐项核对恢复原无障碍服务列表和总开关；App数据未清除。原C/V/代理健康检查均200；两轮及最终重试后的合成业务SQL与写入计数完全一致。没有Gate recover、数据库reset、停止原服务或修改全局ADB/网络配置。语音与手势来自用户实听，控制器未录音，未用UIAutomator干扰读屏。

## 最终源码检查与复验入口

| 项目 | 命令与结果 | 日志 |
|---|---|---|
| 静态分析 | `flutter analyze --no-pub`，0问题 | `analyze-retry2.log` |
| 全量mobile | `flutter test --no-pub --machine test`，334 PASS／0 FAIL／0 SKIP | `mobile-retry2-tests.jsonl` |
| 导航语义 | `flutter test --no-pub --machine test/talkback_semantics_test.dart`，4 PASS | `focused-retry2-tests.jsonl` |
| 新错误语义 | 按plain-name执行新post_screens回归，1 PASS；包含在最终334内 | `transport-announcement-after-fix.jsonl` |
| ARM64 Debug | `flutter build apk --debug --no-pub --target-platform android-arm64 --target lib/main.dart --dart-define-from-file=<本任务既有normal-defines私有路径>`，PASS | `build-retry2.log` |
| R05 | `AUTHLAB_MOBILE_TEST_PATTERN='^TestMobileClientHTTPSPostgres$' bash authlab/run-mobile-isolated.sh`，真实HTTPS/一次性PG PASS | `auth-regression-retry2.log` |
| F4 | `AUTHLAB_MOBILE_TEST_PATTERN='^TestF4MainAppHTTPSPostgres$' bash authlab/run-mobile-isolated.sh`，H01–H08 PASS | `integration-retry2.log` |

根目录：`E:/HnuHole-community-f4-20261012/talkback-validation-20261015`；包装入口 `build-retry2.sh`／`verify-retry2.sh`／`host-regressions-retry2.sh`，SDK/cache均为本任务自有且持有构建锁。R05/F4新一次性库使用本任务短临时目录、独立Unix socket及关闭PG TCP监听；不连接手机保留库或认证库，fixture退出清理。最终源码修改后全量mobile、分析、构建、R05/F4均重跑并覆盖最终源码。

原F4 runner的summary仍含历史finalAuthenticationCandidate=null/finalF4Result=BLOCKED_DEPENDENCY，原值随八项true保存在JSON；不将主机子范围解释为完整F4/App通过。此前333项、原生35项及重启结果不冒充本轮新执行。Go/SQL未改，本轮未重跑server/posts-privileges/vet和原生/整机重启。

第三项系统Passkey及RP配置确认、第四项双实体Android、iOS、生产和未访问流程仍独立未验。本次补验项已经收口；本任务环境和原账号草稿按用户要求保留。未发布Release、合并main或部署。
