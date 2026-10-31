# THEME-BLUE-AVATAR-01 — 主题蓝色与首页当前头像

- 模式：常规
- 负责人／状态维护人：当前 Session
- 分支／Worktree／PR：`codex/fix/theme-blue-avatar`；`E:/Hnuhole-env/source/HnuHole-theme-blue-avatar`；未创建 PR
- 实际基线：2026-10-31 fetch 的 `origin/main` `a4d7228a0dd4b91e851746ab7f9fb37d1ec806b5`，新 Worktree 初始干净。
- 授权依据与边界：用户本轮两张截图及四条需求，授权本地界面修改与必要验证；未授权推送、合并或正式部署。
- 需求确认：图一个人页空态加号及左上角 `:)` 使用主题蓝色；图二首页左上角显示当前身份头像，底栏中间加号使用蓝色；私信与通知页左上角标题使用相同主题蓝色。无未决取舍。
- 更新日期：2026-10-31
- 状态：实现已完成；本地验证 PASS，真机与远端 CI NOT_RUN；合并未合并；发布未发布

## 目标与范围

复用 `HhTelegramPalette.action`，调整个人页空态发帖按钮、颜文字、共享底栏发帖按钮及私信／通知根页标题。首页头像使用现有当前浏览身份及受保护头像加载组件，身份切换和同一身份头像变更后同步更新；默认头像沿用其他身份入口的昵称首字回退。保留头像点击进入个人页、发帖操作、页面导航及数据读取机制。

## 接口与依赖

复用 `PostController.activeIdentity`、其管理器身份目录和个人页同款 `HhDmAvatar`／`IdentityAvatarRepository`。同时监听身份选择与身份目录变化，以覆盖头像变更但选择 ID 不变的情况。头像继续由现有授权窗口隔离的读取缓存解析，不新增网络接口。

## 验收标准

- 个人页空态加号、左上角颜文字、底栏加号、私信与通知标题随浅色／深色主题使用主题蓝色。
- 首页当前头像与当前浏览身份一致，切换身份再返回首页后更新；同一身份更新头像后同步更新。
- 首页头像仍可进入个人页，底栏入口与空态发帖入口仍执行既有操作。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 实现 | 基线加本任务六个产品文件与三个测试文件差异；由本任务本地提交承载 | PASS；五处正文色改为主题 action 色；首页接入当前身份头像，同时监听选择与目录更新。 |
| 静态检查 | Windows，Flutter 3.47.5／Dart 3.13.4；`flutter analyze --no-pub` | PASS；最终代码 No issues found。日志 `E:/Hnuhole-env/theme-blue-avatar-20261031/final-analyze.log`。Dart 格式与 `git diff --check` PASS。 |
| 聚焦回归 | `flutter test --no-pub test/personal_profile_test.dart test/notification_inbox_test.dart test/feed_ui_test.dart test/feed_scroll_refresh_test.dart test/app_navigation_test.dart test/identity_avatar_scope_test.dart test/identity_avatar_recovery_test.dart test/login_home_navigation_test.dart --reporter expanded` | PASS；70项，日志 `focused-tests.log`。首次测试临时使用 Windows 系统 SQLite，执行后已恢复 pubspec；后续复用官方摘要匹配的缓存 DLL。最终头像回退改为个人页同款组件后，`personal_profile_test.dart` 5项复跑 PASS（`final-avatar-tests.log`），其他产品差异不变。验证头像引用、默认回退、切换身份返回、同一身份头像更新、浅深主题颜色、导航与授权窗口；宿主 HTTP 替身不证明真实服务端图片传输。 |
| 渲染自验 | 390×844逻辑像素，真实字体，临时宿主渲染驱动；`flutter test --no-pub test/theme_blue_visual_qa_test.dart --reporter expanded` | PASS；实际查看首页、个人空态、浅深色私信／通知六张 PNG，指定颜色和当前默认头像显示正确。驱动与截图保留在 `E:/Hnuhole-env/theme-blue-avatar-20261031/`；临时测试已从源码移出。另查看现有 Feed 渲染，底栏蓝色加号正常。 |
| Android 构建 | 最终产品差异；JDK 17、SDK 36、Gradle 9.3.1；在 `apps/mobile/android` 执行 `./gradlew.bat --offline assembleDebug -Ptarget-platform=android-arm64 -Ptarget=E:/Hnuhole-env/source/HnuHole-theme-blue-avatar/apps/mobile/lib/main.dart -Pkotlin.compiler.execution.strategy=in-process` | PASS；301项任务，`BUILD SUCCESSFUL`，日志 `android-offline-build.log`。此前 `flutter build apk --debug --target-platform android-arm64 --no-pub` 因动态 Android 测试依赖的联网解析失败（`android-build.log`），离线复用现有缓存后成功；未改工程配置。SQLite ARM64 缓存由包内官方摘要校验。APK `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`，SHA-256 `759e681dc265e94d3a810c41fe8035b8a6444eb59935f591fadeff1715265120`，`apksigner verify` PASS。未安装或清理设备数据。 |
| 远端／设备 | 当前本地差异 | NOT_RUN；未推送、未创建 PR，无本次远端产品 CI；实体设备、iOS、正式发布待验。 |

## 阻碍与下一步

本地实现、操作回归、渲染与 Android debug 构建已完成。没有本地阻碍；后续推送／PR、合并、安装及发布按对应授权执行。README 无项目能力或主要入口变化，不作单任务状态追加。所有本机日志路径均相对于 `E:/Hnuhole-env/theme-blue-avatar-20261031/`。

