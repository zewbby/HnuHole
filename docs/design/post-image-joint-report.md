# 帖子图片前后端联合联调

2026-10-15。本次**真实进程宿主联调 PASS**：生产 Flutter 页面/API/控制器 → 实际 C/V 程序 → 正式迁移与受限 PostgreSQL → 固定图片校验器的帖子图片链路已跑通。本结论不包含手机原生选图、系统相册、物理交互或 iOS。

## 固定源码与隔离

- 分支 `codex/post-image-integration`，独立clone `E:/Hnuhole-post-media-joint-20261015/repo`。
- 前端起点 `075b567ee6093319a0dcb48ab40919aada5cb8f2`，后端固定 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587`，共同基线 `e0c128033682923d519ea99546d72503b085a99e`。联合实现提交 `31e82df6ad0f8345471705cf78e6e0f463beecfb`，两者均为其直接父提交，未合并 main。
- 两处源工作区未修改。合并冲突只有四份交接/台账，已保留双方内容、PM01新增模块和原36个模块；没有用整份一方台账覆盖另一方。
- WSL根 `/home/hnuhole/post-media-joint-20261015`，虚拟磁盘在E盘。新建私有socket PG实例、两个空 C/V 数据库、独立非owner runtime/migrator/recovery角色、随机HTTPS端口、新CA/签名/Gate及合成账号；没有使用既有DSN、真实账号或认证秘密。C/V仍是同机开发授权，不代证生产运营独立性。
- Linux使用同版独立 Flutter3.47.5/Dart3.13.4副本及本任务Pub/Go/home/tmp，SDK工具依赖也已核对全部在任务根。Go1.22.2、PG16.15、Goose3.22.1执行既有二进制；独立Python3.12固定 Pillow12.3.0/libwebp1.6.0，只补6.9MB wheel。Windows构建复用本会话既有专用SDK/JDK/Android工具，profile/Pub/temp单独放新E盘目录；没有升级或清理认证共用SDK。

## 真实联调与替身边界

入口为[联合runner](../../tools/post-media-joint/README.md)与[任务单](post-image-joint-plan.md)。`run.py`构建实际 `cmd/api`、`cmd/verifier`，执行 Goose 到C13、升级14、再次无操作，核对通道种子原样保留；V到4并重复无操作，再应用正式最小grants。API进程使用runtime角色，不持有迁移/恢复角色。

三个独立Flutter进程运行 `integration/post_media_joint_test.dart` 的write/read/edges。注册、身份、通道、命令/清单/grant/字节、发布worker、失效和数据库都是真实实现。透明TLS代理只在指定连接处丢响应/断网，原样转发C的业务状态、正文与授权元数据，未伪造202/204/公开成功。SMTP捕获与控制接口仅供本次合成账号；短时发布限制由受标记保护的 `authlab/post-media-control` 调用已有 `ApplyAccountMute` 与真实Gate，未直接改SQL状态制造失败。

宿主的选图源、文件vault和相册writer是测试接缝。保存resolver会重新走受保护HTTP，实际保存协调器写出原字节临时文件，再由host writer校验并结算清理；这不代表Gal权限、MediaStore、Photos或系统相册回放。实际主App根、通道、详情和独立查看路由均运行，但没有启动手机App。

| 检查点 | 实际结果 |
|---|---|
| J01–J04 | 真实C/V注册、SMTP验证码、身份/通道；生产写帖/确认页九图空正文；意图落盘后回原通道；C已受理后丢CREATE响应，仍只发一次命令 |
| J05–J07 | 新Flutter进程读取同机原图草稿/意图；SQL8/9已验证时仍未公开；手动只补缺项；丢PUT收据但已落库的一张没有再次PUT |
| J08–J10 | 九图有序清单；JPEG/PNG/GIF/WebP及EXIF的客户端原文件、受保护读取和SQL payload散列/长度一致；保存resolver原字节结算；实际main→通道→详情→查看器入口 |
| J11/J12/J17/J18 | 删帖立即终止组且C404，九份SQL payload清除；取消保留本机两张原图草稿且不公开；Upload能力不能读取受保护图片（401），取消后的能力不能写入（403） |
| J13–J16/J19 | 校验器文件漂移导致真实503，暂停补传但不误注销Bearer，恢复后成功；C Gate冻结终止媒体，恢复新代次须重新登录，旧组始终无效；实际等待61秒确认60秒租约失效；退出后已授权但迟到的字节不能交出；服务端发布限制→明确失败→编辑新尝试仍固定身份/通道且可完成 |

19个检查点全部PASS，独立SQL/请求计数交叉核对。前后232项运行输入摘要相同，并已逐文件核对权威Windows工作区；不是只对独立mock端点测试。

## 本轮修复

真实联调和新增宿主回归同时复现：图片部分上传失败后进入明确失败，用户编辑并提交RETRY，后台仍停在ACCEPTED。原因有两层：旧 `PostImageUploadProgress.message` 留在内存，旧 `mediaUploadPaused` 又随retry原记录复制到新意图。现在新意图数据移除旧暂停标记，**只有新意图成功落盘且授权仍当前时**才清除旧内存进度；旧在途工作仍按原command/attempt围栏，未允许重发未知CREATE。新增回归核对新尝试实际重新PUT并发布；真实C/V/SQL用例也已重试通过。

Linux全套回归还复现两项测试退出时的errno39：夹具在切账号新SQLite后台连接尚未完成时就枚举连接并删目录。仅修夹具restart/close，先等待已登记的factory opening Future，再关库/删本任务目录；没有加睡眠、排除用例或改认证/数据库约束。完整375项均实际执行。

其余前期失败属于环境/测试假设：独立SDK镜像缺目录已从同版现成SDK补齐；宿主SQLite只补指向系统只读库的任务内链接；UI输入改为等真实页面和按钮启用帧；遵守HnuholeApp对控制器的释放所有权；未知命令按既定submitted/UNKNOWN两层状态断言。Gate恢复使旧会话失效是既定安全行为，测试改为真实重新登录，未修改认证契约。

## 本轮检查与日志

精确命令、被测输入/锁散列、结果、日志摘要、APK信息和历史失败见[机器记录](post-image-joint-verification.json)。保留日志根 `E:/Hnuhole-post-media-joint-20261015/logs/`；Linux导出在 `logs/linux/`。

| 命令/检查 | 结果 | 证明范围 |
|---|---|---|
| `python3 -B .../tools/post-media-joint/run.py --root ...` | PASS，19检查点/3个Flutter进程 | 实际C/V进程、Goose、PG、完整图片链路 |
| `flutter analyze --no-pub` | PASS，0问题 | 当前mobile源码/测试 |
| `flutter test --no-pub --reporter=expanded test` | PASS，375项、零排除 | 完整Linux宿主套件；包含原控制器43项与新暂停状态回归 |
| `bash authlab/run-post-images-isolated.sh` | PASS，72顶层/含子项244项、无skip | 本轮新建独立PG，SQL/race与媒体协议/权限/生命周期回归；此runner使用Up SQL，Goose另由实际cmd联合runner验证 |
| `go vet ./...`、`go test -run '^$' ./...` | PASS | 最后Go工具修改后的全包检查/编译；零测试编译不计为运行测试 |
| 固定Python `media/test_validator.py` | PASS，4项 | 合成图片完整容器/动画验证 |
| `packages/openapi/check-specs.py` | PASS，6份 | 当前API契约 |
| `flutter build bundle --debug --no-pub` | PASS，Windows专用工具 | Linux这项因没有Android SDK而FAIL_ENV，保留原日志；没有在Linux下载大工具链，用已有独立Windows环境完成 |
| Android `assembleDebug`、aapt、apksigner | PASS | API29+，独立 `org.hnuhole.post_media_joint`，20263102/0.1.0-media-joint，Flutter ARM64 engine；部分插件另含其他ABI，不称纯ARM64 APK。未安装/启动 |

Android原生构建最后使用离线依赖。既有AGP/Kotlin弃用警告保留，未借机升级工具链。Release构建本轮未执行；之前版本的Release/手机证据保留原范围。

## 尚未包含的验收

- **Android业务真机：NOT_RUN。**新设备窗口后重建并验新包/签名，补实际Photo Picker权限/原字节、进程被杀恢复、IME、大字/读屏、真实相册保存/动画回放与压力；不把本轮文件vault/选图源/host writer算平台通过。旧独立组件S18结果不转算本次业务App，不重复索取旧TalkBack确认。
- **iOS原格式选图：NOT_DEVELOPED／入口仍挂起。**上轮已证实锁定库会重编码；先选择原始资源适配，再做Mac/Xcode/iPhone/Photos/VoiceOver，保存默认仍关闭。Android原文件保存默认开启保持不变，最低Android10/API29，不适配旧系统。
- **生产与资源预算：NOT_RUN／待决定。**九张大原图的总内存/流量、并发/账号配额、SQL容量/WAL/备份删除、衍生缩略图、已有文字库存量升级与正式部署/运营独立证据仍须专项验收。本轮Goose只证明私有空库13→14的通道种子保留，不扩称生产存量升级通过。
- 评论/私信页面与图片业务仍未开发，不能借帖子联调完成而关闭。

本轮不操作手机/ADB/模拟器、不发布Release、不部署、不合并main。按授权正常提交推送本联合分支；最终HEAD、远端及清理回执在日志交付记录中登记。小型脱敏证据已保留；本次测试账号/数据库/密钥、专用缓存、Linux SDK副本与APK已按owner和绝对路径精确清理，既有工具及其他任务资源未修改。清理回执 `logs/joint-cleanup-final.json` 已核对通过；原APK及新建调试私钥均已删除，后续设备验收须重新构建并使用新测试签名，不得把已删除制品当作可安装包交接。
