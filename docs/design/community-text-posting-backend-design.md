# 帖子发布事务与恢复设计

维护日期：2026-10-18。本文保留文字帖交付中仍适用的维护知识，并明确主线的图片扩展。
[原始设计、计划及 T1–T3 证据](../archive/community-text-posting-20261008/README.md)按固定旧版本归档。
当前操作形状见 [API 说明](community-text-posting-api.md)和 [OpenAPI](../../packages/openapi/post-api.yaml)。

## 两个成功时点

账号私人控制权 → 本人有效身份 → 固定帖内身份 → 帖子。一个账号在一个帖子中的身份绑定不因重试而改变。

1. **受理事务**：最终 C Gate／会话和归属检查后，原子建立命令回执、帖子内部占位、固定身份、任务及第一次尝试。
   202／ACCEPTED 表示受理，此时内容尚未公开。
2. **公开事务**：worker 不依赖原 Bearer；它重新检查 Gate、账号／身份权限、发布停止代次及内容状态，
   再提交公开内容和 PUBLISHED 事实。有图片时还要求清单及原字节全部验证完成。

列表和详情读取公开事实，不将客户端成功提示或历史命令回执当作公开依据。
核心实现位于 [community_posts.go](../../services/api/internal/authprivacy/community_posts.go)、
[生命周期事务](../../services/api/internal/authprivacy/community_posts_lifecycle.go)及
[读取实现](../../services/api/internal/authprivacy/community_posts_read.go)。

## 未知结果、封印和重试

- GET 查不到命令只返回 UNKNOWN_NOT_OBSERVED；迟到请求仍可能受理，不能直接换身份另发。
- 显式 seal 与原命令在同一账号域串行。原事实不存在时持久写入 NOT_ACCEPTED；事实已存在时返回原结果。
  已受理任务通过 cancel 裁决，seal 不推翻已有事实。
- 命令回执保持原结果，任务及尝试拥有当前状态。取消与公开竞争以最终事务先后决定，不能把已公开内容改画成取消。
- 只有明确失败且允许重试的任务能创建新尝试；版本、身份和通道受约束。未知结果不能直接 retry。
- 隐藏失败入口不删除命令墓碑或释放旧命令键，避免迟到请求再次产生效果。

## 停止代次与账号生命周期

发布停止代次与会话代次独立。申请注销、生效处罚等停止事件与账号状态在同一权威事务中推进，
旧尝试捕获的代次不匹配时永久停止；撤销注销或处罚到期不会自动复活旧尝试。
退出、会话接替、密码重设和临时 Gate 冻结不等于取消已经受理的任务。
删身份、删帖、封禁和关闭账号继续执行各自的内容与图片生命周期清理；图片 API 关闭也不能跳过已有图片的擦除。
最后一点的主线修复和回归见 [B5 整合报告](auth-privacy-b5-main-integration-report.md)。

## 文字、图片与隐私边界

- 原始文字按 Unicode 16 扩展字素簇计数；摘要保留原 Unicode 和 CRLF／LF 差异。
- 无图片和空图片清单保留旧文字帧。非空清单使用独立媒体域，并绑定每项 ID、摘要、格式、长度、尺寸和顺序。
  [文字向量](../../packages/post-protocol-vectors/post-command-v1.json)与
  [图片向量](../../packages/post-protocol-vectors/media-v1.json)分别固定字节兼容性。
- 图片授权、补传、私有原字节存储及全部验证后公开的细则见 [媒体契约](post-image-media-contract.md)。
  当前扩展不允许重试更换身份或通道，也不改变既有文字幂等域。
- 公开内容只展示所选公开身份，不输出私人账号、邮箱、其他面具关联或作者控制权。
  作者能力、任务、草稿和受保护媒体分别执行当前会话与资源归属检查。

## 存储与维护入口

[迁移 0013](../../services/api/migrations/0013_community_text_posts.sql)持久保存文字任务、尝试、回执、身份绑定及停止事实；
[迁移 0014](../../services/api/migrations/0014_post_images.sql)扩展图片清单、字节及生命周期。
权限使用 [C 授权脚本](../../infra/postgres/grant-community.sql)和
[图片精确授权](../../infra/postgres/grant-post-images.sql)，不授予恢复／业务角色任意访问正文或媒体的权限。
客户端 [PostController](../../apps/mobile/lib/src/posts/post_controller.dart)与
[PostStore](../../apps/mobile/lib/src/storage/post_store.dart)保存草稿及原操作恢复事实，按账号隔离。

自动检查入口见 [API 说明](community-text-posting-api.md)。真实 SQL、C/V、设备和生产的证明范围依各专项报告，
本文整理维护知识，不修改模块验收状态、不重写历史结果，也不声明当前完整 App 已通过。
