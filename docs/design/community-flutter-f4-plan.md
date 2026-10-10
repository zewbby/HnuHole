# F4 主 App 集成执行计划

日期：2026-10-10（Asia/Shanghai）。分支 `codex/community-flutter-pages`；前端基线 `d44c5ebe83b5fb20727f3d0d040d7ff93364a265`。

当前认证远端仍是 `0eff47a21cd4f4ab1636b4468f7d5df9769a264f`，非 iOS 收口存在未提交变更且继续验收中。后端固定提交 `514a944560988e3d8d599e6f9fe9d5d99fe07f88`。F4 最终认证整合依赖尚未满足；不复制正在变化的认证或 T4 工作树，不用旧版本证据代验当前代码。

本轮先完成独立子范围：

1. 从已固定后端提交选择服务源码、正式迁移及必要 runner，逐文件记录来源；保持 F3 页面／存储修复和正式图稿。
2. 生产 main 与集成测试共用同一 `HnuholeApp` 根路由，实际操作登录、通道树、列表／编辑／确认、我的／设置／身份管理、详情／删除和重开后的恢复。
3. 新写真实 HTTPS C/V handler→独立一次性 PostgreSQL→当前 Dart HTTP adapter/controller→文件 SQLite→生产根页面的测试。冻结／恢复、旧会话及账号切换、原命令丢响应核对作为共享边界；主机 vault 使用文件替身，原生／设备与实际 cmd 最小权限证明另列。
4. 执行当前 mobile 静态分析及全量回归、Go／SQL／race／vet及原认证真实链，记录源码快照、实际命令和最终结果。
5. 更新四份交接、保留历史版本、清理本任务确属的 Linux 资源，普通提交并推送已有前端分支。

终验待办：认证会话提供稳定最终提交后，对照 main／auth flows／session／HTTP／closure／native／manifest／迁移差异，整合所需源码并重新打开共享回归；固定该候选后重跑本轮真实链，FP14 才可收口。F5 原生平台、跨进程、备份、真实 IME／读屏／设备、iOS 仍独立登记。无新产品问题，无需重复确认既定页面。

## 2026-10-10 执行与换机状态

固定后端接入、主导航修复及8项主机真实链已完成并PASS，源码68d35af。最终认证候选仍BLOCKED_DEPENDENCY。早期Go/SQL/race/vet与mobile308保留范围；最终checks/R05/vet未完成，WSL系统命令段错误及emergency_ro故障单列。已更新四份交接与机器记录，按用户要求提交并普通推送对应分支。PG/进程结束；任务缓存删除errno30、仍需本机恢复文件系统后清理。详情见community-flutter-f4-machine-handoff.md。
