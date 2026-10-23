# 帖子图片媒体契约与实现交接（2026-10-15）

> **2026-10-23 thumbnail-v1扩展（`fix/mobile-navigation-refresh`，未合并／未部署）：**下方v1三份原图来源继续作为无协商头时的兼容契约。新客户端在清单和feed GET发送 `X-Post-Preview: thumbnail-v1`；启用新校验器的后端将thumbnail改为受保护 `/thumbnail`、`image/webp`、`maxByteLength<=524288`，不再声称衍生图有预先确定的byteLength。full／original保持原字节。缩略图为EXIF归正、最长边640px的静态首帧，客户端标注动图；feed可同时返回有序imageSizes预留布局。两个读取入口均需当前Bearer／C最终Gate，编码完成后再次检查帖子与会话。无新SQL迁移或磁盘缓存；部署需同步可信helper、其SHA-256和runtime重启。新客户端兼容旧清单及缺少尺寸的旧feed。详细资源上限、测试、候选包和未验范围见[本轮任务](../branches/fix-mobile-navigation-refresh.md)。

本任务只实现帖子图片服务端；评论与私信只登记复用边界。独立分支 `codex/post-image-media`，目录 `E:/Hnuhole-post-image-media-20261015/repo`，实际起点 `e0c128033682923d519ea99546d72503b085a99e`。没有合并前端、社区或 main。只读核对的前端提交是 `a696742f943c1cfe6a5005024dccaf40be752d8f`，其组件来源 `bd7458ad94b7f9aea377ef060acf1316a6cfc6de`；前端后续交付仍由该分支提供固定提交。本文件不是完整 App 或生产验收声明。

## 基础设施盘点与选择

现有 `Community.ExecutePostCommand` 持久化任务、不可变标题/正文、身份/通道绑定和幂等回执；`withPostSession` 检查账号锁、会话状态/代次/截止和最终 C Safety Gate；worker 与账号关闭/处罚共享最终事务。既有 PostDetail/PostApi 是纯文字，之前没有媒体端点、上传器、对象存储或媒体域名。评论/私信业务未实现。

本分支新增迁移 `0014_post_images.sql` 和真实 PostgreSQL `bytea` 存储，不是内存或本地文件存储替身。原字节、校验元数据、上传权限摘要和帖子绑定在同一私有 C 数据库。没有引入公开桶、签名读 URL、CDN、图片 URL 猜测或长期公开缓存。库的访问、磁盘/备份加密和保留治理仍由部署方案负责；删除 SQL 行中 payload 不代表物理磁盘/WAL/备份立即擦除。

这是显式启用的开发装配：现有 runtime 仍仅支持 `environment=dev`。没有配置 `postImages` 时不启用媒体上传/读取；旧文字命令摘要、响应和通道保持原规则。迁移与授权脚本**不自动运行**。现有文字 grants 仅补媒体表 SELECT，供新迁移的完整性触发器使用；媒体 INSERT/精确列 UPDATE 另由 `infra/postgres/grant-post-images.sql` 显式授予 C runtime。business、recovery 和 V 不得读图片。

## 受理、补传与公开