## vivo 试用安装（2026-10-31）

### 普通静态照片上传失败修复

用户反馈头像选择后报“头像已失效或图片不符合要求”，确认选择普通静态照片并提供失败原图。实测489354字节、810×1440的JPEG能完整解码，但EOI后有24字节附加数据；正在运行的开发服务校验器在 `JPEG terminator` 处拒绝，原图检查和缩略图进程均退出2。普通合成PNG/JPEG/WebP校验正常，问题已用用户实际图片复现。

修复仅限头像选择入口：复用已有字节／像素预算预检，再要求单帧，按实际解码方向等比例缩到最长640像素并编码标准PNG，移除附加数据及元数据后调用原头像上传API。默认头像、未知上传恢复、权限检查与服务端严格校验不变；帖子原图处理不变，用户本地原图不修改。基线为本任务 `a4ab711`；同步到 `a578e65` 加既有本任务差异的vivo整合包。新增synthetic-only回归保留在 `identity_avatar_photo_test.dart`；实际原图只通过环境变量复现，不提交用户照片。

Windows Flutter 3.47.5：任务分支头像／图片选择与身份管理20项 PASS（`avatar-main-tests.log`）；vivo整合分支聚焦12项 PASS（`avatar-fix-tests.log`），analyze最终PASS（`avatar-final-analyze.log`）。同一用户图片经实际Flutter代码生成360×640标准PNG、299383字节，送入当前开发服务同一校验程序，完整检查及缩略图生成均退出0；缩略图22384字节。此项证明实际输入兼容性，不冒充用户账号上的HTTP上传及保存成功。首次analyze的花括号lint已修正。

vivo Profile离线构建PASS（41秒，`avatar-build.log`），版本2026103103，APK SHA-256 `3bc7acfda52cda5549111643d0dec1247ec8af5ede9befc6e0120537c73799b2`，同签名验签PASS。实际账号选图／上传／保存等待设备安装后的用户复验；未修改后端、数据库、正式数据或服务配置。

### 后续标题调整

用户试用后要求将个人页左上角 `:)` 换为“我的”，字号、颜色和字体与通知／私信完全一致。本轮将三处统一为 22号、w700、主题 action 蓝色，沿用页面共同主题字体；整合包使用现有本地化 `hhText`。个人页 key 调整为 `profile-title`，对应既有测试同步定位。任务分支与 vivo 整合源码同步修改；两套个人页／通知测试各12项 PASS，整合版 analyze PASS，离线 Profile 构建 PASS（47秒）。日志 `title-main-tests.log`、`title-tests.log`、`title-analyze.log`、`title-build.log`。试用版本 `2026103102`，APK SHA-256 `0536db55dc8bc659950c981bfe37853341844977f138e26237328e4964c3c9ed`；同证书验签 PASS，沿用上一轮安装授权覆盖安装。

用户明确要求“安装vivo上我看看”。核对 vivo V2323A `10CEAG17RY003M7` 原版本为 `2026103016`／`0.1.0-settings-v3`，对应 `a578e65`，含尚未合入当前主线的设置功能。为保留正在试用的功能，在独立临时构建 Worktree `E:/Hnuhole-env/source/HnuHole-theme-blue-vivo` 以该 SHA 为基线，叠加本任务六个产品文件和三个测试文件差异。没有修改他人的设置 Worktree。整合中保留本地化、22号标题及设置入口逻辑，仅移除通知标题样式的 const 以支持主题色；头像切换测试适配当前底栏个人入口。完整整合差异为本机 `vivo-integrated.patch`。

最终整合代码 analyze PASS；个人页与通知12项测试 PASS（`vivo-tests-final-pass.log`），Feed滚动15项 PASS。首轮编译发现整合版 const 样式问题已修正，测试入口定位差异也已修正并复跑。Profile构建因依赖联网解析失败后使用相同 dart-defines 离线 `assembleProfile` 成功（`vivo-offline.log`）。沿用既有 `usb-defines.json` 和 `AUTH_DEV_PROFILE=true`，后端与 USB 转发不变。

APK `E:/Hnuhole-env/source/HnuHole-theme-blue-vivo/apps/mobile/build/app/outputs/flutter-apk/app-profile.apk`，版本 `2026103101`／`0.1.0-theme-blue`，SHA-256 `674b6da9edcefa2b6d6e23eaf57a46205d9aa7689f23e2cb7537ad0f186fdc0c`。从设备读取旧包并核对两包证书一致（SHA-256 `1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`），验签 PASS；`adb install -r` 返回 Success，启动 PASS。设备读回新版本，更新时间 2026-10-31 10:25:39，首次安装时间仍为 2026-10-30 09:57:04；未卸载或清数据。等待用户试用反馈，安装启动不代表本次真机功能验收。未推送、合并或正式发布。

2026103102 安装回执：vivo 系统安装确认后 adb 返回 Success，设备读回版本2026103102，启动PID 18087，首次安装时间保持2026-10-30 09:57:04，数据保留。

2026103103 安装回执：adb install -r 返回Success，读回版本2026103103，启动PID 7769，首次安装时间保持2026-10-30 09:57:04，应用数据保留。整合源码差异已保存到本机 vivo-avatar-fix-integrated.patch，实际选图保存等待用户复验。
