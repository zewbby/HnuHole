# F4 主 App 集成执行计划

## 2026-10-13 当前接续（下方早期计划与未提交状态为历史）

固定认证d859cb05c772cdf8d8b75e439a2bfedf0414dd46已按用户新指令整合；整合前20文件保存提交7452dadefb52e7b695cdd1079d21083fcb6cae02已正常推送。当前联合主机七stage、mobile320及原生构建PASS，单台Android验收用户明确延期，所有设备用例NOT_RUN；第二台Android、iOS和生产不纳入本轮通过。最终443项源码指纹599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7及命令/失败修复/复验条件详见[20261013联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)、[整合差异](community-flutter-f4-auth-integration-diff-20261012.md)和[设备清单](community-single-android-acceptance-20261013.md)。旧“不得提交/未指定认证/20未提交”的指令与结果仅适用其原日期；本轮用户授权正常提交推送本分支，禁止强推、main合并、Release发布与生产部署。F1–F3不重新开发。

## 2026-10-12 本轮执行边界与收尾

本轮以实际起始 `4d58116bdde2c1d2d406b965590bc1625a5c7955` 的独立clone接续，改动仅未提交；用户明确禁止本轮提交／推送／合并／部署，覆盖下方历史步骤5。F1–F3页面不重做、不扩业务。详情见 [当前验证报告](community-flutter-f4-validation-report-20261012.md) 和 [机器记录](community-flutter-f4-validation-20261012.json)。

posts-privileges先复现社区授权遗漏，获用户明确确认后仅在本任务SQL源码补入固定514a944文字授权29行。最后修改后六stage全部重跑PASS：全mobile311、R05、本轮F4主机8项、6包server/race、真实受限权限PostSchema9顶层及4生命周期、最终vet；新SDK／缓存／fresh一次性库隔离与最终指纹已核对。授权前FAIL保留历史，旧证据不计本轮；当前host scoped PASS，F4最终BLOCKED_DEPENDENCY等待最终认证SHA，不提交／合并／推送／部署。

认证已提交候选及精确SHA详见 [整合差异清单](community-flutter-f4-auth-integration-diff-20261012.md)，尚无明确最终整合SHA。本轮只比较已提交快照，未合并认证、未复制脏工作树；设备／iOS和实际部署权限／升级／运营不借主机handler结果验收。

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
