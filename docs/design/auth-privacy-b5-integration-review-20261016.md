# B5 主线增量独立审查

日期：2026-10-16（Asia/Shanghai）。审查基线为 `main` 的 `b164762b8cd58da592bf645cc4e2ada738bb79ec`；对象为 `codex/fix/b5-main-integration` 候选差异。审查人是独立只读 agent `/root/b5_integration_review`，主任务完成集成和验证。该记录不是 GitHub 成员批准。

审查覆盖 `AuthFlows` 的持久化后状态展示、epoch/closureId 围栏、旧账号业务清理失败与重试；图片 API 关闭时的四列擦除授权、启动核验、权限审计及真实 SQL 负向场景；三个 B5 夹具的当前根组件适配。

发现两个当前候选夹具仍调用 `AuthCrypto.randomEncoded(24)`，会在原生恢复成功后触发现有长度守卫。device 和 Bitwarden 夹具均改为 32 字节，审查者复核三份候选夹具已无该错误调用。历史报告、三份机器记录和原 checker 的字节未改。

其余已审查代码无阻断发现。真实 SQL 验证应执行 `run-post-schema-isolated.sh` 和 `run-post-images-isolated.sh`，确保新测试取得私有一次性数据库的受限角色 DSN；无 DSN 的跳过不能计作通过。

相对主线没有修改 Android/Passkey/vault 原生代码；此次增量不强制重新执行完整双机验收。合并条件是受影响 Flutter、实际 PostgreSQL、构建及协作检查通过。候选原生设备验收仍为 `NOT_RUN`；原 B5 的 24/24 仅证明原版本，不扩张为新 APK、完整产品或生产批准。
