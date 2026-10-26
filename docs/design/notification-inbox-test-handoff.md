# 通知、共享身份与导航测试交接

2026-10-27，任务 `NOTIFICATION-INBOX-01`，B02／B07／B08／B09／B10。范围和授权见[任务](../branches/feat-notification-inbox.md)。

## 源码及检查入口

| 范围 | 源码与检查 |
| --- | --- |
| 四等宽分类、大字、滑动、只读筛选、身份迟到围栏、精确版本已读、媒体撤权 | `system_notifications/inbox_screen.dart`、`inbox_models.dart`、`notification_thumbnail.dart`、`notification_inbox_test.dart` |
| 当前身份在通知／私信／个人页／新发帖同步；身份删除、账号退出、管理页取消 | `identity/active_identity_controller.dart`、`active_identity_test.dart`、`personal_profile_test.dart`、`governance_test.dart` |
| 五项导航在全部主模块保留，＋进入真实发帖，只有沉浸首页隐藏 | `navigation/feed_chrome.dart`、`active_identity_test.dart`、`feed_scroll_refresh_test.dart`、`app_navigation_test.dart` |
| 实际发表才投递、幂等、匿名赞聚合与取消、所见版本、账号／身份归属、删除预览、Gate | `authprivacy/community_inbox*_test.go` |
| HTTPS严格边界、真实会话／SQL、禁用mentions字段和目标接口 | `authprivacyhttp/inbox_postgres_test.go`、`inbox_endpoints_test.go` |
| 空库到28、27到28，旧数据保留，Down拒绝回退收件事实 | `community_inbox_migration_test.go` |

真实 SQL 仅在自己的 WSL Linux 文件系统快照运行，使用一次性私有 socket 数据库；最小运行角色、实际 C/V HTTPS 与旧评论回归分别记账。初版提及代码已撤回，旧评论协议／editor／journal没有产品差异。测试替身不代证设备，APK安装不代证完整真机联调。最终 PASS／SKIP／远端 CI 状态见[机器记录](notification-inbox-verification-20261026.json)。

```sh
# 仓库根，Go1.22.2 / PostgreSQL16 / Goose3.22.1（Linux）
COMMENT_TEST_PATTERN='^(TestNotificationInbox|TestInboxRoutesAndDisabledMentionsBoundary|TestCommentText)' PGPORT=55583 sh services/api/authlab/run-comment-text-isolated.sh
cd services/api
go test -mod=readonly -race ./internal/comments
go test -mod=readonly -race ./internal/authprivacyhttp -run '^(TestInboxRoutesAndDisabledMentionsBoundary|TestCommentTextNullableBoundary|TestStrictJSON|TestStrictObject)'
go build -mod=readonly ./...
go vet -mod=readonly ./...
```

```sh
# apps/mobile，Flutter3.47.5，锁文件不变
flutter analyze --no-pub
flutter test --no-pub
# 仓库根，Python3.12，packages/openapi/requirements-check.txt
python tools/check-notification-contract.py
python -X utf8 packages/openapi/check-specs.py
```

CI已扩展 `comments-core.yml`（客户端、原生构建、契约）和 `comments-backend-text.yml`（真实SQL／HTTPS／最小角色）。完整私信HTTP包的旧测试会改全局`time.Local`，曾与TLS清理发生race；本任务未修改该旧测试，不宣称其完整race稳定通过，受影响的通知／评论限定race单独检查。历史设备探针与编译Dart探针缺失时明确SKIP，不作为接口通过证据。

完整本机日志位于 `E:/Hnuhole-env/notification-inbox-20261026/`，不入库。用户已授权PR推送合并和最新主线构建；仍需核对实际CI和合并SHA，不预记成功、不冒充独立成员批准；现有正式签名／公开生产环境的配置不由测试凭据替代。
