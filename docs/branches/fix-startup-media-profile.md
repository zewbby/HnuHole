# MOBILE-STARTUP-MEDIA-PROFILE-01 录屏体验修正

- 更新时间：2026-10-23（Asia/Shanghai）。
- 分支：`codex/fix/startup-media-profile`；从当时最新 `origin/main` 的 `8dca780` 建立独立 worktree。
- 关联既有模块 A12、B03、B06、B10、PM01、IV01；与 AUTH-STARTUP-FLASH-01、MOBILE-NAV-REFRESH-01 衔接，保留历史验收范围。
- 状态：本地实现与验证；未提交、推送、合并或发布；同签保数据覆盖 vivo 2026102319，已登录冷启动限定验收通过。

## 录屏与实现

用户录屏长约10.84秒：启动白屏后短暂显示欢迎操作，再进入准备页、空白首页；个人页空态先出现，身份资料后插入导致整体下移。放大图标并核对源码后确认：录屏中的小图片图标是加载占位，无法单据录屏认定请求失败。本轮修正图片加载／失败的状态表达和恢复入口，不宣称找到了历史网络或服务端故障。

1. Android 29–30 的窗口启动背景加入矢量品牌标识；Android 31+ 使用对应系统启动图标和浅／深色背景。Flutter 恢复会话及加载完整通道目录时共用不可操作的品牌画面；只有确认退出登录后才显示欢迎页。品牌图形不依赖字体载入；既有认证失败和 Gate 处理保留。
2. 首页首次无内容的读取阶段提供静态骨架，取消横跨通道栏下方的动态蓝条；已有列表的刷新不插入该骨架，也不清空原内容。下拉刷新继续由 RefreshIndicator 反馈。
3. 个人资料与本人内容并行读取，独立处理资料失败；个人头像／昵称区域始终保留，成功、失败、空身份状态均保持布局。资料请求使用独立序号，翻页不取消尚未返回的资料，刷新／切账号则隔离旧响应。
4. 图片字节／解码等待明确显示“图片加载中”，失败显示“图片加载失败／点击重试”。显式重试清除相关字节和缩放解码缓存后重新走受保护读取；原有授权租约不延期，账号／会话／删除／冻结围栏继续有效。

源码位于 `apps/mobile/lib/src/navigation/entry_screen.dart`、`posts/{feed_screen,post_controller,post_screens,post_images,post_media_repository}.dart` 及 Android `res`。没有修改服务端、数据迁移或授权策略。

## 验证与接续

- PASS：`cd apps/mobile; flutter pub get --enforce-lockfile --offline`，锁文件无修改。使用既有 Flutter 3.47.5／Dart 3.13.4；`PUB_HOSTED_URL=https://pub.dev` 对齐仓库锁文件。
- PASS：`flutter test --no-pub test`，830通过、3跳过；跳过项沿用既有外部真实HTTP fixture未配置范围，不代表真实服务通过。包含新增的资料延迟成功／失败位置不变、首屏骨架、翻页不取消资料、图片传输／解码失败后重试及缓存重新读取。
- PASS：首次 Android ARM64 debug APK 构建，验证原生资源可编译；最终源码分析／构建与截图结果以下方最终回执为准。
- NOT_RUN：本轮手机覆盖安装、录屏对照、冷启动耗时和真实图片请求追踪、iOS、独立review与远端CI。主机测试不代证这些项目。
- 自动检查：既有 `auth-feedback.yml` 覆盖启动与会话／导航回归；`feed-ui.yml` 覆盖本轮定点测试、分析和bundle；`post-images.yml` 覆盖全量Flutter及Android候选构建关联工作流。本地没有触发远端CI。
- README不变：修正现有展示／恢复行为，不改变项目能力、整体阶段或使用入口。

下一验收入口：本分支工作区差异，及 `E:/Hnuhole-env/video-analysis-20261023/` 中的日志和截图。构建产物不纳入Git。正式送审前补独立review；设备验收时核对当前用户分支整合与同签名安装，避免覆盖其他尚未合并的视觉改动。

## 最终本地回执

- PASS：最终 `flutter analyze --no-pub`，0问题；Android ARM64主入口debug APK重新构建通过（2026102317，仅本机构建，未安装）。
- PASS：另行运行本地渲染夹具1项，390×844实际字体下检查浅／深色启动、首页骨架、个人资料等待与返回后5张截图；标题和空态位置一致。临时渲染夹具移至证据目录，不加入产品测试套件；全量830项为产品测试，二者分开计数。
- PASS：工作区协作规则／内容／Android XML检查与 `git diff --check`；依赖锁无修改。未执行commit／push／merge，全部修改保留在需求分支的工作区。
- [最终版本与验证记录](../design/validation/startup-media-profile-20261023.json) 保存源码SHA-256、实际命令、APK摘要、未验项与证据位置。设备冷启动、历史图片卡住的原因和用户录屏对照仍为NOT_RUN／NOT_CONFIRMED，不能将主机验证当作真机验收。

## 用户复测后的启动修正（2026102319）

2026102318 用户视频确认：已登录启动仍有系统 logo → Flutter logo 的位置／亮度变化和后续居中转圈。前述本地 logo 截图仅证明静态绘制，不证明真机启动过渡通过；原“统一启动”实现被本节替代。

用户确认目标为“一次系统 logo → 首页静态骨架 → 内容”。移除 Flutter 品牌等待画面，恢复会话／目录加载期间直接复用首页布局与静态骨架；指针、焦点和语义操作均暂时阻断，未授权前不创建业务控制器视图或提前读取帖子。确认登出后仍进入欢迎页；认证／目录失败保留重试。

- PASS：startup_entry、login_home_navigation、app_navigation、feed_ui 共32项，分析0问题。覆盖延迟目录加载、10秒无动画、未授权前无帖子请求、就绪前后标题／底栏位置一致、登出欢迎页。
- PASS：同签 ARM64 debug 2026102319 构建、保数据覆盖 vivo V2323A、已登录 COLD 启动录屏：系统 logo 后直接进首页骨架再进帖子，未见第二段 logo／启动居中转圈。系统 splash 退出仍有系统默认过渡；debug 系统 logo 约3秒，am start 总耗时3576ms，不作为正式包性能基准。
- 证据：E:/Hnuhole-env/video-analysis-20261023/retest/vivo-cold-start-2026102319.mp4；定点日志 retest-focused.log、retest-analysis.log。图片区域等待与启动等待分别计；本次未更改图片等待表现。
- 本轮未重跑全量830项，旧结果只保留原版本范围。未提交／推送／合并／发布，用户最终体验确认待回执。