1. 宿主在自己控制的持久草稿中保留原图与顺序，先读取实际字节与尺寸、计算 SHA-256，再调用已有 CREATE 或 RETRY。标题仍为手写且最多 15 字素；正文最多 3000 字素；正文可为空但必须有图片。最多 9 张。
2. CREATE/RETRY 请求新增可选 `images` 数组，每项严格包含 `mediaId`、`sha256`、`byteLength`、`mimeType`、`width`、`height`。`mediaId` 是客户端生成的规范非零 UUID，同一清单不重复；数组位置即 0 起图片顺序。禁止文件名/路径/账号/通道等额外字段。空数组等同旧文字意图。
3. 非空清单使用新摘要域，下节给出精确帧。受理事务同时固定完整清单与 imageCount，并为每项生成随机、不可变的 `contentVersionId`。202 仅表示任务受理，不是公开。内容修改必须走现有明确失败后的 RETRY（新尝试版本）；身份、通道和 postId/taskId 继续由旧任务固定，不能改归属。未知结果先核对原 command/task；不能重发新身份。
4. 宿主 `GET /api/v1/me/post-tasks/{taskId}/attempts/{version}/images` 读取有序上传状态。它仅对当前任务所有者可见，返回该尝试选择清单和 `uploaded`；不含读写能力。只对缺失/明确失败项申请 `POST .../images/{mediaId}/upload-grant`，空 body，无 Idempotency-Key。
5. grant 返回 32 字节随机 base64url `uploadToken`，数据库只存摘要；单项最多 15 分钟，且不超过受理后 24 小时上传截止。新 grant 仅替换该项旧 grant。宿主通过 `PUT .../images/{mediaId}/bytes` 上传二进制，`Authorization: Upload <uploadToken>`、准确的图片 Content-Type；不同时传 Bearer。能力只属于 task/version/item，不允许读、改字节清单或改身份/通道。退出/会话接替不倒销已授权任务的单项原字节补传；没有 grant 的后续新授权请求须重新登录原账号。
6. 逐项检查长度、SHA-256、真实格式/编码尺寸、EXIF 显示方向和全部动画帧；子进程完成验证后，在最终 Gate 事务内再次检查账号/处罚/身份、stop generation、任务版本/状态、grant 与可信截止，再写入原字节。校验失败返回 422，校验器不可用返回 503；均不影响其他项。相同 grant+原定字节在任务仍 ACCEPTED 时重复 PUT 为幂等 204；若已公开，核对任务状态，不重新发布。
7. worker 在最终 Gate 事务内核对图片总数、顺序、全部 verified 状态，以及库中每项长度和 SHA-256，再与帖子公开/尝试 PUBLISHED 同事务提交。数据库延迟约束也拒绝缺图公开。不完整上传不会阻塞其他已就绪或纯文字帖子。缺图尝试到受理后 24 小时仍未齐全，worker 使用最终可信时间标记原 `PUBLICATION_FAILED`；已齐全的已授权任务不因处理延迟自动取消。
8. 取消、明确失败和删帖会撤销权限并将 SQL payload 置空，保留不可变墓碑；注销/禁言/封禁的 stop generation 使后续上传立即失效，worker 物化终态后清理。身份删除沿既有同事务 hook 终止未公开任务。已公开内容继续遵守旧作者占位/删除规则。宿主原草稿不由服务端清理；失败/取消后的本机原图恢复归宿主持久层负责。

## 命令摘要精确帧

无图片沿用原 `HNUHOLE/POST-COMMAND/V1\0` 帧，已有黄金向量不变。有图片先生成旧 CREATE/RETRY 字段帧，然后拼接：

```text
UTF8("HNUHOLE/POST-MEDIA-COMMAND/V1") || 0x00 || 原文字命令完整帧
|| uint8(imageCount)
|| 按数组顺序逐项(
     UUID原始16字节(mediaId)
     || uint32BE(64) || ASCII(sha256小写hex)
     || uint32BE(UTF8长度(mimeType)) || UTF8(mimeType)
     || uint32BE(byteLength) || uint32BE(width) || uint32BE(height))
```

外部 requestDigest 为上述全部字节的 SHA-256 小写 hex；服务端存用途隔离的 HMAC fingerprint。RETRY 原帧绑定 taskId 和 uint64BE(expectedAttemptVersion)，不接收新身份或通道。新清单顺序、大小、散列、格式或尺寸任一改变都会改变摘要。客户端必须在落盘待发意图时固定同一清单；seal 使用同一 requestDigest。

## 读取契约与前端映射

当前会话的宿主用 Bearer 调用 `GET /api/v1/posts/{postId}/images`。返回严格对象：`postId`、有序 `images`、`accessValidUntil`。已删除/未公开帖子统一 404。即使 URL 已知，每次读清单或字节仍需当前会话与最终 C Gate 授权；Upload 能力不能读。资源状态检查与删帖串行。

每张图片包含 `mediaId`、随机稳定 `contentVersionId`、0 起 `position`、编码 `width/height`、按 EXIF 方向的 `pixelWidth/pixelHeight`、`frames`、`animated`、`saveAllowed`，以及 `thumbnail/full/original` 三份来源对象（`path/mimeType/byteLength`）。**v1 的三份来源明确指向相同的完整原字节端点**：`/api/v1/posts/{postId}/images/{contentVersionId}/original`。当前没有缩小后的衍生缩略图，不承诺节省流量；UI 仍用固定预览框 cover，查看时用完整原比例。GIF/WebP 不截首帧、不转 GIF、不降质。

