# AC04 匿名基础链路覆盖与回归报告

日期：2026-10-05（Asia/Shanghai）。分支：`codex/auth-privacy-handoff`。基线：`cbc99b010ba23bba42f76e2523269e3952b14392`，本轮修改尚未提交。任务依据见[三步任务单](auth-privacy-regression-plan.md)，最终源码摘要、真实命令与结果见[机器记录](../../services/api/authlab/privacy-regression-verification.json)。

## 新增范围

只扩展 R05 集成测试和私有 fixture，以及 R03 失败时的脱敏 Gate 状态诊断；应用逻辑、公开 API 和迁移未变。新增 `integration/verifier_gate_https_scenarios.dart`，修改 `integration/auth_public_https_postgres_test.dart` 与 `identity_https_scenarios.dart`；SQL 私有断言位于 `internal/authprivacyhttp/mobile_closure_postgres_test.go`，控制端装配于 `mobile_client_postgres_test.go`。路径分别相对 `apps/mobile` 与 `services/api`。

- V 冻结时，已登录 C 会话仍有效；V 的新 OTP 请求、确认和原结果读取全部拒绝。显式恢复后，同一旧确认仍返回 `OTP_EXPIRED`；新代 OTP 可重新确认，C 会话不被 V 恢复撤销。
- 身份成功创建的原键从既有丢响应核对流程保留到关闭测试。SQL 捕获两项活动身份、一项已删除墓碑及累计状态／永久回执；七天缓冲和主动登录取消均逐字段保持不变。
- 正式关闭在同一终态时间擦除原昵称、头像和改名时间；已删除墓碑、创建归属、累计状态和永久回执不变。重复终结没有第二次提交；旧 Bearer 的本人列表和原结果访问均拒绝。
- V 持久释放后，同一精确测试邮箱经新 OTP 和 bootstrap 注册新 C 账号。新账号初始零身份／零累计次数／无冷却，旧身份回执查询为 NOT_FOUND，首次建立独立原始身份。SQL 再确认旧墓碑和永久历史未改写。

R05 控制端只在测试 TLS 服务中以随机能力保护，快照不返回给 Dart，绝不作为产品接口。签名测试时钟的七天推进用于到期 fixture；不会改写数据库期限或强行打开 Gate。V 恢复后的新 OTP 使用不同测试地址，以免绕过旧地址的独立重发冷却。

## 关键场景映射

以下是覆盖映射，执行结果及版本以机器记录为准；历史记录保留原版本，不换绑本轮摘要。

| 不变量 | SQL／HTTP 入口 | 实际进程 R03／真实客户端 R05 |
| --- | --- | --- |
| V 回退阈值、重启与独立性 | `TestVerifierGateRollbackBoundaryRestartAndIndependencePostgres`；`TestVerifierGateIsIndependentOfCommunityFreeze` | R03 `verifier-stage/frozen/recovered`；R05 `verifyVerifierGateHttpsScenarios` |
| V 旧快照不得重开 | `TestVerifierGateCompleteGateSnapshotCannotReopenPostgres` | R03 实际 V schema dump／restore，保留较新库外锚点 |
| 最终授权、锁等待及外部迟到结果 | `TestVerifierGateFinalCommitAndPendingGenerationPostgres`；`TestVerifierAddressLockWaitCannotCrossRecoveryGeneration`；`TestVerifierLateSignatureCannotCrossFreezeOrRecovery`；SMTP／退役迟到测试 | R03 原代 OTP 恢复围栏；R05 原确认拒绝。锁等待及迟到细节由 SQL 故障测试证明 |
| 独立连接池与受限恢复 | `TestVerifierGateRefreshWithSingleConnectionBusinessPoolPostgres`；`TestVerifierGateRestrictedRecoveryAndReplayPostgres` | R03 V3→4、恢复角色与普通运行角色权限矩阵 |
| 身份 CRUD、未知结果与会话接替 | `TestRealHTTPSIdentityManagementPostgres` | R03 `identities/restart/frozen/recovered`；R05 创建／改名／删除丢响应、重建客户端、接替后原键核对及拒绝回执 |
| 正式关闭零／一／三身份与取消 | `TestIdentityFormalClosureZeroOneAndThreePostgres`；`TestIdentityClosureCancellationPreservesProfilesPostgres` | R03 `closure`；R05 缓冲／取消 SQL 原样比较与正式资料擦除 |
| 关闭并发、冻结、故障回滚 | `TestIdentityMutationAndClosureSerializePostgres`；`TestIdentityClosureWaiterRejectsFreezeAndOldGenerationPostgres`；`TestIdentityClosureSQLFaultRollsBackEveryBoundaryPostgres`；`TestIdentityClosureMultipleWorkersCommitOncePostgres` | 并发及故障由 SQL 测试证明；R05 重复终结检查不冒充并发证据 |
| C11→12 升级修复与保持历史 | `TestIdentityClosureMigrationRepairsLegacyProfilesPostgres`；`TestIdentityClosureMigrationRejectsInsufficientTrustedWatermarkPostgres` | R03 非空升级、旧墓碑／回执／通道逐字段保持 |
| 同邮箱新账号独立历史 | `TestIdentityClosedAccountReturnHasIndependentHistoryPostgres` | R03 `identityClosureReturn`；R05 完整新 OTP→注册→本人列表／原键隔离→首次创建及旧历史复核 |
| C/V 数据和身份归属隔离 | `TestPrivacySchemaPartyBoundaryPostgres`；`TestPrivacySeededPartyRowsPostgres`；`TestRealHTTPSIdentityPrivacyIsAccountScopedPostgres` | R03 角色 SQL；R05 新账号旧回执 NOT_FOUND |
| 诊断不反射秘密 | `TestPrivacyDatabaseDiagnosticsPostgres`；`TestPrivacyBoundaryErrorsNeverEchoSensitiveInputs`；runtime 诊断测试 | R03 PG／应用日志 canary 与 unsafe 设置启动拒绝；Flutter 既有负向测试 |
| 独立注销占位契约 | `TestInactiveIdentityProjectionHasNoAccountLinks` | R03 纯投影字段／token 比较；公共帖子／聊天消费者尚未实现，不能视为已集成 |

