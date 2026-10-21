# LOGIN-HOME-01：登录直达首页与运行期间保留通道

- 更新：2026-10-21，Asia/Shanghai。
- 分支：`feat/login-home-recommended`；基线 `ddf506a5dfd9874c0bf060a8ab40b3efa3728d31` 加本地未提交差异。
- 状态：实现、宿主回归、Android 测试 APK 和单台 vivo 真机指定场景 PASS；用户已授权提交、推送、PR 及通过规范检查后合并，当前进入交付流程，未正式发布。
- PR：[ #40 ](https://github.com/zewbby/HnuHole/pull/40)，用户已授权检查通过后 Squash Merge。合并状态、时间和最终 SHA 以该 PR 回执为准；本页保留送检事实，不将旧 APK 标为新构建。
- 送检：源码提交 `250af2a`，整合主线文档 `c1b7ebf`／主线 `874bc0b`，运行源码与 2122 被测输入一致。独立 agent `/root/independent_review` 已完成静态审查，无阻断；这不是 GitHub 成员批准。最终远端 head CI 由 PR 回执确认。
- 当前结果与旧阶段区分：[机器记录](../design/login-home-recommended-verification-20261021.json) 的 history 保留原 20／632 项和 Android 构建受阻状态；以下为澄清后最终版本。

## 用户最终确认的行为

删除登录后的通道／节点选择页面，直接进入首页。每次彻底启动程序默认“推荐”；启动后用户选择“吐槽”等通道，从详情、个人页、消息页返回和点击首页按钮均保留所选通道及当前阅读状态，不自动切回推荐。同次运行的同账号重新登录保留所选通道；各账号的选择不混用。选择只保存在本次进程内存，不跨彻底重启持久化。附图加载失败提示不是需求。

## 实现与自动检查

`apps/mobile/lib/main.dart` 将真实 `FeedScreen` 设为已授权首页根路由，删除旧节点树路由；登录成功退回根路由。按账号／授权代次重建受保护数据，通道选择按账号保留在当前 App 内存中。完整目录、服务端会话和权威截止持久化仍是进入首页的条件。

`apps/mobile/lib/src/navigation/entry_screen.dart` 仅保留未登录、加载与重试；`channel_tree.dart` 及其视角／绘图状态删除。`feed_screen.dart` 的首页按钮保留通道、数据和位置。页面内通道选择／发帖与屏蔽能力保留，不新增推荐算法。

当前 Flutter 3.47.5／Dart 3.13.4：

| 检查 | 实际命令／结果 |
| --- | --- |
| 分析 | `flutter analyze --no-pub`：PASS，0 问题 |
| 跳转／账号／无障碍 | `flutter test --no-pub test/login_home_navigation_test.dart test/personal_route_account_test.dart test/talkback_semantics_test.dart --reporter expanded`：PASS，23 项 |
| 移动端全量 | `flutter test --no-pub --reporter expanded`：PASS，635 项 |
| Android 原生 | 下述本地覆盖参数的 `:app:assembleDebug`：PASS，212 tasks，最终 42 秒 |
| 远端 CI | 送检中；既有 `.github/workflows/feed-ui.yml` 已纳入新增专项，最终结果见 PR #40 |

测试从 `apps/mobile/test/login_home_navigation_test.dart` 进入。旧认证／设备夹具将已删除的树类型落点更新为 FeedScreen，历史 F4／全矩阵未在本轮复跑，不据此提升完整模块状态。

## Android 构建修复与制品

定点补齐 Android SDK CMake 3.22.1；原 Kotlin 异常确认是 E: pub-cache 与 C: 工程的跨盘增量缓存路径冲突，本次命令使用 `-Pkotlin.incremental=false`。未修改共享 Gradle 配置。

实际命令（PowerShell 中各 `-P...` 参数完整引用，公共 defines 从本地文件读取）：

```text
gradlew.bat --offline --no-daemon --max-workers=2
  -I E:/Hnuhole-env/login-home-20261021/test-identity.init.gradle
  -Pkotlin.incremental=false -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart
  -Pdart-defines=<公共端点与开发 CA defines>
  -Pdart-obfuscation=false -Ptrack-widget-creation=true -Ptree-shake-icons=false
  :app:assembleDebug
```

最终 APK：`E:/Hnuhole-env/login-home-20261021/hnuhole-login-home-2026102122.apk`，98,781,028 字节；SHA256 `af71445abb10a8e8aa38bd25682be87e6392802f1b9fc316f295e043e71a8cf5`。
包名 `org.hnuhole.hnuhole_mobile.loginhome`、名称“HnuHole 登录跳转测试”、版本 `2026102122`。构建仅覆盖包名／名称／版本和 debug manifest，运行入口仍为真实 `lib/main.dart`，未嵌入账号密码或 token。签名已用 apksigner 验证，证书摘要见机器记录。

早期 2121 APK 在需求澄清前构建，只保留原阶段事实；交付以 2122 为准。

## 真机指定场景

vivo V2323A／Android 15，独立测试包已安装。通过真实页面使用分配的合成 reporter 账号登录现有隔离 C/V（共享服务源码 c923fa5）；未改数据库或 C/V 配置。

| 实际操作 | 2122 结果 |
| --- | --- |
| 启动／恢复会话 | 默认推荐；原生选择器中的推荐 selected=true：PASS |
| 推荐切换吐槽，进入真实帖子，再按返回 | 仍为吐槽，无节点页：PASS |
| 吐槽进入我的，再点首页 | 仍为吐槽：PASS |
| 吐槽点击底部首页 | 不重置选择：PASS |
| 吐槽进入系统消息，再返回 | 仍为吐槽：PASS |
| 同次运行从账号设置退出，再真实输入密码登录 | 直接到首页且仍为吐槽，无中间节点页：PASS |
| 根首页系统返回 | 离开 App 前台，不出现节点页：PASS |
| force-stop 测试包，再启动并恢复真实会话 | 默认推荐：PASS |
| 原包版本／安装更新时间前后对照 | 未覆盖原 App：PASS |

截图、UI 层级、APK 和命令证据保存在本任务目录 `E:/Hnuhole-env/login-home-20261021`；公开截图摘要在机器记录。密码页面的中间材料只私有保存；输入焦点与安全键盘收起需按真实状态等待，未改变安全键盘设置。启动加载的瞬时状态不当作已稳定成功或故障。

## 继续试用与边界

本测试包使用 App 内开发 CA，证书链与主机名校验开启，手机系统未安装 CA。需本机隔离服务及 USB 在线：phone55145→host51245；phone54947→本任务 localhost54948 透明中继→WSL V49747。当前保留映射和本任务中继以支持用户继续试用，说明见本地 `INSTALL.md`；共享服务未改配置。仅操作测试包，未卸载／清除原 App 数据。

模块沿用 A12、B03、B10，仅登记本次导航限定 PASS。iOS、生产、其他机型与完整历史模块矩阵不在本轮范围；未发布。

## 审查与主线同步

2026-10-21，独立审查覆盖 `ddf506a..250af2a` 与 `c1b7ebf` 整合后的运行输入，核对导航、按账号内存选择、授权代次/旧回调、CI、635项日志、分析0和2122制品摘要，未发现阻断。文档中“默认推荐”已明确仅指本次运行首次进入；最终提交只补交付文档，产品与测试输入不变。合并前检查所有适用远端 CI，使用预期 head SHA 的 Squash Merge；合并后核对远端 main 包含 PR 结果。未正式发布。

## PR39 主线运行代码整合（送检快照）

PR40 送检期间主线合入 `c23620f`（新版登录注册实现 #39），已保留其 AuthPresentation 生命周期、Scope、主题／语言和欢迎页，并重新接入首页根路由与内存通道选择。测试改用新界面的 `auth-start`、`login-submit` 稳定键。旧2122记录只证明原运行源；本次另建[整合验证记录](../design/login-home-main-integration-20261021.json)，分析0、全量643项与2124原生构建212任务PASS，独立复审无阻断。2124的实际入口冒烟与最终精确head CI结果在合并前核对并附PR回执；不把送检时待验快照当成最终未验结论，也不沿用旧包代证。主线源码合入不更改用户最终要求：启动推荐，运行期间往返保留通道。
