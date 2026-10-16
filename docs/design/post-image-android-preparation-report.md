# 主 App 帖子图片 Android 非手机准备

> **2026-10-15 主App帖子图片S18真机联调已完成约定范围：**修复实现 `fd2e4c04f48b29ddda0142660188988c4a655f5f`，分支 `codex/post-image-integration`。实际原生Picker/原图跨进程恢复、九图C/V/SQL上传及缺项补传、失败编辑同任务RETRY、受保护查看、Gal原格式保存与Gallery动画回放、删帖/退出/切账号/迟到隔离取得本轮证据；修复成功核对后残留旧错误提示。最后修改后分析0、相关宿主69、Python守卫15、bundle、Android Debug20263116构建/验签及上机复验PASS。手机窗口结束，系统设置已恢复、自己的App/后端已停、映射已撤；Linux专用私钥/库已清理。Windows清理被自动审批拦截，材料仍保留且私有目录ACL受限，不能写成已清理。iOS原始选图仍未实现，最大资源预算/库存升级/生产与评论私信另列；不重测旧TalkBack、不宣称全模块/双端通过。见[本轮报告](post-image-android-device-report.md)与[机器记录](post-image-android-device-verification.json)。下方旧记录保留各自版本与范围。

2026-10-15；当前结果 **PASS_NON_DEVICE_PREPARATION／等待另一会话释放手机**。本轮没有调用ADB、读取手机、安装/启动App或修改手机设置。按用户要求保留可直接使用的独立验收材料，手机病例PMA01–14全部NOT_RUN。

## 阶段与固定版本

1. **非手机准备：已完成。**起点 `a36b955ad09687e87e216b3f5a30910fe04b4b41`，实现提交 `2eeb19ce87542aed9e0c57874e8d6b3478df946d`，分支 `codex/post-image-integration`，独立目录 `E:/Hnuhole-post-media-joint-20261015/repo`。只增加验收工具和一个显式宿主素材检查；产品Dart/Android、图片包、认证插件、Go/SQL及五个锁文件均未改。没有重做封装、合并main或部署。
2. **手机集中验收：等待。**只在对方释放且用户给出继续窗口后操作，不反复询问旧TalkBack结果。入口为[一次性SOP及14项病例](../../tools/post-media-android/README.md)，当前所有设备结果都未执行。iOS、完整资源预算及生产另列。

## 可直接使用的材料

验收kit `E:/Hnuhole-post-media-android-20261015`，后端根 `/home/hnuhole/post-media-joint-android-20261015`。Windows工具/SDK、Pub/Gradle/profile/temp均为新任务物理副本或独立缓存，WSL虚拟磁盘在E盘；现成同版来源只读，不升级或清理认证/社区SDK。不使用手机连接或真实账号，不建立共用服务。

| 包 | 已验证构建身份 | 设备状态 |
|---|---|---|
| 主App | `org.hnuhole.post_media_android`／HnuHole 图片业务验收／20263115／0.1.0-media-android-ready | 未安装、未启动 |
| 原图存储probe | `org.hnuhole.post_media_android.probe`／HnuHole 原图存储探针／同版本 | 未安装、未执行 |

两包都是API29+ Debug、新测试签名，Flutter ARM64 engine；部分插件含其他ABI，不称纯ARM64 APK。主App使用真实 `lib/main.dart` 和专用C/V/私有开发CA，仅通过构建init覆盖包名、版本与可识别标签，未改产品源。新签名证书SHA256 `85c8fc2812395423b7d474c226e744e15f65392c770cbadb003af66afed0af8d`，不复用认证签名。APK完整SHA/长度/签名、准确命令和日志见[机器记录](post-image-android-preparation-verification.json)。

probe只访问自己包内的合成业务scope，编译了真实PostStore→原生business vault/Keystore/no_backup路径、九原图/跨chunk、新进程恢复、错误digest/异账号拒绝和关闭清理流程。write/read/purge需现场依次执行并核当前PID、phase及原writePid，旧PASS不能代证新阶段。它不替代主App原生选图/相册，也不把“关闭后访问拒绝”冒称硬件密钥已物理擦除。

