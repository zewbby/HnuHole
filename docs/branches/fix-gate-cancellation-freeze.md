# Gate 取消请求导致冻结的修复

2026-10-19，状态：已通过[PR #25](https://github.com/zewbby/HnuHole/pull/25)正常 Squash 合入 main `54a6768fe607c37930959fab23c4876bb4ab531d`，未部署或发布。

用户针对 Android 集成候选期间的 `INDEPENDENT_ANCHOR_FROZEN` 事件明确要求“解决”。本次分支 `codex/fix/gate-cancellation-freeze`，基线为实际 main `65b28cafebbfe259e661553919611f287486d661`。原 APK、验收证据和私有恢复归档继续保留；不恢复旧实例、不准备 Android SDK、不重建候选、不连接手机或重复旧验收。

## 实现与证明范围

已在新建的独立 PostgreSQL16 测试库中复现两类缺陷：在线证据读取遇到请求取消时被误当成证据源失效，及锚点写入后 UPDATE/COMMIT 仍受调用方取消影响。真实可信 TLS 客户端断连可使旧代码的 C、V 冻结；锚点后的 Snapshot/CommitAuthorized × UPDATE/COMMIT × C/V 八种边界均在旧代码失败。

`Snapshot`、`RecheckForCommit`、`CommitAuthorized` 在锁内及证据读取后检查取消，最终业务回调后再检查一次；发布前取消拒绝/回滚且不改变检查点。发布开始后，仅 SQL 收尾使用 `WithoutCancel` 加独立10秒 deadline，保留原 context 值；文件锁/fsync 不属于该10秒的执行上限。真实 SQL 失败、不确定提交、锚点异常、过期、时钟回退和代次变化仍拒绝放行并要求原有显式签名恢复，不自动重开、不撤销锚点、不执行 Down、不改业务迁移或权限 SQL。

原事件缺少请求级追踪；网页处置成功与冻结相距约57ms只是相关时间线，不能据此认定网页请求就是当时触发者。此交付证明已复现的缺陷与修复，不将历史单次事件的具体请求归因改写为已确定。

## 实际验证

- 新增取消回归及既有纳秒检查点：真实 C/V SQL + race，38个测试及子项 PASS，0 FAIL/0 SKIP，含真实 TLS 断连；真实 UPDATE 执行故障仍冻结且业务写入回滚。
- 受影响后端全包 SQL/race：1108个测试及子项 PASS；4项因最小测试库缺评论 runtime 角色/DSN及诊断日志配置失败，按既有隔离 runner 补齐后仅重跑失败项，12 PASS/0 FAIL/0 SKIP。其余 38项条件测试明确 SKIP，未记通过；具体名称及原失败保留于机器记录。
- `go build -mod=readonly ./...`、`go vet -mod=readonly ./...`、CI选择4项、实际shell入口3场景、协作规则19项通过；YAML已解析。
- 独立 agent `/root/evidence_review` 只读审查无阻断；提出的旧PR head缺选择脚本问题已修复及实测。无 GitHub 成员批准，不伪造批准。

首次全套测试因最小副本扁平复制而缺仓库级夹具，被停止并保留失败记录；修正仓库布局后重跑。首次 TLS 夹具仍处于 break-glass，因此未复现；切换实际在线检查点并推进时钟后旧代码稳定复现。上述试验不记 PASS，不删除原记录。

## CI与复现

复用 `services/api/authlab/run-isolated.sh`，仅补齐已有评论测试所需的一次性 runtime 角色/DSN。新增 Authorization Gate 产品 CI 做 build、全后端真实 SQL/race 和 vet。Android prerelease 的精确 Gate-only allowlist 让本次改动不重建 APK、不重复旧恢复/部署演练；其他产品、迁移或工作流改动仍走原流程，手动候选触发也不豁免。旧PR head缺脚本时保留原流程，已有脚本出错则检查失败。

在全新、明确归属的 Linux Go1.22.2/PostgreSQL16 环境执行：

```sh
export PATH="$(pg_config --bindir):$PATH"
cd services/api
go build -mod=readonly ./...
sh authlab/run-isolated.sh
```

该 runner 创建私有 Unix socket、独立 C/V 数据库及非超级用户，设置 reset marker，结束后停止并移除自己的库。默认条件媒体、Goose、Dart/浏览器 fixture 缺失为 SKIP；不能将其记成对应业务/设备通过。不要连接未知 DSN，不能借此重启旧候选环境。定向命令、源码摘要、旧代码 FAIL 与修复后结果见[机器记录](../design/gate-cancellation-verification-20261019.json)。

## 交接边界

共享授权影响重新打开 A03/P01 及调用方宿主回归，按上述实际版本与范围关闭；不提升完整模块/生产结论。原固定 Android APK 及旧证据保留原 SHA，不能说旧后端/旧归档已包含本修复。没有部署或正式发布，没有新手机验收。真实磁盘/COMMIT故障全集、独立生产运营与原事件请求级归因仍不在此限定证明内。

交付前同步[HANDOFF](../design/HANDOFF.md)、[progress](../design/progress.md)、[模块交接](../design/module-acceptance-handoff.md)、[模块台账](../design/module-acceptance-ledger.json)与README。合并事实以后续PR/API回执为准，不为记录自身递归创建文档PR；本任务新工具/测试库收尾及保留路径写入本地最终回执。

## 已确认合并与收尾

固定送合 head `b0946e53a1b218b899506ffcaf707f273da6f42a`：8项适用检查全部 SUCCESS；candidate/rehearsal 由成功的范围检查明确 SKIP，不记作候选重建/旧演练通过。Gate真实PostgreSQL/race/build/vet、治理、受影响图片/Go/Flutter检查及协作均实际通过。独立agent对固定head及CI增量审查无阻断，无GitHub成员批准，按仓库现有规则普通合并、未绕过限制。合并树与已检head一致，见[合并回执](../design/gate-cancellation-main-merge-20261019.json)。

本任务新建的PostgreSQL已停止，独立Go工具/缓存/源码副本及测试库已清理；原始测试事件、失败历史、历史只读摘录及每成员摘要读回验证的私有证据归档保留。原APK与旧私有恢复归档重新核对摘要保持一致，见[清理/保留回执](../design/gate-cancellation-cleanup-20261019.json)。Windows交付目录保留源码bundle、证据和运行说明；本需求结束，不追新main，不重启旧环境或重复验收。
