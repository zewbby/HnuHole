# 帖子详情 X 布局示例 · 2026-10-21

本轮为用户要求“先做一个示例图”的视觉提案，尚未批准或接入生产详情页，不改变 PR #37 的合并状态。之前将收藏单独置于标题右侧、点赞单独置于正文右下角的候选由用户最新两张 X 参考覆盖，按下列新结构评审。

- 参考：用户本轮 `1b9f929e5cdc4738904fa9a5c6a23d5c.jpg`、`bf3362b901fd9caa6a5e9ffbd5a40977.jpg`；借鉴单列内容、作者区、日期浏览量、横向互动栏、评论列表及固定底部回复入口。
- 适配：保留 HnuHole 标题、通道和公开面具昵称；无顶部 Logo、关注、私有账号标识、“相关”、引用或新增转发功能。评论区标题直接为“评论”。未添加 GIF。
- 本图为纯文字帖，使用虚构内容与数字；作者头像为项目既有文字头像形式。媒体详情、菜单展开及其他状态不在本张证明范围内。
- 字体：实际打包 Roboto 及 HhNotoSansSC；导航21、昵称17、标题19、正文17、元信息13.5、评论正文15.5逻辑像素。正文行高1.55、评论1.5。
- 色彩：复用 HhTelegramTheme 浅色主题，白表面、1D1D1D正文、757575次文字、168BDA强调、EAEAEA分隔线。图标复用现有 Feed 的路径，不用生成位图代替已有图标。
- 布局：402×874逻辑像素，3倍实际 Flutter 栅格渲染为1206×2622。主内容连续滚动，底部回复入口固定；正文及一级评论左边距16，回复层级缩进。互动仅图标／数字，不展示“点赞／取消点赞／收藏／取消收藏”按钮文字或蓝底选中框。
- 复审：已查看实际输出，调整评论行更多菜单至右侧统一对齐。无渲染溢出异常，标题／正文／楼主标记／计数均可读；折叠线以下评论内容需滚动查看。
- 证据：[PNG](../telegram-android-appearance/assets/post-detail-x-layout-20261021.png)。源 `apps/mobile/tool/x_detail_layout_preview.dart`，可选渲染入口 `apps/mobile/test/x_detail_layout_preview_test.dart`，设置 `HNUHOLE_DETAIL_LAYOUT_RENDER_DIR` 后执行 `flutter test --no-pub test/x_detail_layout_preview_test.dart --reporter expanded`；本轮渲染 PASS。
- 用户确认：待本次展示后的意见。真实业务接线、手机安装、键盘／大字／读屏与平台验收 NOT_RUN；本图不能代证。

## 图标与字体校准稿

用户指出需提升图标质感、尽量还原并核对字体，所以上述首张仍为被提修改意见的候选，未定稿。本轮不覆盖旧 PNG，另存 [校准图](../telegram-android-appearance/assets/post-detail-x-refined-20261021.png)。

- 核对官方源码：Telegram 的 [AndroidUtilities.bold](https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/java/org/telegram/messenger/AndroidUtilities.java#L252) 使用系统500或Roboto Medium；[DialogCell](https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/java/org/telegram/ui/Cells/DialogCell.java#L1180) 有17的名称和16的预览文字。前稿过多700/600并不能视为已经复现该层级。
- 当前预览采用 Regular400／Medium500，标题18、名称17、正文及评论16、元信息13.5。显式字距0；Noto可变字体设置wght轴，以免把常规和中等字重混成默认或合成粗体。中文为项目真实打包的 Noto Sans SC，并非已经确认与参考手机的厂商中文字形完全相同。
- 按当前连接手机只读报告的1080×2400显示覆盖、480dpi，预览改为360×800逻辑像素、3倍栅格输出1080×2400；正文左右8，更接近参考边距。未更改设备显示设置。
- 对照参考原图读取主互动图标像素边界：评论约62×59、心形62×55、收藏52×59、分享57×60。按24逻辑坐标重画轮廓，尤其修正前稿过窄且尖角的收藏，缩小心形及修正圆弧；统一1.75主笔画、圆端点、光学留白。底部图片／展开、返回和更多也改为同一套矢量画法，取消厚实的混用图标。图标灰为59666D，正文和次文字仍沿用共享Telegram近似色值。
- 头像按Telegram参考的圆形渐变字头像处理。评论回复采用同一头像纵轴及连接线，公开面具／楼主关系不变；无关注、Logo、相关、引用或新业务。
- 实际 Flutter 渲染及预览两文件的定向 Dart analysis PASS（0 issues），实际图片已查看。中途 C 盘临时目录空间不足，清理仅本任务旧2120/2121/2122 APK，保留已安装2123；仅本次进程的TEMP/TMP改用E盘专用目录后重新渲染成功。未删除其他工程或用户文件。
- 当前仍是演示数据的布局预览，未替换已安装详情页。用户反馈待本次展示；全局生产主题迁移、最终真机与交互验收不能由该PNG或单项渲染证明。

## 用户确认与真实接入

用户明确回复“可以，按规范提交合并”，本轮校准稿已确认。真实 `PostDetailScreen` 使用同一套 `detail_components.dart` 矢量轮廓、Roboto/Noto 400/500 与字号层级；作者、标题、正文和媒体、日期浏览量、图标计数互动栏、连续评论、固定回复入口已接入。评论区为“评论”，无Logo／关注／相关／引用。原菜单、身份停用提示、删除和举报、图片授权、精确回复目标和分页快照保留。原分屏组件兼容模式保留，当前详情明确选择 continuous 模式。

分享尚无业务实现，本次图标置灰并标注“暂未开放”，不伪造成功。底部图片／展开均进入支持图片的现有完整回复编辑器；没有GIF。旧单独收藏／点赞位置不再交付。643项全量 Flutter 回归 PASS，分析0；预览与实际原生安装分别记录于外观任务验证记录，不能相互代证。