9张带编号合成原图共1008698B；首张PNG为696527B，跨多个256KiB存储chunk。覆盖JPEG/PNG、EXIF6、480×7200长图、GIF、有限与无限WebP。06有限WebP为每帧2秒、两轮后停蓝；GIF和07 WebP无限循环。Pillow和Flutter都检查了容器/几何/原字节与动画时长、循环，不转换用户图片，不代证系统选图器或相册。

## 本轮实际检查

| 检查 | 实际结果 |
|---|---|
| 锁定离线Pub、SDK工具依赖版本与写入根 | PASS；五锁不变；工具bootstrap重新生成了路径相关锁内容但依赖版本未变，没有升级SDK |
| `flutter analyze --no-pub` | PASS，0问题 |
| `flutter test --no-pub --reporter=expanded integration/post_media_android_preflight_test.dart` | PASS，10项：9原图/动画、超限先拒绝不打开字节流 |
| `test_preparation.py` | PASS，15项：离线无网络/进程、包/签名/原图/源码/信任到期/路径与生成器越界守卫 |
| 构建入口拒绝设备命令 | PASS，4项；拒绝devices、integration_test、非offline pub、connected任务，实际设备工具未启动 |
| 真实C/V+正式Goose/最小grants/受限PG | PASS；C14/V4、账号/帖子/图片0、私有socket、私有CA和控制鉴权拒绝；服务已停止 |
| 同一专用后端重启彩排＋Windows→WSL HTTPS | PASS；验链/主机名，两个ready均200；结束后自己的C/V/watch/PG已停止 |
| 主App与probe的离线Android构建、aapt、apksigner | PASS，两个Debug APK、API29+、独立包、v2签名；没有安装或执行 |
| 离线就绪清单 | PASS；本地SHA/身份/源码/剩余信任有效期，完全不连接设备 |

日志根 `E:/Hnuhole-post-media-android-20261015/logs/`。上轮19项真实联调、375项完整宿主、244项后端保留 `a36b955`之前的固定源码与范围，**本轮没有重复执行，不重新计作本轮新通过**。本轮产品源码未变，新增加的只是测试/工具；Release本轮未构建。

准备时的失败已经定位并复验：Windows SDK含长路径iOS golden素材，改用长路径复制；NTFS不支持POSIX chmod，只导出公开CA/origin，私钥留Linux0700根；PG start不会复用旧参数，现显式限定私有socket/端口/无TCP；首轮离线Pub早于补充缓存复制完成，补齐后重跑通过。曾观察V Gate为FROZEN/INDEPENDENT_ANCHOR_FROZEN，未修改认证实现、伪造开放状态或自动保留旧代次；对零账号/零OTP/零帖测试库明确执行正式签名恢复后重启就绪。**有账号停机恢复仍按正式Gate/重新登录契约验，不能把本轮空库彩排扩称通过。**

## 手机释放后的入口

先运行 `tools/post-media-android/check_ready.py --kit E:/Hnuhole-post-media-android-20261015`，再按SOP启动自己的lab。当前叶证书有效至 **2026-10-22T15:49:12+08:00**；清单要求至少剩30分钟，过期先重建信任和APK，不带失效材料上机。现有服务全停，不占资源等待窗口。

现场只复用明确释放的既有连接，不启动/重启ADB、不改共享key、不覆盖未知同名包/映射。先跑独立probe，再正常主App集中核原生Picker/原图草稿与杀进程恢复、九图上传/补传/失败重试、真实查看和保存/回放、退出失效/迟到及新业务IME/控件。旧组件TalkBack全套不重复；厂商播放器表现与文件完整性分别记录，不能静默转GIF/降质或以宿主结果代替真机。

按当前“准备好等待配合”的用户要求，APK、新调试key、自己的Linux空库/CA/Gate、同版工具和缓存暂时保留；Windows profile/private目录ACL已仅限本用户/System/Administrators，未改全局安全配置。源码/小型脱敏记录入Git，所有材料不入Git；设备验收结束后只清本任务资源，不清其他会话环境。

iOS原始资源适配、最大九图预算/生产存储配额与WAL/备份、库存升级、评论私信和发布部署仍独立。当前“准备完成”不等于Android业务真机或完整模块通过。
