# Telegram Android 私信展示层改造

2026-10-21，DM-TELEGRAM-01，B08/B09。分支 `feat/telegram-direct-messages`；实现未合并，生产私信未接线。任务分析与接口缺口见[分支记录](../branches/feat-telegram-direct-messages.md)。

## 截图与还原范围

用户补充四张聊天截图和一张指定的列表参考，原图均为 1080×2400。原图只作本地参考，不作为产品资源、壁纸或整页贴图提交。聊天素材包含个人对话空态、键盘、溢出菜单及另一会话的气泡；列表参考提供浅灰底、分组与搜索比例。用户随后要求沿用发帖页的固定底栏，最后指定消息用铃铛、私信用单气泡；未选中线框、选中蓝色实心。保留 HnuHole 的消息字段、身份边界与现有语义色，不引入联系人、通话、在线或语音业务。

按宽度折算到 402dp 的近似布局（截图未提供系统密度，不能据此确定实际 dp/sp）：

| 部分 | 本轮实现 |
| --- | --- |
| 聊天顶栏 | 52dp 独立圆形返回和更多按钮，约 6dp 间隔；头像与名称位于中间胶囊，44dp 头像、18sp 名称、13sp 次文字 |
| 聊天输入 | 单一圆角表面，17sp 原生多行输入、附件和 48dp 发送目标；发送身份仍可见，空输入不替换为语音 |
| 菜单 | 20dp 圆角、约 210dp 宽，图标与文字纵向列表；只提供已有来源帖入口和本地复制昵称，不放入未接通的静音/清历史/删除会话按钮 |
| 列表 | 浅灰底、14dp 外边距、24dp 白色分组、胶囊搜索；50dp 头像、17sp 名称、14sp 摘要及右侧时间/未读 |
| 底部导航 | 复用发帖页固定 64dp 栏与安全区，四入口依次为首页、消息、私信、我的；铃铛与单气泡采用代码矢量，未选中线框、选中蓝色实心 |
| 空态 | 居中圆角服务卡、简短说明及 Flutter 图标；不复制原图卡通贴纸。键盘显示后随剩余视口布局 |
| 配色与字体 | 复用主线 HhTelegramPalette、Roboto 与 HhNotoSansSC 及原许可；使用主题色组成轻微渐变，没有增加另一套字体或 Telegram 壁纸资产 |

上述为独立 Flutter 布局，系统键盘与系统栏由 Android 绘制。动态效果采用 Flutter 按压/菜单/短滚动过渡，并服从减少动态效果设置；没有以静态图证明帧率。

## 结构与业务边界

迁入旧设计工作区的四个聊天展示组件并整合主线主题，新增 `direct_message_chrome.dart`、`direct_message_timeline.dart` 和 `direct_message_inbox.dart`。按用户后续要求抽出共享 `HhAppNavigation`，生产 `main.dart` 分离消息/私信入口，并在通知、私信、个人页复用同一底栏。消息仍进入既有 `SystemNotificationsScreen`；私信后端缺失，因此正式入口仅显示“私信暂未开放”，不连接内存预览。未修改 API、数据库、Gate 或账号生命周期。

- 列表只显示当前收件身份，角标由上层投影提供；打开列表、搜索和切换身份均不自行清未读。点会话仅发出 scope/identity/conversation 三元目标，隐藏搜索结果的恢复与已查看批次仍须由未来业务适配器处理。
- 名称、备注、来源标题和本地正文匹配限定于当前身份已提供的数据；不查询陌生用户或云端聊天历史。列表惰性构建；向下浏览时暂缓新排序，固定提示按钮由用户主动应用。
- `onSend` 约定仍为本地持久队列接受，不能解释为服务端成功。发送中/未知不可重发；明确失败在确认后回调原目标，取消保留失败。页面/身份变化使旧回调失效，普通投影更新保留当前草稿及中文 composing 范围。
- `DmHistoryRequest` 只连接未来本地消息仓库，包含 scope 和 before 游标；分页具有可用/加载中/失败/完成投影。反向列表保留前插历史的位置，新消息到达时保护可见消息锚点，不把正在阅读历史的用户拖到底部；日期及未读分隔来自投影。
- 本轮没有本地消息表、持久队列、真实未读同步、待投拉取/落地 ACK、结果核对、私信媒体上传、双用户收发或重启恢复实现。旧样板有图片与撤回/举报回调，不等于这些业务已接通。不能借用帖子、评论或系统通知端点实现私信。

