# FEED-SCROLL-SMILE-01：沉浸阅读、发帖入口与下拉刷新

- 更新时间：2026-10-23（Asia/Shanghai）。
- 分支：`codex/feat/feed-scroll-smile-refresh`，从最新 `origin/main` 的 `45e3948` 建立独立工作区。
- 状态：[PR #65](https://github.com/zewbby/HnuHole/pull/65) 已于2026-10-23按用户授权Squash合入main `df484b12a3b16783ea4588cbacf51a52476fdf0c`；精确head `fad2a5c` 的8组工作流15项检查全PASS。未安装或发布。
- 需求来源：用户两段录屏。第一段关注底栏隐藏与发帖按钮交接、下拉刷新；第二段追加向下阅读时顶部标题和推荐等工具也收起，反向浏览恢复。用户明确标志使用无空格的 `:)`，两个符号仅稍有距离，沿用原字体效果，并指定遇到问题由 GPT-6.1 Sol xhigh 排查。

## 实现与规则

1. 首页保留现有四个栏目，在中央加入发帖动作；中央与右下悬浮入口复用同一通道选择／新建帖子流程及提示。新增重复进入保护，快速触发只打开一次。发帖动作不新增栏目，不改变IndexedStack索引。
2. 只根据首页列表自身、深度0、垂直且带真实拖动信息的通知累计阅读方向。向下阅读36dp后收起上下导航，反向14dp恢复；小幅抖动、水平图片滑动、惯性和非顶部程序跳转不切换。停下来保持状态，回顶恢复；在列表中途就能反向显示导航。
3. 顶部标志／账号／搜索、推荐或通道选择、最新发布／筛选整体裁切收起，不留原有空白；底栏同步240ms收起，发帖入口转为右下60×56dp圆角按钮。展开时恢复52×48dp中央入口。隐藏区域不接受点击或辅助功能操作。
4. 共享 `FeedChromeController` 由 `PrimaryTabs` 持有，随现有授权窗口换新；独立FeedScreen使用本地回退。其他栏目保留原固定导航，往返保留首页数据／通道／位置，不复制底栏。
5. `RefreshIndicator.noSpinner` 保留Material的阈值、取消、anywhere抵顶后继续下拉与单次刷新控制。手动拉伸顶部最多112dp，松手320ms回弹，底栏固定；`:)` 最多放大至1.45倍并变浅，回弹后由1100ms循环弧段反馈等待。使用Roboto、22dp、700字重和原强调色，字距0.6dp，不插入空格；减少动态效果设置下不循环。
6. 继续调用现有PostController的同作用域刷新，保留旧帖子、媒体组件及失败后的分页游标，成功才替换第一页；空列表也能刷新。初次加载由标志反馈，移除重复的线性进度条；错误和重试沿用现有列表提示。未改变账号授权、接口、后端或媒体生命周期。
7. 根底栏仍由Scaffold管理实际占位，首页extendBody保证底部收起不反复改变根视口。只恢复真实系统padding，保留Scaffold已经消费的键盘inset；其他栏目不重复扣安全区，SnackBar避让底栏。Sol xhigh审查指出的安全区、提示条和IME问题均已修复并以几何断言保护，最终复核无剩余重要问题；此为只读agent审查，不是GitHub成员批准。

## 验证

完整命令、被测文件SHA-256、构建摘要与未验边界见[机器记录](../design/feed-scroll-smile-verification-20261023.json)。宿主验证最初在提交前完成；送审head `fad2a5c`、合并源码及其产品输入均与记录中的SHA-256一致。

| 检查 | 本轮结果 |
| --- | --- |
| `flutter pub get --offline --enforce-lockfile`，`PUB_HOSTED_URL=https://pub.dev` | PASS，未改变锁文件或新增依赖 |
| `flutter analyze --no-pub` | PASS，0 issues |
| 新增滚动／刷新10项＋既有导航2项 | PASS，12项 |
| `flutter test --no-pub test --concurrency 2 --reporter expanded` | PASS，844项／3 SKIP；跳过既有专用P2／P3 TLS与SQL、DM_HOST_FIXTURE联调 |
| Android Debug APK，目标Flutter engine arm64，2026102316 | PASS；apksigner、aapt2版本与arm64 engine／kernel存在性核对PASS |
| 真实打包字体的浅色／深色／大字号／纯享／下拉／加载渲染 | PASS，宿主布局检查，不代替设备视觉 |
| 最终head远端CI | PASS，8组工作流15项检查，无失败或跳过 |
| 手机视觉／原生TalkBack／设备帧性能／iOS | NOT_RUN |

新增测试覆盖真实正反向拖动、唯一发帖入口和安全位置、栏目与浏览位置保留、短拉取消和水平动作、空态刷新、防重复发帖、拉伸与小字距、保留旧行／分页／失败重试、单次刷新、提示条避让、安全区、授权窗口换新与旧完成隔离、300dp键盘只消费一次、退出后的迟到完成和实际字体渲染。

初次默认并发全量为839 PASS／3 SKIP／1 FAIL，旧 `post_composer_photos_test.dart:75` 的固定150×10ms图片导入等待超时；未改该文件或图片业务，单文件复跑通过。最终降低至两并发全量844 PASS／3 SKIP。初始失败日志保留，不改写为首次全通过。

已在 `.github/workflows/feed-ui.yml` 加入新增测试和渲染上传路径；现有该workflow继续执行分析、回归、bundle及真实feed夹具。精确送审head的远端结果已逐项核对并记入机器证据，与本机检查分别保留。

## 本机产物和下一入口

- 工作区：`E:/Hnuhole-env/source/HnuHole-feed-scroll-smile-refresh`。
- 日志：`E:/Hnuhole-env/post-button-review-20261023/`，最终分别为`analysis-final.log`、`all-tests-final.log`、`review-regressions.log`和`android-build-final.log`；不纳入Git。
- 页面PNG：`apps/mobile/build/feed-scroll-refresh-render/`；四状态合图为`E:/Hnuhole-env/post-button-review-20261023/implemented-preview.jpg`。
- APK：`E:/Hnuhole-env/deliveries/feed-scroll-smile-20261023/hnuhole-feed-scroll-smile-2026102316-debug.apk`，SHA-256为`2ad762e508cd8492f89ab87fafaedf64adac07d38c827c9dfee3b3b403c79e08`。这是本地Android Debug签名的构建验证制品，没有使用日常候选签名、开发连接配置或安装到手机。
- 下一步按用户明确授权准备匹配开发环境的设备候选，验证正反向滚动、上下栏过渡、下拉取消／触发／断网恢复、媒体播放与键盘／系统手势安全区；需要时采样设备帧表现。
- 本次仅更新B03／B06／B10相关界面增量交接，不升级既有模块、原生认证、真实SQL、iOS或生产结论。

## 合并回执

- 用户明确要求提交与合并；功能提交 `9220039`，随后 `fad2a5c` 整合main `c5475aa` 的头像交付记录。仅文档冲突，保留双方记录；所有已测产品／测试／CI输入摘要不变。
- [PR #65](https://github.com/zewbby/HnuHole/pull/65) 的Identity avatars、Post images、Android prerelease、Direct message chat、Auth feedback、Collaboration、Feed UI和Report moderation共8组工作流／15项检查全部success；逐项run／job链接在机器证据的remoteCI字段。
- Squash合并 `df484b12a3b16783ea4588cbacf51a52476fdf0c`，GitHub merged状态与远端main引用均已核对。主线输入再次逐项比对原被测SHA-256一致，没有以文档整合扩大设备验收。
- README最近变动、main详情、导航规则、HANDOFF、progress及台账通过本次单独文档回执同步；不为记录文档PR自身递归追加PR。功能／文档分支暂保留，未删除，APK与本机证据也保留。
