# FEED-INTERACTIONS-01

- 2026-10-20，分支 `feat/feed-interactions`，基于最新远端 main `f3454d1` 的独立 worktree，用户指定分支名。
- 状态：SCOPED_LOCAL_PASS，已提交[PR #29](https://github.com/zewbby/HnuHole/pull/29)；实现提交 `97e7c8b7ed4fa6e5a6d35d201c0366707932c3bd`，后续交接引用提交不改变被测产品输入。合并已获授权，最终head CI完成前不合并，未部署。
- 范围：新版列表的帖子点赞、收藏、评论数接口；复用现有评论统计，不改评论业务或既有 feed DTO，不扩展收藏列表、消息通知或热度算法。
- 规则：按登录账号保存点赞／收藏，无身份选择或发言绑定；允许自赞；公开聚合数量，仅向本人返回本账号状态，无参与者或身份关联 API。
- 完成标准：幂等设置与批量查询、匿名及账号隔离、0020空库／升级及最小权限／关闭清理、真实 SQL/race/TLS、Go和完整OpenAPI、前端接线与模块交接、最终head CI后PR合并。独立成员批准状态如实记录，不伪造批准。

## 实现与接线

新增 `POST /api/v1/feed/interactions` 按页批量读取1至50个唯一帖子ID；`GET /api/v1/posts/<id>/interactions` 单帖核对；`PUT /like`、`PUT /favorite` 设置期望布尔状态。保留已有严格 FeedPost 与旧接口的精确字段，按postId合并摘要，不要求升级旧解析器。新表仅存账号赞／藏事实及可信收藏时间；统计没有另建评论计数。

评论数共用 `readVisibleCommentCounts`，与既有context／主评论页一致，包含有效主评论和楼中楼，隐藏或删除整楼即排除。不新增评论业务、收藏列表、删除占位管理、通知或热度。原会话要求ACTIVE；待注销会话即时失效，沿既有401，不增加读写例外。

前端按[完整契约](../design/feed-backend-contract.md#点赞收藏与评论数接线)独立接线：批量摘要、账号隔离、串行写入期望状态、未知先核对、迟到读取围栏、成功采用服务端完整结果。正式Flutter接线、设备和生产NOT_RUN。

## 验证与交接

Go全包test/build/vet、11份完整OpenAPI、旧14操作契约、19项协作工具及4项合成验证器测试PASS。真实SQL/race/TLS **50顶层／108含子项PASS，0 FAIL／0 SKIP**；空库、0018／0019升级、最小权限、关闭清理、会话／Gate、旧feed分页与过滤、受影响文字及单图评论回归通过。

源码／测试／迁移、命令、输入摘要、原始失败及最终日志位置见[机器记录](../design/feed-interactions-verification-20261020.json)。B03／B06本范围增加证据，A03／A08／B07／B10及C/V隔离、原真实浏览回归保留各自范围，不提升完整模块。最终PR head的远端CI和合并回执以PR为准。

审查为同一代理技术复核；独立同事／GitHub成员批准尚无，不伪造批准。按用户明确授权，在全部适用检查通过且无技术阻断后提交PR并合并，不部署或操作生产迁移。

远端首次 `d77ee09` 的Feed backend媒体可用性检查失败：setup-python解释器不适合验证器的最小子进程环境。已复用仓库图片CI的系统Python私有venv／不可写helper策略并补最小环境probe，不放宽验证器、不改业务或测试输入。失败run及修复见机器记录；以修复后最终head全部检查为准。
