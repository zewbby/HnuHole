# Android 集成候选

2026-10-19，Asia/Shanghai。状态：固定候选及必要新增限定验收完成；待本任务 PR 审查/检查后合并，未部署或正式发布。

唯一交付为固定源码、配置、后端、迁移和签名的可用 Android 集成候选，包含现有图文、完整评论和评论举报审核/通知/申诉。交付 [PR #23](https://github.com/zewbby/HnuHole/pull/23)，分支 `codex/ci/android-integration-candidate`，独立工作目录 `E:/HnuHole-android-integration-20261019/repo`。

依赖已实际合入：完整评论 [#19](https://github.com/zewbby/HnuHole/pull/19)、评论举报 [#22](https://github.com/zewbby/HnuHole/pull/22)。产品基线固定为 `1a810944787eacb66e2115e1ce77de08190c366a`，正式 C 迁移0001..0018 / V0001..0004；停止追新 main。

原预发布 [#16](https://github.com/zewbby/HnuHole/pull/16) / 合并记录 [#20](https://github.com/zewbby/HnuHole/pull/20) 已完成且已清理，不恢复旧环境，不重复旧演练。本轮只在依赖齐备后准备一次独立工具和新的私有隔离实例。

## 证据继承与本轮补验

- 评论 [接通及 Android 报告](../design/comments-connected-report-20261019.md)、[机器记录](../design/comments-connected-verification-20261019.json) 的原生 journal、单图、进程恢复、失败通知/重试和系统选图结果保留原 APK 范围；不为统一 APK 重验。
- 评论举报 [报告](../design/comment-report-validation-20261019.md)、[机器记录](../design/comment-report-verification-20261019.json) 的 SQL、Dart HTTPS、网页闭环和迁移/权限证据沿用。新增必要恢复补验集中在非空评论/图片、举报/处置、通知/已读/申诉事实及应用兼容。
- 普通集成包使用真实 `lib/main.dart`，仅编译公有 loopback HTTPS 地址和开发 CA，明确独立测试签名；不包含 `COMMENT_DEVICE_FIXTURE`、账号、密码或 token。配置/签名/制品摘要和运行/安装说明随候选归档。
- 用户在候选就绪后开启实际 vivo S18 窗口，并明确授权卸载旧同包 App 及其本机数据。普通候选已实际完成回复举报→严格 TLS 网页处置→举报人/作者通知→App 申诉→独立网页复核→App 申诉通过详情和单条已读。窗口现已关闭，专用 ADB、两条 reverse 和临时 UI XML 已收回，App 保留安装；不再 ADB。
- C Gate 中途出现一次 `INDEPENDENT_ANCHOR_FROZEN`，原因未确定。使用既有签名 operator 仅恢复本任务 C，旧会话失效后人工输入合成凭据正常重登、读回结果；C/V 最终严格 HTTPS readiness 均200。保留 incident 和失败输入历史，不推断与网页申诉的因果，不宣称持续可用；后续根因分析交授权/Gate 所属模块。
- 不修改业务迁移或业务缺陷；发现业务问题交回所属模块。应用回滚与数据库兼容分别记录，不执行 Down，不把旧 binary 能启动当成新治理语义兼容。

## 结束条件与授权

固定候选可用、必要新增影响验证完成、制品与记录交付、相关 PR 按规范独立审查/检查后合并、临时资源收尾后结束。用户已授权本范围提交、推送、PR及检查通过后的合并；不部署或正式发布，不扩展 iOS、跨设备 Passkey、多机型及生产证明。

接续：[HANDOFF](../design/HANDOFF.md)、[进度](../design/progress.md)、[既有预发布复现入口](../release/android-prerelease.md)。

## 固定成果及审查

APK `4df3f7c85f6bb312fde1034d577c093136b6f0c989daeea70a65f32aa624ac0f`，版本 `0.1.0+2026101901`；测试证书 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。仅一次成功候选构建，后补交付工具守卫未改变产品输入，未重建。

新增恢复实测包含62份 C 表/sequence摘要及规范权限匹配；0018前后端实测拒绝新授权契约，不能安全回滚该旧 binary，不执行 Down。普通与 `-O` 下8项工具边界检查均通过；独立只读审查已闭环三项交付工具问题，无剩余 P1/P2，agent 审查不冒充 GitHub 成员批准。

完整摘要、工具版本、命令、incident、未验范围及归档入口见[发布记录](../release/android-integration-candidate-20261019.md)与[复现说明](../release/android-integration-reproduction-20261019.md)。构建 manifest 是构建时快照（device NOT_RUN），设备实际结果另见[设备回执](../release/android-integration-device-20261019.json)，不能改写历史。

独立[审查回执](../release/android-integration-review-20261019.json)及[保留/停止回执](../release/android-integration-retention-20261019.json)已归档；最终 CI/合并与缓存删除按实际完成后更新。
