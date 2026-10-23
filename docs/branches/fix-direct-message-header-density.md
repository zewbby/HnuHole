# DM-HEADER-DENSITY-01 私信列表紧凑布局

更新时间：2026-10-23。分支 `fix/direct-message-header-density`，基线 main `eb1eeb93f55a643718f0bff48aa0386a9db62c5e`（包含 #60）。源码提交`a5e7415309450d381fda457dd280138f82f26b05`已送审[Draft PR #62](https://github.com/zewbby/HnuHole/pull/62)。2314收起／展开视觉已获用户确认；r3补齐语义点击动作并通过独立Sol XHigh精确源码及文档复审，2315构建、同签覆盖与版本核对PASS，自动启动NOT_RUN。精确head CI与合并状态以PR回执为准，尚未合并或发布。

## 用户要求与实现

- “私信”标题从28改为22，字重由700改为600；标题行上下留白减至8dp。
- 按用户纠正保持原横向长度、14号昵称、28dp头像、20dp箭头与水平间距，仅把入口视觉高度从48dp减至36dp。外层保留至少48dp触控，右对齐、下拉锚点与唯一添加入口保留。首版缩短横向长度的方案作废，r2为已确认的视觉定稿。
- 搜索框最低高度40dp、14号字／20dp图标、灰底（现有secondary以10%混合background），圆角20dp；列表上间距减至12dp，不修改共享主题。
- 独立审查指出外层`Semantics(excludeSemantics:true)`会屏蔽子InkWell点击动作。r3只增加`Semantics.onTap: _selectIdentity`，沿用现有回调，未更改绘制／布局／触控尺寸或菜单锚点。
- 只修改`direct_message_inbox.dart`与既有导航测试夹具，不改业务接口、收发、身份权限、后端或底栏组件。最终修复与收尾按用户要求由Sol XHigh执行。

## 源码与定点验证

本机先加载`. E:/Hnuhole-env/env-windows.ps1`，将`PUB_HOSTED_URL`设为`https://pub.dev`。此前`flutter pub get --enforce-lockfile`成功，依赖锁未改。下列命令均在`apps/mobile`执行。

| 版本／检查 | 命令与结果 |
| --- | --- |
| r2受影响布局用例 | `flutter test --no-pub test/direct_message_navigation_test.dart --name 'compact dropdown mirrors content and places one add row after identities\|360dp inbox supports 200 percent text without dropping unread' --reporter expanded`：2 PASS，覆盖对齐、下拉／添加／键盘及360dp两倍文字。 |
| r2真实字体渲染 | 设置`HNUHOLE_DM_IDENTITY_RENDER_DIR`及现有MaterialIcons字体路径，执行`flutter test --no-pub test/direct_message_navigation_test.dart --plain-name 'render actual inbox identity selector collapsed and expanded' --reporter expanded`：1 PASS，390×844逻辑画布、2倍PNG，使用仓库Roboto／Noto Sans SC与真实HhAppNavigation，夹具身份。主会话已目视查看两图。 |
| r3语义动作回归 | `flutter test --no-pub test/direct_message_navigation_test.dart --name 'identity selector semantics tap opens identity menu' --reporter expanded`：1 PASS。先在未补回调源码复现tap action缺失，再直接经语义树执行tap，确认真实身份菜单打开；测试用try/finally释放SemanticsHandle。 |
| r3定点静态分析 | `dart analyze lib/src/messaging/direct_message_inbox.dart test/direct_message_navigation_test.dart`：0 issues。 |

本轮未重复已通过且未受影响的r2两项布局用例和渲染，也未重复完整私信文字／图片／恢复矩阵。r3应用源码移除唯一新增的语义回调行后，字节SHA256精确恢复为r2源码散列，因而沿用已确认的视觉证据；这不代证原生TalkBack。

最终r3工作树文件SHA256（提交时Git按仓库设置规范化换行；候选构建校验以下原始文件散列）：

- `apps/mobile/lib/src/messaging/direct_message_inbox.dart`：`89f5e91decf27f8c8ba3340092c0b689df8baa883404a61c2579fa8b0f0f7e76`。
- `apps/mobile/test/direct_message_navigation_test.dart`：`f7485ba2926ae984349af47af2f79776dd29932eeaf6124e2685c8ac4cd93ea3`。
- r2应用源码／r3移除唯一新增回调行：`bc8b9c73f7a38f8fa9c451aef749e8cf2fa1b3ffe48dd984c23898b213e4a7a1`。

本地证据根目录`E:/Hnuhole-env/deliveries/dm-header-density-20261023/`：r2的`preview-verification.json`与两张组件图；`r2-checks.log`、`r2-analyze.log`；r3的`preview-verification.json`及`r3-semantics-before.log`、`r3-semantics.log`、`r3-analyze.log`。顶层旧r1记录不代表最终版本。组件图不含真实用户私信，设备截图按私人证据保留，不提交仓库。

## Android与用户确认

2314使用正常`lib/main.dart`入口、主体包`org.hnuhole.hnuhole_mobile`及既有候选签名构建，在vivo V2323A同签保数据覆盖，安装版本核对`2026102314`通过。主会话确认收起状态和最终正确下拉菜单截图，用户回复“可以了，这个就可以了”，视觉验收限定PASS。

2314 APK SHA256：`b3e393a9204a9cc5b579a11ed693ce049d30e79a72b81e95c1a5bacd66767a40`；签名证书SHA256：`adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。脱敏本地回执`E:/Hnuhole-env/deliveries/HnuHole-dm-header-2026102314-device.json`，普通开发C/V环境，未部署后端、未发布生产。

2315绑定r3源码，主会话使用同一正常主入口及签名构建，同签保数据覆盖安装成功，设备版本号核对`2026102315`通过。APK为188039416字节，SHA256：`92603da3c0795c6c80fb81d256656fd105d43f402ae176b5f94df23cc31f4efc`；源码补丁SHA256：`e6acdff20956118eb2eb065f859503d8d442d0950c0880512ea0436d2de6a077`。本地回执`E:/Hnuhole-env/deliveries/HnuHole-dm-header-2026102315-device.json`。

版本核对后ADB服务不可用，`am start`未执行成功，故2315自动启动保持NOT_RUN，不记启动PASS，也未扩大设备排查。2314视觉确认仅按精确源码视觉等价复用。原生TalkBack操作仍NOT_RUN；新增宿主测试仅证明Flutter语义点击可打开菜单。

用户收到2315安装与自行打开App的说明后再次回复“可以了”，记录最终安装版本的用户可用／接受确认PASS。自动启动及原生TalkBack仍按上述NOT_RUN保留。

## 交付与剩余边界

独立Sol XHigh按上述最终源码散列复核产品diff与before FAIL／after PASS／分析0日志，并核对README、任务页、交接与台账，无新增阻断；该agent审查不等于GitHub成员批准。本地暂存协作检查、`git diff --cached --check`、变更Markdown本地链接及台账JSON解析PASS。精确head远端产品CI及协作检查待PR #62回执；通过必要检查及最终主会话快照后按已有授权合入main，禁止直接推main。当前未合并、未发布。README分支入口、HANDOFF、progress及模块交接／台账同步本页状态；最终CI和合并回执在PR及交付回执记录，不递归创建记录自身合并的文档PR。

旧真实突然掉电NOT_RUN、P3人工SKIP、远程推送未实现、iOS与生产未验保持原版本和范围；本轮UI定稿不提升完整B08/B09验收结论。原生TalkBack如需新增验收，须单列设备操作及证据。