当前帖子规则允许主动保存，因此 `saveAllowed=true`；宿主仍必须按字段执行。所有响应 `Cache-Control:no-store`，原图额外 `nosniff`、attachment，无 ETag、304 或 Range 公共缓存路径。端点不重定向、不返回 token URL。group 租约至多 60 秒且不晚于当前会话截止；这是客户端持有字节的**最长离线授权窗口**，不是实时撤销推送。宿主看到注销/切账号/冻结/权限失败/删帖事件须立即撤销；没有事件时到期撤销，重新授权必须创建新 group，不能把同一个已撤销 group 改回 true。

给前端提交 a696742 的直接映射：

| 媒体字段/动作 | 现有前端接口 |
| --- | --- |
| 调用当前 C origin 的受保护清单 | `PostImagesLoader(postId)` 的宿主实现 |
| 响应 postId、0–8 position 顺序、唯一 contentVersionId | 构造 `PostImages(postId, images, accessGranted)` 前严格核对 |
| thumbnail 路径经宿主认证读取的原字节 | `PostImage.thumbnail = MemoryImage(bytes)`；不用带 Bearer 的 NetworkImage |
| contentVersionId | `ViewerItem.id`；换内容换 ID，不以数组下标当 ID |
| full 经过宿主授权的完整原字节 | `ViewerItem.loadSource -> ViewerSource(provider:MemoryImage(bytes), pixelSize:Size(pixelWidth,pixelHeight))` |
| original 经过宿主再次授权的原字节 | `resolveOriginal -> ViewerOriginal.bytes(bytes, ViewerOriginalFormat.gif/webp/png/jpeg)` |
| saveAllowed | 原样传入 `ViewerItem.saveAllowed` |
| 身份/环境代次、失效事件、租约计时器 | 宿主持有并终止 `accessGranted`；在每次 await 后检查代次，拒绝迟到响应 |

宿主认证只保留在调用层闭包/transport 内，不能把账号、Bearer、密码、恢复材料放进图片组件、provider header、文件名或异常。宿主必须限制只接受上述当前 C origin 的相对路径，禁止凭返回 path 去任意域下载。临时字节只存在受控内存，不建长期公开私有图片缓存；撤销/账号切换时清空本层字节引用并逐个 evict 对应 MemoryImage，包括原预览 provider，禁止全局清其他会话缓存。保存仍使用既有 packages/image_viewer 的 gal 原格式流程与 Android 默认开启策略。

**接线前必须解决的接口差异：**a696742 的 PostApi/本地任务仍只有文字字段；本分支为 PostDetail 与 OwnTaskContent 增加正数时才出现的 `imageCount`，且有图片时允许空 body。宿主严格 DTO 白名单/正文校验须接纳该字段；不能沿旧文字 requestDigest 发送含图清单。查看器 loader 对接可独立做，但图片选择、持久草稿/原图、上传任务恢复与发帖 UI 不因 loader 存在而已实现。本分支不修改 apps/mobile，也不声称这些宿主动作已交付。接线由前端会话使用双方固定 SHA 后执行，不自动合并。

## 格式、资源与校验器

允许 JPEG、PNG、GIF、WebP；APNG/其他格式明确拒绝。单张最大 10 MiB、单边 16384、静态像素 12×1024²；动画最多 120 帧、画布 1024²、画布像素×帧数 16×1024²、单帧 15 秒、单周期 60 秒。与 a696742 复用组件默认上限对齐，未放大手机解码预算。短/零延时按至少 100ms 保守计算校验预算，不改原文件。真实 Flutter 解码、方向和播放仍须前端/设备独立验证。

服务端使用固定 Pillow 12.3.0 自带 libwebp 的既有解码实现，helper 逐帧读取、PNG CRC verify、容器结束/长度检查；没有新写/分叉图片解码器、查看器或原生桥。独立 Linux 子进程每次限地址空间 384MiB、CPU 5 秒、墙钟 8 秒、禁止写文件/core，最多两个并发；不继承账号/服务端环境变量，不访问图片 URL，不输出原图或异常正文。Python/依赖由部署方放在可信只读位置；启动校验依赖、helper SHA-256，每次调用复查脚本摘要。当前工作目录、第三方包和解释器的供应链/权限由部署安全策略进一步固定，脚本摘要不是通用 OS 沙箱证明。