## 运行与验证入口

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub test --concurrency=2 --reporter expanded
flutter build apk --debug --no-pub --build-name=0.1.0-dm-nav --build-number=2026102155
$env:HNUHOLE_DM_PREVIEW='1'
flutter build apk --debug --no-pub -t tool/direct_message_preview.dart --build-name=0.1.0-dm-preview --build-number=2026102156
```

独立开发入口 `tool/direct_message_preview.dart` 使用内存夹具，并持续显示“开发预览 · 不连接私信服务”。调试属性只将该 APK 包名设为 `.dmpreview`，不覆盖日常测试包，不读取真实账号。预览内发送保持未知、重试保持未知，不生成成功回执；历史和未读为明确虚构的样例。

新增产品 CI `direct-messages.yml` 执行分析、私信边界测试、生产 bundle 及独立 Android 预览构建。宿主测试覆盖草稿/组合输入、身份与迟到回调、确认重试、单图目标、历史前插/新消息锚点、分页失败与跨会话完成、未读隔离、隐藏搜索和 360dp/200% 文字。实际结果、APK 摘要和设备证据见[机器记录](telegram-direct-messages-verification-20261021.json)；本地 PASS 不代证远端 CI 或真实私信业务。

## 当前验证

最终完整 Flutter **702 项 PASS**（并发 2），分析 0 问题，**36 项聚焦检查含真实字体宿主渲染 PASS**。生产入口 Android APK 2026102155 与独立预览 APK **2026102156** 构建 PASS。新增实际根路由测试循环切换四个入口，确认系统通知仍走原端点、不清未读或发送私信，回首页保留原 feed/channel。

真我 **RMX3366 / Android 14 / 1080×2400** 已安装独立包 `org.hnuhole.hnuhole_mobile.dmpreview` 2026102156，展示范围 UI/IME **PASS**。检查了四导航及蓝色实心态、浅/深色列表、失败取消保留原状态、确认重试后单条原消息转为等待核对、加载更早本地样例及返回最新、首次切换发送身份不自动发送、多行输入与键盘避让。2153 同源聊天实现另验中文拼音组合/提交“你好”、菜单与键盘共存、返回保留草稿，以及发送后未知状态。精确滚动锚点及迟到回调边界由宿主测试证明，未声称真机像素测量或真实网络发送通过。

早期 2151 包名隔离失效被签名检查拒绝覆盖日常包；2152 锁屏安装 -99，以及可选渲染测试的失败均保留在机器记录。用户要求重试后解除安装阻塞，2153/2156 成功安装。日常测试包保持 **2026102142**，未清数据、未更改系统设置。设备使用结束仅停止本任务预览进程并释放占用。后端收发、真实未读同步、持久任务及重启恢复仍 **NOT_IMPLEMENTED/NOT_RUN**；iOS、多机型、TalkBack 实机与性能预算 NOT_RUN。[Draft PR #44](https://github.com/zewbby/HnuHole/pull/44) 已提交，远端 CI 已触发待结果，独立成员 review 待完成，保持 Draft、未合并/发布。

Android 真机证据（预览夹具，不代表业务联调）：

- [浅色列表与四导航](telegram-direct-messages/assets/android-inbox-2156.png)、[消息铃铛选中](telegram-direct-messages/assets/android-notifications-2156.png)、[深色列表](telegram-direct-messages/assets/android-inbox-dark-2156.png)
- [多行键盘](telegram-direct-messages/assets/android-keyboard-2156.png)、[更早历史样例](telegram-direct-messages/assets/android-history-2156.png)、[失败确认](telegram-direct-messages/assets/android-retry-2156.png)
- [菜单与中文输入法，2153](telegram-direct-messages/assets/android-menu-ime-2153.png)

Flutter 宿主渲染（非 Android 真机截图）：[会话列表](telegram-direct-messages/assets/telegram-inbox-light.png)、[浅色聊天](telegram-direct-messages/assets/telegram-dm-light-v2.png)、[深色聊天](telegram-direct-messages/assets/telegram-dm-dark-v2.png)、[首次联系](telegram-direct-messages/assets/telegram-dm-empty-v2.png)、[失败确认](telegram-direct-messages/assets/telegram-dm-failed-v2.png)。
