# B07 评论与回复：首阶段独立核心交付

2026-10-18，Asia/Shanghai。[PR #17](https://github.com/zewbby/HnuHole/pull/17)，分支 `codex/feat/comments-replies`，**draft／未合并／未发布**。源码与全部实测命令固定于[机器证据](comments-core-verification-20261018.json)；被测实现 `cd45a893e2aade2a079ee302743f622ee111649e`，22 项源码／测试／契约／CI 输入指纹 `746d3cc21138a00ac6009a3f2e67ccddb10889d524274e10c073be9e14496f45`。

这是可运行的独立核心与宿主测试交付，**不是 Android 评论功能完成**。当前 App 尚未装配评论；评论 SQL、HTTP、worker、真实加密 journal、页面、单图上传读取及统一失败通知均未实现或接线。完整 B07 为 BLOCKED，`COMMENT-FAIL-ENTRY-01` 为 NOT_RUN_NOT_CONNECTED。

## 实现与范围

| 入口 | 已实现并实际测试的范围 |
| --- | --- |
| `services/api/internal/comments/`（B07-CORE-01） | 原文／单图校验、受理身份绑定纯规则、不可变原身份／帖／楼／具体目标、四态与版本裁决、失败重试／放弃、身份删除不覆写成功；安全公开投影与稳定排序快照 |
| `apps/mobile/lib/src/comments/`（B07-CLIENT-01） | 同帖临时输入、收起保留／离帖清空、含文字或图片换对象确认、先 journal 后请求、未知／确定未受理区分、原任务恢复接口、账号代次隔离、身份删除去材料、明确失败的私有投影 |
| Go/Dart `CommentProtocol` 与 `packages/comment-protocol-vectors/v1.json`（B07-CODEC-01） | 五种命令精确帧、评论专属域、12 份独立生成黄金向量；原始 Unicode／换行、单图 presence、全部不可变字段与版本绑定 |
| `packages/openapi/comment-api.yaml`、`tools/check-comment-contract.py`（B07-CONTRACT-01） | 计划端点的闭合 DTO、本人／公开隔离、非零规范命令键、版本上限、未知和权威未受理、NOT_CONNECTED 通知投影及负向 fixture |

业务规则和接线参数完整见[契约](comments-replies-contract.md)。Go 模型不是持久服务；Dart API/journal 只有宿主接口及明确命名的测试适配器，不提供长期评论草稿或第二套通知中心。公开／本人 wire DTO 仍需显式生产适配，不能直接序列化现有领域结构假称 HTTP 实现。

## 实际验证

| 命令／检查 | 结果及证明范围 |
| --- | --- |
| `go test -mod=readonly -race -count=1 -json ./...`（`services/api`） | PASS_HOST_ONLY；747 个含子项通过事件，266 个需环境的跳过事件；无外部 DSN，不计真实 SQL |
| `go test -mod=readonly -race -count=1 -cover ./internal/comments` | PASS；50 个含子项通过事件，覆盖率 91.0% |
| `go build -mod=readonly ./...`、`go vet -mod=readonly ./...` | PASS |
| `flutter pub get --enforce-lockfile`（`apps/mobile`，pub.dev） | PASS；原锁保留，实际 `vm_service` 15.3.0 |
| `flutter analyze --no-pub` | PASS；0 问题 |
| `flutter test --no-pub --reporter json test` | PASS；全部 445 项可见测试（原有 395＋评论核心 45＋协议 5），无排除／跳过 |
| `flutter build bundle --debug --no-pub` | PASS；Flutter bundle，不是评论 APK／Android 原生验收 |
| `python -X utf8 -B packages/openapi/check-specs.py` | PASS；全仓 7 份完整 OpenAPI 校验 |
| `python -X utf8 -B tools/check-comment-contract.py` | PASS；语义与完整 OpenAPI |
| `python -X utf8 -B -m unittest discover -s tools/tests -v` | 207 项，204 PASS、3 个平台 SKIP；评论契约含 16 组测试 |
| 独立 Python `uuid/struct/hashlib` 重拼帧 | 12/12 PASS；未调用 Go/Dart codec，不写文件 |

工具固定 Go 1.22.2、Flutter 3.47.5、Dart 3.13.4、Python 3.12.14、PyYAML 6.0.1、openapi-spec-validator 0.9.0。SDK 与 pub/Go 缓存为本任务独立副本；Go 密钥夹具与临时文件位于本任务 Linux 文件系统目录。日志及 SHA-256 见机器证据，原始文件位于 `E:/HnuHole-comments-replies-20261018/runtime/logs/`。本轮没有新数据库、监听端口、手机或 ADB 操作。

首轮 Go 宿主测试因 Windows 挂载盘 TMPDIR 的 Linux 权限不符合密钥检查而失败，原日志保留；改用专属 Linux 临时目录后完整重跑通过。Flutter 首次普通 pub 解析曾因镜像源切换升级测试依赖，该预跑不作最终证据；恢复原锁并严格解析后重跑全部测试。没有修改鉴权、TLS、Gate 或产品依赖来绕过失败。

## 独立审查

Go 领域与精确 codec、Dart 状态核心分别由不同 agent 实现，在独立工作树提交后由 root 正常 cherry-pick。另一位未编写这些代码的 agent 复核 Go／Dart／文档／CI，并独立重建黄金向量；后端作者也独立复核客户端，root 审查规范与最终整合差异。不是 GitHub 成员批准，不伪造第二账号。

审查发现并修复：并发复用命令键、journal 部分安装／加载竞态、旧回执回退终态、删身份残留其他任务材料、放弃恢复时迟到材料复活、删除置前回复后自动晋升隐藏项、明确未受理不能收敛、更高尝试版本与本地材料错配，以及回复对象旧确认覆盖最后选择。对应回归已进入 45 项客户端核心测试。最后源码复核无未解决核心阻断。

当前保守边界：被拒绝 mutation 若读到更高版本 ACCEPTED/FAILED，而当前 API 尚无该版本权威材料，保持 UNKNOWN，不用本地旧原文冒充新失败内容；未来生产适配器必须取回并对齐实际 owner payload 后再恢复编辑。更高版本真实 PUBLISHED/ABANDONED 仅用于收敛终态与清私有材料。

## 主线、迁移与下一阶段

开工已核对仓库、干净工作区、分支和远端。原创建基线 `8fa9cbc`；实时 PR #13 已合入 main，正常合并 main `986477b`，整合提交 `79213db`。只处理 README 分支索引冲突，保留主线图片、认证和无障碍成果。没有复制其他任务未提交代码或整树覆盖。

main 当前只到迁移 0014；治理分支最终核对为 `60e5df4`，新增已提交通知契约；已完整读取并在本任务契约记录 ownerIdentityId→identityId、IDENTITY 范围、LOCAL_TASK 来源和 COMMENT_FAILURE/taskId 路由映射。实际 provider 的事件包装／已读／时间／去重及未受理失败入口尚未实现，没有已合入的 0015 或真实通知接线。未添加假 0015、未运行缺失／乱序迁移、未合并整条未完成治理分支。评论暂定 0016，需在治理基础实际合入后重新核对编号与 main。

后续必须完成，不能用本阶段测试替代：

1. 正常整合治理基础 main；定稿 0016 与最小 grants，覆盖现有帖内身份绑定 FK 的非作者评论适配、C 最终事务、命令持久回执／seal、worker 和账号／身份／帖子生命周期。
2. 在独立一次性库运行正式空库迁移及 `0014→0015→0016` 前向升级、受限角色、真实 C/V/SQL/HTTPS、并发／迟到／处罚／注销／删除回归；按影响重开 A00/A01/A02/A03/A06/A08/A10/A12/A13 与 X06/X07。
3. 装配同环境／账号隔离的原生加密 journal、原图材料原子保存／清理及跨进程恢复，再接帖子独立滚动、输入／身份管理往返、定位／本人删除与单图 UI。重开恢复涉及 N01，不能由内存适配器代证。
4. 按已核对的[任务2契约](https://github.com/zewbby/HnuHole/blob/60e5df46545180c1c7017b6aee3b417af471ccbe/docs/design/report-notification-contract.md)装配真实 provider，补事件包装／单条已读／时间与去重，覆盖实际顶部失败提示、原身份详情、重试／放弃及解决后移除；未接线前 `COMMENT-FAIL-ENTRY-01` 和完整 B07 不得 PASS。
5. 固定含实际评论功能的源码与 APK 后统一安排 Android 设备窗口。跨设备 Passkey NI-X02 和 iOS 继续延期；生产／发布独立，当前无合并或发布事实。

GitHub 最终 head 的检查以 PR #17 当前 head 为准，记录在 PR 描述和任务 runtime 的 `final-head-check.json`；不为把提交自己的 SHA 写回自己而递归追加文档提交。
