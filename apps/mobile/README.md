# Hnuhole Mobile

移动端认证状态机已接到原有 Material 入口树：旧号私有用户名／密码登录、V 校邮资格与 C 持钥注册、恢复码单次展示与隐藏后全量确认、独立恢复码重设、七天注销申请／状态核对、单设备接替提示、服务端权威会话恢复、活跃近到期续期及持久登出待办。

启动先处理登出标记并移除对应社区 Bearer；独立撤销待办异步重试，不拖住后来新会话。每次恢复均查 C；本地过期时间仅用于续期调度。目录 200 必须包含完整七通道与严格 UTC `Session-Expires-At`；同 token／请求版本仍有效时，先将权威截止写入 AuthStore 并核对落盘，才发布节点。同 token 的并发迟到响应不能缩短已持久截止。登录、恢复、退出及新目录请求立即使旧请求失效；截止缺失／非法、目录不全或持久写失败均不发布节点。401 清对应令牌／节点；503、网络故障和公共边界 400／403／429 保留安全持久令牌、隐藏节点并提供前台重试。不存在后台定时保活。所有秘密与未决能力由本地 [auth_vault](../../packages/auth_vault/README.md) 保存，无普通文件降级。新恢复码／密码只留短期内存，不缓存原码、不自动复制。

配置固定且不同的 C/V HTTPS origin（不得带路径、查询或响应指定的跳转地址）：

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=AUTH_COMMUNITY_BASE_URL=https://community.example.org --dart-define=AUTH_VERIFIER_BASE_URL=https://verifier.example.org
```

默认地址为 `.invalid`，需要运行实际隔离 C/V 公共服务。客户端验证固定帧／本地槽位和公钥绑定；权威严格票据验签由 C 执行，TLS 使用系统证书信任，不提供绕过按钮。每组固定端点使用独立安全存储 namespace／scope。

核心状态机的历史验证见[原报告](../../docs/design/auth-privacy-mobile-auth-validation-report.md)。2026-10-01 历史联调完成真实客户端→隔离 C/V HTTPS／PostgreSQL 的认证请求，含未知结果、Gate 冻结／签名恢复和注销释放 ACK，当时目录使用 503 占位。本次 fixture 已换为真实 `HttpChannelRepository`、受信 TLS 和 C Gate 目录，断言七节点及 AuthStore 持久截止；此更新尚需在有 Flutter 的电脑实际复验。运行 `services/api/authlab/run-mobile-isolated.sh`，需先 `flutter pub get` 并将 `AUTHLAB_MOBILE_FLUTTER` 设为 Flutter 可执行路径。普通 `flutter test` 不会执行这条联调。

Android vault instrumentation 在历史版本曾编译／组装测试库 APK，当前完整app和设备故障验收待执行；受限 `android/prebuilt-debug.init.gradle` 不代证新增 Passkey 插件。iOS vault标记、串行和SwiftPM/CocoaPods同源打包已接入，当前完整Xcode／Keychain／插件链接未验。正式签名与关联域未配置。

## 设备与恢复凭据管理（2026-10-02）

“我的”进入当前／最近接替设备与恢复凭据页：主动退出、密码复验后恢复码轮换、一次展示／隐藏／完整确认、可选Passkey绑定和两步移除。登录页可发现Passkey证明接现有密码重设，不自动登录。权威截止先落盘；最终提交前保存原意图与键，未知结果只读核对，不保存密码、新码或系统证明。

原生桥、平台关联生成及真机矩阵见 [auth_passkey](../../packages/auth_passkey/README.md)。用户尚无RP／签名／Team配置，系统Passkey真机闭环待验。新增真实vault／跨进程入口为 `integration_test/auth_security_device_test.dart`，iOS RunnerTests直接测试Keychain；步骤见[本片报告](../../docs/design/auth-privacy-device-credentials-passkey-validation-report.md)和[模块交接](../../docs/design/module-acceptance-handoff.md)。本机共享Swift codec／marker、关联生成器及轻量检查通过；Go／Flutter／SQL／完整app与设备未验。

用户要求大型临时运行时、专用缓存和生成 APK 收尾删除，只保留源码和小型证据。另一台电脑的完整复验步骤及平台边界见[本轮交付报告](../../docs/design/auth-privacy-mobile-native-integration-validation-report.md)。

## 独立图片查看接入钩子（2026-10-15）

`HnuholeApp.loadPostImages` 可注入 `PostImagesLoader`，现有通道与“我的”进入详情都会传递它。返回 `PostImages(postId, images, accessGranted)`：每张 `PostImage` 分别提供缩略 provider 和完整查看的 `ViewerItem`，后者负责稳定内容 ID、真实尺寸、完整原文件 resolver 与保存许可。媒体层先授权，不把账号/Bearer交给查看器；撤销时通知 `accessGranted=false`，其 notifier由媒体层拥有，不能因旧异步完成恢复旧页面。

启动现已装配 `PostMediaRepository` 和 `HttpPostApi` 的受保护读取，只对详情声明 `imageCount>0` 的帖子加载图片。读取契约固定于后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587`；两个分支未自动合并或部署。每次请求使用现有宿主授权与持久续期；图片 provider 仅持内存字节，不带 Bearer header。清单校验帖子/内容ID/顺序、格式/尺寸/字节预算及最长60秒租约；超时、退出、切账号、删帖或访问拒绝终止当前组，逐个 evict 自有 provider。到期需主动重新读取，旧组不复活。

`PostImage.deferred` 延迟读取预览，预览/完整查看共用同一租约内存来源，保存另发受保护原文件请求。`PostImages.onRelease` 在详情卸载、换组或丢弃迟到结果时释放租约；只有该媒体层拥有 notifier。v1 后端把完整原字节用作预览，尚无节省流量的衍生缩略图；当前字节读取并发上限2，九图/跨页整体内存预算仍须专门验证。

Android发帖已增加官方 `image_picker` 原格式选图（不传缩放/质量选项）、九图等尺寸预览、移除/长按排序与读屏移动动作、原比例查看，以及正文为空的含图发布。图片进入按环境/账号隔离的业务SQLite，原字节按256KiB分块认证加密，和草稿元数据同事务写入；不持久保存picker路径或上传能力。同机重开恢复已保存的原图/顺序；未完成的外部选图会提示重新选择，不把无账号绑定的系统lost-data附到后来账号。

启动使用 `HttpPostUploadApi`：media-v1黄金摘要、CREATE/RETRY清单、受保护逐项状态与短期grant、仅 `Upload` 能力的原字节PUT均已接入。发布意图先落盘再返回原通道；未知结果核对原命令，失败时只补尚未上传的项。进度及补传入口在“我的”对应任务页。明确失败后可修改文字/图片重试，原身份与通道固定；确认取消保留图片草稿，成功/明确放弃后按引用清理本机原图。

锁定的iOS选图实现会经过UIImage重编码，GIF时序/循环也可能改变，原字节契约不满足，因此原生iOS选图入口先挂起，未引入fork或新原生桥。iOS默认相册保存仍关闭。评论/私信未开发；完整C进程/SQL装配及真实系统选图、主App平台验收分别登记，宿主替身不能代证。见[上传前端报告](../../docs/design/post-image-composer-report.md)、[读取接线报告](../../docs/design/image-viewer-post-media-read-report.md)；历史钩子阶段见[阶段1报告](../../docs/design/image-viewer-business-stage1-report.md)。
