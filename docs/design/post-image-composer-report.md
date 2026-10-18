# 帖子选图上传前端交接

2026-10-15。选图、图片草稿与逐项上传已接入现有发帖页面，后端继续固定在独立分支；本轮交付前端实现、宿主证据和 Android 构建，不代表真实 C/V/SQL 与手机联合验收。

## 版本与范围

- 工作目录：`E:/Hnuhole-image-viewer-component-20261012/business-20261015/repo`。
- 分支：`codex/image-viewer-business-integration`；起始 `7c5817a7e3035dc12630e12f730b2e0229712564`，本轮实现提交 `5cd5fdb8f3766bb5ae5840fa7546eda6739fd98c`。最终文档提交和远端以 Git 交付回执为准。
- 后端契约：`codex/post-image-media`，实现 `efccade441bfc5d453751a3fac74211b090e8129`，交接 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587`。没有合并该分支或 main，没有部署。
- 只改 `apps/mobile` 的发帖、草稿存储、装配、选图库依赖/用途说明、测试和本交接。认证、通道、身份、导航、Go、SQL及 `packages/image_viewer` 均未改；未操作手机、ADB、模拟器或其他会话服务。

## 实现与输入契约

`main()` 现在装配 `HttpPostUploadApi` 与 `NativePostPhotoPicker`。原通道进入写帖页，正文后显示三列等尺寸图片：最多9张、尾部添加、右上移除、长按拖动排序，读屏另有向前/向后移动动作。点击可用图片沿用独立查看组件看完整原比例；草稿预览关闭保存，不额外创建图片引擎。单张读入/校验失败只占本张失败槽，可替换或移除，其他图片及文字保留。沿用既定标题15字素、正文3000字素；标题必填，正文或至少一张有效图片必有其一。

选图使用官方 `image_picker 1.2.4`，不传缩放或压缩质量参数。客户端边读边限制单张10MiB，嗅探 JPEG/PNG/GIF/WebP，通过 Flutter 现有 codec 预检尺寸、帧数/像素/时长预算，并保留原始字节与 SHA-256。JPEG 的小型 SOF 元数据读取只用于编码尺寸，避免 EXIF 显示旋转与服务端原始宽高不一致；不是自研解码器。服务端完整容器校验仍为最终权威。没有转 GIF、降质或衍生缩略图；现有预览仍读取原图，九图总内存/流量预算尚未验收。

持久清单每项只含随机 `blobId/mediaId` 和六个协议字段：`mediaId/sha256/mimeType/byteLength/width/height`，顺序即选图顺序。原图以256KiB分块放入现有账号/环境绑定的加密 SQLite 行信封，沿用三表 v1 和 vault；没有新增服务端 SQL 或修改认证存储。原图、引用和草稿在事务中一起保存，磁盘失败则保留编辑器中的原字节供重试。移除/替换、丢弃与终态压缩按仍存续的草稿/意图引用清理孤块；确认取消上传任务先保留可编辑图片草稿，再压缩旧任务。旧客户端不支持新 `mediaRoot/mediaChunk` 行，不能将含图数据库降级交给旧版本写入。

打开系统选图器前先持久化文字、既有图片及中断标记。重启恢复已保存的原图与顺序；系统未返回的这批图片提示重新选择。Android `retrieveLostData` 队列没有账号/请求绑定，启动时只排空、不自动导入给当前账号，以防切号串图。原生选图器进程被杀后的实际行为仍待手机验收，宿主重建不能代证系统行为。

发布先持久化不可变的清单与 CREATE/RETRY 意图，媒体摘要按后端黄金向量封装原文字 frame；无图时原文字摘要完全不变。确认后沿既定行为回原通道，后台发命令；只有受理后才查询逐项状态、取得短期 grant、按原字节 PUT。尚未得到命令结果只核对原 command key，不重发 CREATE，不将 UNKNOWN 当明确失败。明确失败可改标题/正文/图片后发新 RETRY，原身份/通道固定；另一设备缺少原图时拒绝进入旧文字重试，避免丢图。

补传严格匹配 task/post/attemptVersion/清单顺序，先查询服务端状态，跳过已确认图片。某项失败继续处理其他项；停止自动重试并显示待补传序号，用户“继续上传”重新查状态。PUT 已成功而收据丢失时不会盲传已确认图片。CREATE/RETRY、状态/grant 走现有受保护 HTTP 和续期契约；字节 PUT 仅使用瞬时 `Authorization: Upload`，不发送 Bearer，不持久化 grant，不跟随重定向。失效、切号、取消/新尝试前后均检查代次和最新意图；已在途系统/HTTP操作不承诺远端撤回，迟到结果不得恢复旧 UI。Upload capability 的401/503不误注销 Bearer 会话。

## 平台与依赖门槛

Android最低10/API29，未添加旧 Android 适配。锁定 Android 选图插件在无缩放、质量100的分支返回原文件路径；这是源码核对，系统 Photo Picker/相册提供方是否逐字节交回原图仍须手机核对。现有组件 Android 原文件保存默认开启未变，本轮没有重复旧 TalkBack 或相册验收。

**iOS 原格式选图尚未启用。**锁定 `image_picker_ios 0.8.13+12` 的 `FLTPHPickerSaveImageToPathOperation` → `FLTImagePickerPhotoAssetUtil` 使用 UIImage/CGImageDestination 重写图片，GIF 还会重新生成循环/时序，即使不传压缩参数也不能证明原字节保留。前端因此在非 Android 返回可理解的未启用提示，保留文字和已有草稿；Info.plist 已留用途说明，但不代表 iOS 选图开发完成。后续需要评估支持原始资源读取的现成适配方案，再独立实现与验收；本轮未 fork、未写 PhotoKit 桥或解码器。iOS 原生构建/Photos/VoiceOver 均 NOT_RUN，原保存默认关闭。

`pubspec.lock` 保留，新增16个锁定选图依赖；原有条目的版本/来源/hash均未变，组件和示例锁未改。SDK/JDK/Gradle使用本任务既有独立 E 盘副本；Pub、profile、临时文件、Gradle缓存及日志均在本任务 E 盘目录。未修改全局配置或下载大型工具链。

## 本轮实际验证

准确命令、输入文件摘要、时间、退出码、日志 SHA 和本轮 APK 信息见[机器记录](post-image-composer-verification.json)。日志在 `E:/Hnuhole-image-viewer-component-20261012/business-20261015/logs/`，执行器为同任务的 `run-host.ps1`。

| 检查 | 本轮结果 | 证明范围 |
|---|---|---|
| `flutter analyze --no-pub` | PASS，0问题 | mobile源码/测试 |
| `flutter test --no-pub --reporter=expanded` | PASS，374项，零排除 | 完整mobile宿主套件，含原控制器43项、实际SQLite、媒体协议/HTTP及页面 |
| `flutter build bundle --debug --no-pub` | PASS | Dart/kernel及资源打包 |
| Android ARM64 Debug原生构建/验签 | PASS，构建/验签均通过 | 单独包名 `org.hnuhole.post_media_check`，不安装、不代表业务真机 |
| 实际Flutter渲染 | PASS，人工查看 | 三列几何/添加/移除与真实长按排序、仅图下一步；[UI复审](ui-reviews/post-image-composer-v1.md) |
| C/V/SQL完整上传联调、原生选图与进程杀恢复、业务真机 | NOT_RUN | 双方分支尚未联合装配；本轮没有服务和手机操作 |

宿主覆盖：原图加密落盘/重开/重排/删除回收、坏图替换/移除、九图限制、部分补传、丢PUT收据、丢CREATE响应后重建核对、明确失败编辑重试、确认取消保留原图、NOT_ACCEPTED原图恢复、晚到选图隔离、未绑定lost-data排空、2MiB以上分块原图/缺引用事务回滚、实际Flutter解码与EXIF预算。HTTP测试使用合成原图和受信 loopback TLS，断言线上的清单/grant/Upload PUT；测试HTTP和会话/vault是夹具，不能当作真实 C/V/SQL 或 Android Keystore通过。

本轮修复历史 Windows errno32 的真实原因：`PostController.dispose()` 发起未等待的 `PostStore.close()`，第二次 close 看到 closed 状态后过早返回，SQLite仍关闭中时夹具删文件。现在并发 close 共享同一个 Future，拒绝关闭后新入队操作，已排队操作完成后才关数据库。43项控制器测试本轮实际全跑通过，不再排除；先前读接线报告的失败/未执行保留原日期与范围。

补充收尾复现：启动排空系统选图队列时会话失效，旧代次返回可能重新显示旧草稿卡片。新增测试先实际失败，再在恢复入口等待完成后重验授权代次/账号/销毁状态，阻止迟到恢复。完整回归另复现上传失败进度写入与取消命令争用同一行 revision，取消此前会被本地CAS冲突拦住。现在仅在同任务/同尝试/同一旧命令仍有效时，有限重试尚未发送的本地CAS，保持同一新command key；已有新命令或终态则转核对，不重发网络命令。最终日志使用 `composer-final3-*` 和 `composer-android-final3-*`。

中间失败与修正均保留日志：新媒体行最初被旧解码规则拒绝，改为只允许无意图的 draft/mediaRoot/mediaChunk；两处测试未等持久化完成，改等实际完成状态；页面测试中的截图/关库在虚拟时钟挂起，调整测试异步边界后通过。初轮分析/格式错误已修正，误触的无关格式变更已恢复。最终三项宿主命令在最后源码修改后执行，输入摘要一致。Android首次离线缺 AGP8.13.1 Maven依赖，仅向本任务缓存补齐；既有 AGP/Kotlin弃用警告未借机升级认证工具链。

## 后续两项

1. 在独立联合装配分支固定本轮前端与后端d893378，合并双方交接，准备自有 C/V Gate、迁移0014、受限授权/完整图片校验器及合成数据，补真实客户端→C进程→SQL的九图、补传/退出/恢复/取消与访问失效证据。继续正常分支操作，不直接推 main；生产存储、配额和缩略图成本仍沿后端待决定项。
2. 新窗口验 Android API29+ 实际选图权限/原字节、九图/动画/EXIF、杀进程和磁盘不足、发布返回与未知核对、原图保存/失效、总内存/流量。iOS原始资源适配与完整平台验收、评论/私信页面另列，不把组件旧S18证据当作本轮业务通过。

本轮按授权正常提交/推送本分支，不发布 Release、不部署、不合并 main。完整业务验收仍未通过。

原生构建的两份APK副本与本次生成的独立debug签名已在记录摘要/验签后精确清理；未安装过手机。后续设备验收须从固定源码重新构建并记录新签名，不能把已清理包当作现成可安装制品。本任务既有SDK及构建缓存保留供联合装配，其他任务资源未清理。
