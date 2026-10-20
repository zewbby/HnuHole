# FEED-READ-ERROR-SCOPE-01 / FA-D07

2026-10-20 送审快照，分支 `codex/fix/feed-read-errors`，基线 main `a1cb812a84ef7650b9156a6b510997df508b6c70`（[#31](https://github.com/zewbby/HnuHole/pull/31) 已于 07:09:01 UTC 合并）。本修复尚待最终 PR 检查及合并；合并事实、最终 main2010 提交与制品校验值由 PR 和不可变交付回执记录，不为记录本 PR 再递归建立文档 PR。未正式发布。

## 缺陷与修复

2008 在列表断网、原重新加载成功后，详情及返回重开仍残留“暂时无法核对结果，原操作已保留，请稍后核对。”。列表和偏好读取把局部错误写入全局命令错误，并清掉原命令的错误归属；成功重载只清局部提示。

运行改动仅 `apps/mobile/lib/src/posts/feed_controller.dart` 三处 catch：普通列表／偏好错误留在原局部重试入口，只有既有 typed Post/Auth401/503 继续交给失权处理。原 epoch、请求序号及 current 围栏保留；读取成功不清除并发真实命令错误。未修改 X 布局、Telegram 字体配色、CAS、认证策略、发帖、评论、图片或私信。

## 已完成验证与适用性

- 修复源码 `8f8ec66c6b185fdbb15fb528b164820b70fa7ec1`。25 项专项 PASS、App 全量 615 PASS、analyze 0、debug bundle PASS；旧 main 运行文件配合同一最终 25 项测试实际 17 PASS／8 FAIL，已完成后恢复修复文件。按用户收敛要求复用这些结果，不重复红绿或全量。命令入口为 `flutter test --no-pub test/feed_read_error_scope_test.dart`、`flutter test --no-pub`、`flutter analyze --no-pub`、`flutter build bundle --debug --no-pub`；日志摘要及 SHA 见机器记录。
- 新专项使用生产 Controller、原重新加载、进入／重开详情；真实 `reconcile` 先产生带归属的 CREATE 命令错误，再确认 REJECTED 才清自己的错误。覆盖并发读成功、偏好写丢响应／核对失败、三阶段 typed401/503、旧账号迟到错误及 metadata 存储失败。HTTP、PostStore、secure-vault 为替身，不代证 TLS／SQLite／真机。
- 独立 Max 静态审查无阻断，确认三处围栏、命令归属及 CI 接线；reviewer 未跑测试或操作设备／环境，agent review 不冒充 GitHub 成员批准。
- 2009 原生 Android 构建 301 tasks PASS，同签 debug／`lib/main.dart`；Android 独立核 APK 摘要、签名、打包地址及 CA，保留数据升级后完成 D07 与直接影响范围复验：列表断网原重载及偏好保存/读回双 transport 失败后原重新核对均恢复，同详情及返回重开无旧全局提示，恢复后同列表普通点赞0→1→取消0正常；无新增阻断，非全矩阵。
- Android 证据 `candidate2009-d07-targeted-summary.json`，SHA256 `745651d4a21f5d2eb3814f1dfcccbe7df40df8beae06936e24492e275ed32d5e`。详见[机器记录](../design/feed-read-errors-verification-20261020.json)；设备由 Android 会话独占操作。
- 实际渲染：[列表恢复后详情](../design/feed-interactions-ui/assets/android-2009-d07-timeline-detail.png)／[偏好恢复后详情](../design/feed-interactions-ui/assets/android-2009-d07-preferences-detail.png)。Android 批准的合成数据原 PNG，前端逐张目视并保留原 SHA。
- 对 2008 的 runtimeInputs 逐文件比较，唯一运行差异为上述 Controller。签名、公共 defines／CA、Android 配置、依赖和后端相同；环境负责人六项适用性核验 PASS，无部署或重复 SQL。2008 的丢响应、迟到写、重试、账号切换、评论与图片发布回执保留原版本；图片两帖 27 项合并 SQL PASS 不反推设备 UI。2007 媒体及旧认证结果也只保留原证明范围。

## 候选与后续门槛

2009 分支候选：`feed-ui-d07-8f8ec66-2026102009.apk`，98,804,432 bytes，APK SHA256 `3329947f0bc3c7f3c33954ed031a3f17477bc507c1e64a1b85989dab20861936`，cert SHA256 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。非最终 main 包。公共 defines SHA256 `f7d52b05297121684c89e643480ce4a5f2e0ab1b4fed165b4d6a2f1f431c7862`，CA SHA256 `57487d56e2d50327bfbf2ca9bb0db4952a050efef6c4fb85ac9990ffbf9cbda4`。

最终精确 PR HEAD 的适用 CI 必须全部通过（含 Feed UI 真实 C HTTPS／一次性 PostgreSQL 条件写与 Android 构建），核对独立审查和定点无阻断后，按用户已有授权 Ready／合并。从最终 main 重建同签 2010，比较运行输入与编译 kernel，再由 Android 安装启动、列表／详情一次冒烟；若新阻断继续修复与必要回归。最终校验值及合并回执随交付包提供。

自然 same-token 设备续期、失败 worker 重试、iOS／跨设备 Passkey、release/profile 真实 HTTPS／性能及完整生产安全验收仍 NOT_RUN；不以旧版本或宿主替身升级完整模块。前端未操作验收设备、更新共享环境或正式发布。

相关入口：[HANDOFF](../design/HANDOFF.md) · [进度](../design/progress.md) · [模块交接](../design/module-acceptance-handoff.md) · [台账](../design/module-acceptance-ledger.json) · [#31 历史](feat-feed-interactions-ui.md)。
