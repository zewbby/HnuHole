# 帖子发布 API 与客户端接入

维护日期：2026-10-18。本文从文字帖历史交付整理，适用于已接入可选图片的主线。
机器契约以 [post-api.yaml](../../packages/openapi/post-api.yaml) 为准；图片上传、受保护读取另见
[图片 API](../../packages/openapi/post-image-api.yaml)及[媒体契约](post-image-media-contract.md)。
历史 T1–T3 原文、报告和截图位于[归档索引](../archive/community-text-posting-20261008/README.md)，
其日期、源码摘要、通过及未验状态保持原版本，不代表当前 App 验收。

## 14 个基础操作

以下操作均访问固定 C HTTPS origin，要求当前 Bearer，并在最终 C Gate／会话事务内检查权限。
V 不接收帖子、账号或正文；客户端不能用 accountId／ownerId 指定归属。

| 方法与路径 | 作用 |
| --- | --- |
| PUT `/api/v1/post-commands/{commandId}` | 接受 CREATE；202 只证明任务受理，同 ID 同意图不创建第二份任务 |
| GET `/api/v1/post-commands/{commandId}` | 查询原命令事实；UNKNOWN_NOT_OBSERVED 不证明原请求未提交 |
| POST `/api/v1/post-commands/{commandId}/seal` | 原请求未受理时持久封印；已有事实不变，不用于取消已受理任务 |
| GET `/api/v1/me/post-composer-context` | 取得默认发言身份或必须设置／选择身份的状态 |
| GET `/api/v1/me/post-tasks` | 列出本人可见的处理中或失败任务 |
| GET `/api/v1/me/post-tasks/{taskId}` | 查询当前尝试、终态及可执行操作 |
| POST `/api/v1/me/post-tasks/{taskId}/cancel` | 按 expectedAttemptVersion 裁决取消；公开先赢时不能改判为取消 |
| POST `/api/v1/me/post-tasks/{taskId}/retry` | 对明确允许重试的失败任务创建新尝试；身份、通道及任务归属不变 |
| POST `/api/v1/me/post-tasks/{taskId}/hide` | 隐藏明确失败的本人入口，保留防重执行事实 |
| GET `/api/v1/channels/{channelId}/posts` | 分页读取当前可见的公开帖子卡片，不返回正文摘要 |
| GET `/api/v1/posts/{postId}` | 读取公开详情；删除／不存在统一 404，不返回作者私人账号或本人权能 |
| GET `/api/v1/me/posts` | 读取本人仍活动身份的已公开帖子 |
| GET `/api/v1/me/posts/{postId}/capabilities` | 私有作者权能；当前 canDelete=true、canEdit=false |
| POST `/api/v1/posts/{postId}/delete` | 最终权限与归属复核后的作者删除，返回原命令回执 |

取消、重试、隐藏和删除按 OpenAPI 使用 Idempotency-Key；CREATE 使用路径中的 commandId。
不同操作不能用同一账号命令键表达不同意图。请求体、字段、查询、头部、状态码与响应大小遵循机器契约，
不能把 HTTP 超时、401、503 或客户端取消解释为“原 mutation 没有发生”。

## 文字与可选图片

- 标题最多 15 个、正文最多 3000 个 Unicode 16 扩展字素簇；同时保留 4096／65536 UTF-8 字节上限。
  不 trim、不 NFC、不转换换行；拒绝非法编码和约定外控制字符，具体边界由运行时校验及共享向量定义。
- 标题必须有效。无图片时正文必须有效；有至少一张图片时正文可为空。
- CREATE／RETRY 可携带最多 9 项 `images`，每项只包含 mediaId、sha256、byteLength、mimeType、width、height。
  数组顺序是图片顺序；不得加入文件名、路径或账号选择字段。
- 不携带图片或空清单保留旧文字摘要。非空清单使用独立媒体摘要域；失败重试仍固定原身份和通道。
- 受理不代表图片已上传或帖子已公开。宿主持久保存原图及上传状态，只为明确缺失项申请授权、补传；
  全部字节完成校验后，worker 才能在最终事务公开。
- 公开列表／详情 DTO 与本人任务／能力 DTO 分开。详情的 imageCount 只表示存在受保护图片，
  不提供公开图片 URL；读取图片须走独立的当前授权链路。

## 恢复与错误处理

本机先持久保存原命令、文字、图片引用和归属，再发请求。结果未知时查询原 command/task，不能另造命令重发。
命令回执记录历史受理结果；页面还须读取任务或帖子当前状态，不能将旧 ACCEPTED 回执显示成新一次发布成功。
主动退出、换机及密码重设不自动取消已经受理的发布任务；申请注销、处罚和身份删除按
[后端事务设计](community-text-posting-backend-design.md)执行停止规则。

## 检查入口

在安装 [固定检查依赖](../../packages/openapi/requirements-check.txt)的独立环境执行：

```sh
python -X utf8 packages/openapi/check-specs.py
python -X utf8 tools/check-community-text-contract.py
python -X utf8 -m unittest discover -s tools/tests -p test_community_text_contract.py -v
```

第一条验证仓库全部 OpenAPI，后两条检查帖子静态契约及其负向回归。
这些检查不能代替真实 HTTP／SQL、Flutter、原生或设备验收；动态结果继续沿用对应版本的专项记录。