测试文件分别见 `services/api/internal/authprivacy/{verifier_gate_test,verifier_gate_business_test,community_identity_closure_test,identity_closure_migration_test,privacy_boundary_postgres_test}.go`、`services/api/internal/authprivacyhttp/{identity_endpoints_test,identity_privacy_postgres_test,endtoend_postgres_test}.go`，以及实际 `services/api/cmd/runtimeprobe/{verifier_gate,identities,identity_closure}.go`。

## 执行与限制

本轮 R01 全量 Go／一次性 SQL／race 和 R02 vet、R03 实际非 owner C/V 进程、R05 真实 Dart→HTTPS handler→一次性 C/V PostgreSQL 均 PASS，退出0；Flutter 分析无问题，现有179项测试通过。检查分别覆盖最终对应源码：Go／Dart测试文件不再变更，新增R03停机时序与脱敏诊断在最终实际进程复验执行。Windows原始摘要与WSL LF摘要分别保留，逐文件仅允许CRLF→LF，协议向量原字节不变。

R01 不配置 Flutter 时主动跳过 opt-in 的 `TestMobileClientHTTPSPostgres`，由 R05 单独取得证据。R03 是真实非 owner C/V cmd＋HTTPS/mTLS＋正式迁移；R05 是真实客户端＋handler＋SQL，使用内存 vault。不能将两者相加宣称完整物理 App→实际 cmd→原生存储通过。

AC05 的 Android/iOS 原生、系统 Passkey、物理设备与 B02 输入法／无障碍／身份草稿设备矩阵本轮未执行；iOS 与实际 ceremony 仍缺相应设备／配置。B05–B11 公共消费者、本地聊天／备注／搜索清理未实现，X06/X07 只证明当前关闭及投影函数边界。P02–P06 生产分权、灾备、侧信道校准、供应商／代理／备份日志与人类独立审计仍未取得本轮证据。B02 整模块保持 BLOCKED。

## 失败及复验

准备脚本首次读取台账使用 Windows 默认编码，改为 UTF-8 后继续；该次未进入应用测试。Flutter 初轮静态检查发现测试过早 return，移至全部既有断言后，最终分析与客户端回归通过。R03 初轮源码归档权限为 0600，使 Docker 内初始化脚本不可读；修复本轮归档权限，保留 0700 临时材料父目录。第二轮 R03 在重启后返回 503，定位与最终结果见机器记录，不把部分阶段通过改成完整 R03 PASS。

第二次与第三次未协调授权停机的R03分别出现C或V重启后503；第三次固定类别诊断为C OPEN、V FROZEN／INDEPENDENT_ANCHOR_FROZEN。源码显示SIGTERM可取消库外锚点先写后的SQL事务，因此此时安全冻结符合既定机制。普通重启保留会话的测试改为先取得两侧一次性Gate行锁，等当前授权提交后再停机，新授权阻塞于锚点更新之前并随停机取消。最终完整R03退出0，保留原恢复／旧快照／代次断言。没有自动恢复或放宽授权检查；这只证明受控普通重启，不承诺任意中断均保留会话。失败诊断只输出Gate状态、代次与白名单类别，其他原因统一OPERATOR_OR_OTHER。

## 最终交接与清理

交接一致性／覆盖映射检查和git diff --check通过。221个被测文件逐一核对，WSL副本只采用CRLF→LF，协议向量保持原字节；小型记录保留raw和Linux摘要及实际runner阶段。全部本轮唯一Docker项目／卷／网络、runner进程和一次性库已清理；带归属标记的WSL源码／依赖／build/pub缓存／私钥／日志目录已删除。Windows准备归档及脚本于收尾删除，现成SDK／AVD／Docker镜像保留。源码、测试和脱敏证据留在工作区，未提交／推送／部署。