依赖依据：[Pillow 12.3.0 官方发布说明](https://pillow.readthedocs.io/en/stable/releasenotes/12.3.0.html)、[Pillow 安全说明](https://pillow.readthedocs.io/en/stable/handbook/security.html)。未因验证动画另引入 Go WebP 解码分叉；[Go WebP 官方包](https://pkg.go.dev/golang.org/x/image/webp)与现有系统 Go 版本的适配/安全升级不在本次隐式操作中。

示例配置片段（不含真实域名、密钥或 DSN）：

```json
{"postImages":{"pythonFile":"/task-owned/python/bin/python","validatorFile":"/trusted/source/services/api/media/validate_image.py","validatorSHA256":"<该文件实际sha256>"}}
```

先按现有方式显式配置 posts 三用途密钥与 C Gate，正式执行迁移 0014 及两个授权脚本后，才能启用此片段。代码不安装 Python、不迁移数据库、不恢复 Gate、不自动部署。

## 评论与私信的未来复用

- 评论最多一图；未来复用随机版本 ID、原字节验证、宿主认证读取和终止租约。目标评论/帖子/身份、失败保文字与手动移除图片发送、离帖清未发输入须由评论模块实现，不能复用帖子任务假装评论。
- 私信每组最多九图；先执行首次联系只允许一条文字、对方回复后才开放图片，再固定身份对/组序/单项任务。部分成功项保留、失败项原位重试。待收投递副本必须保留到接收方真实本地持久确认，不能套用帖子 24 小时截止/公开读取或平台长期历史缓存。
- 两模块均没有在本分支新增页面、数据库任务或 HTTP 路由；B07/B09 维持未实现。

## 独立复验与证据边界

使用 `services/api/authlab/run-post-images-isolated.sh`；它只创建新的私有 socket PostgreSQL 集群、专属角色及空 C/V 测试库，不接收外部 DSN、不操作已有服务、ADB/手机/SDK。先自行准备专属 Python venv（仅 requirements.txt 小型 wheel），生成合成图片：

```sh
export PATH=/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/usr/bin:/bin
export GOTOOLCHAIN=local GOPATH=/task-owned/go-mod GOMODCACHE=/task-owned/go-mod/pkg/mod
export GOCACHE=/task-owned/go-cache GOTMPDIR=/task-owned/tmp TMPDIR=/task-owned/tmp
export POST_MEDIA_PYTHON=/task-owned/python/bin/python POST_MEDIA_FIXTURES=/task-owned/fixtures
# 在独立Linux源码目录执行；helper须是可信不可被其他用户写入的文件。
$POST_MEDIA_PYTHON -B media/test_validator.py --fixtures "$POST_MEDIA_FIXTURES"
$POST_MEDIA_PYTHON -B media/test_validator.py -v
sh authlab/run-post-images-isolated.sh
go vet ./...
```

聚焦测试含完整字节子进程、真实 PostgreSQL 约束/受限运行角色、实际 loopback TLS HTTP handler 与 SQL；HTTP strictness 用宿主替身，单独标注，不能代证服务端装配或手机。raw migration fixture 不等于正式 Goose 前向升级；本轮没有实际 cmd 进程装配、部署、Flutter/Android/iOS/图库验收。Android 只设计 API29+；没有运行 Flutter，不存在共享 bin/cache 的写入证明或可宣称的 Flutter PASS。既有 TalkBack 证据保留原组件版本，不重跑、不借为当前业务通过。

## 生产前待决定/补证

1. 私有 PostgreSQL 原字节存储是否可作为首期生产方案，或改用独立私有对象存储；后者需确定供应商/区域、独立凭据、原图保护读取与删除/备份策略，再做可靠适配，不能替换成公开桶。当前实现的字节存储是真实 SQL，未称其生产容量/SLA已验。
2. 账号/总存储配额、上传频率/带宽和资源预算；目前继承旧命令预算与最多128个未完任务上限，单图10MiB不是账号总容量保证。压测、并发验证器队列/内存、WAL/备份删除、孤儿数据与安全审核尚待专门验收。
3. 是否接受 v1 用完整原图作为缩略来源的流量成本；若需衍生缩略图，必须明确动画预览/尺寸/保真要求并新增版本，不能静默取首帧或改原图。
4. C HTTPS 域名/部署与校验器供应链、文件权限、依赖安全更新、正式 Goose 升级/回滚前向修复；生产安全 Gate 与独立运维证据继续按原认证台账。

这些是后续生产方案选择，不阻止审查本次源码/契约/隔离测试，也不是部署授权请求。最新执行结果与清理范围见 [脱敏证据](post-image-media-verification-20261015.json)。
