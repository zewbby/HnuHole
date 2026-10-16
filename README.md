# 海南大学树洞

面向海南大学校内人员的封闭树洞社区，围绕“想说就说”设计；首版以吐槽、避雷、安利、互助、搭子、科技、情感七个通道组织内容，保护校内用户个人信息并提供匿名表达空间。

当前已从产品设计阶段进入工程方案阶段，首版面向 iOS 与 Android。工程基线已确定为 Flutter/Dart 移动端、Go 服务端和模块化单体后端；仓库采用 monorepo，Go HTTP、PostgreSQL、REST/OpenAPI、服务端会话、移动端本地存储、CI/测试与部署基线已记录，具体云厂商、推送供应商和发布流程仍在后续决策中。

## 当前开发切片

任务 1 正在实现登录后的通道目录与二维入口树。未登录只显示无节点树外壳；登录后通过 `GET /api/v1/channels` 加载七个通道，初始关注五个，另外两个通过拖动探索。服务端代码位于 `services/api`，OpenAPI 源文件位于 `packages/openapi/channel-api.yaml`，本地 PostgreSQL/Mailpit 配置位于 `infra`。

当前机器未安装 Go/Flutter SDK，且 Docker 引擎未启动；本轮代码尚未运行测试。换到具备 SDK 的环境后，先执行 API 依赖整理、迁移、格式化和测试，再运行 Flutter 分析与客户端测试。

## 新会话接续

继续本项目讨论时先读[接续说明](docs/design/HANDOFF.md)，再按其中索引读取当前模块；不要从历史对话猜测最新规则。

## 设计入口

[产品设计目录](docs/design/README.md)是当前规则的统一入口，按模块维护：

- [账号](docs/design/modules/accounts.md) · [帖内身份](docs/design/modules/identity.md)
- [入口与导航](docs/design/modules/navigation.md) · [标签与屏蔽](docs/design/modules/tags.md)
- [新建帖子](docs/design/modules/post-composer.md) · [帖子详情](docs/design/modules/post-detail.md) · [评论与回复](docs/design/modules/comments.md)
- [消息中心](docs/design/modules/messages.md) · [私信与会话](docs/design/modules/messaging.md)
- [个人内容与设置](docs/design/modules/personal.md) · [内容管理](docs/design/modules/moderation.md)

当前规则只修改所属模块，本页不重复维护规则清单。

## 图稿与讨论记录

- [帖子详情图稿档案](docs/design/post-detail-dark-final.md)
- [回复输入 PNG](UI产品图/回复输入状态.png)
- [消息首页正常状态 v1 · 已确认](UI产品图/消息首页-正常状态-v1.png)
- [身份弹框 v3 PNG · 旧稿](UI产品图/首次发送-身份选择-v3.png)
- [历史讨论目录](docs/discussions/README.md)

按用户要求优先交付 PNG，设计图的确认范围在各模块内说明。
