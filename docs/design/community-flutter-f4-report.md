# F4 主 App 集成与换机交接报告

2026-10-10，分支 `codex/community-flutter-pages`；源码提交 `68d35af745098be0ed52d0d448f290795665afa1`。**固定基线的主机真实链已通过，F4 最终认证联合验收仍为 BLOCKED_DEPENDENCY。** 当前后端固定514a944、认证基线0eff47a；认证会话仍在运行且没有最终提交，不导入其未提交代码或后端未提交T4证据。

本轮从后端提交逐文件引入40份服务源码、测试、迁移0013和runner，来源见[版本锁](community-flutter-f4-lock.json)。F3页面／持久状态保留。生产 `main()` 与测试共用公开 `HnuholeApp` 根路由；设置新增“账号与安全”入口，解决个人入口改为“我的”后原登录／退出／注销页面不可达的问题。F1正式图片未修改，无重新设计页面。

## 实际执行结果

| 检查 | 结果 | 证明范围 |
|---|---|---|
| F4真实主App链 | PASS | 实际生产根路由＋HTTP adapter/controller＋TLS C/V handler／Gate＋独立PG＋文件SQLite，两个主机Flutter进程 |
| Go／SQL／race／vet | PASS | 6个测试包；导入的生产服务源码／迁移此后未变；当时的新F4 fixture尚未完成最后修改，不代证最终fixture的vet |
| 早期mobile分析／全量测试 | PASS（早期快照） | 0问题、308项、20文件；在账号与安全入口补齐之前，不代证最终快照的全量回归 |
| 最终mobile分析／全量测试 | BLOCKED | WSL realpath／ln段错误，后续写日志errno30只读；未启动测试 |
| 最终R05认证回归／vet | NOT_RUN | 串行检查在上述环境故障处停止，没有完成证据 |
| F4最终认证候选／FP14 | BLOCKED | 未取得最终认证提交；主机通过不等于完整App或联合终验 |
| F5原生／平台／物理UX | NOT_RUN | 未构建本轮APK、未执行native7／设备／iOS／系统Passkey／IME／读屏／备份 |

完整测试入口在[runner](../../tools/run-community-flutter-f4-linux.sh)，源码为[Dart根页面测试](../../apps/mobile/integration/f4_main_https_postgres_test.dart)与[Go真实链fixture](../../services/api/internal/authprivacyhttp/f4_main_mobile_postgres_test.go)。[脱敏结果](community-flutter-f4-test-summary.json)保存8项实际检查、计数和简短runner输出；原始大日志不入仓，早期machine日志在交接时因WSL I/O错误无法重新读取计数。

| 场景 | 结果 | 实際验证 | 模块 |
|---|---|---|---|
| F4-H01 | PASS | 生产 HnuholeApp 根页面：真实注册前置后退出，实际登录表单登录并进入通道树 | A02、A03 |
| F4-H02 | PASS | 我的→设置→账号与安全／身份管理，既有账号页面与原身份可达 | B02、B10、A08 |
| F4-H03 | PASS | 编辑→确认→原身份→提交回包丢失→原通道；原 CREATE commandId/digest 落盘，未知查询不重发 | A06、A12、B05 |
| F4-H04 | PASS | 两个独立主机 Flutter 进程，恢复同一 SQLite 草稿和原命令；核对服务端任务及固定身份 | A12、N01、B02、B05、B10 |
| F4-H05 | PASS | 真实 worker 公开后列表／我的→正文详情；DELETE 回包丢失，核对同一原命令，写 DELETED 后清正文并返回 | B03、B06、B10 |
| F4-H06 | PASS | C 冻结停访问；代次恢复拒绝旧会话，明确重登恢复 A 草稿；新设备接替后 retry 拒绝旧会话 | A03、A06、A07、A12 |
| F4-H07 | PASS | 退出 A 后真实注册 B；B 不继承 A 的草稿、待核对项或删除事实；CREATE／DELETE 都只发一次 | A12、N01、B10 |
| F4-H08 | PASS | 生产注销表单申请 B 注销；可信测试时间前进七天，真实 worker 闭号；SQLite 关闭墓碑拒重开 B，保留 A 草稿 | A08、A12、N01、B02、B10 |

数据库独立断言：posts=1、deletedPosts=1、identity bindings=1、publication tasks=1；实际CREATE=1、DELETE=1、提交成功后丢回包=2、原命令查询丢响应=2。第一阶段退出后启动第二个独立Flutter主机进程，仍核对同一commandId/digest，未靠标题或正文归并未知请求。

C冻结时保留令牌但停止内容访问；恢复会推进安全代次、拒绝旧会话，明确重登后才恢复原账号草稿。新设备接替通过实际会话核对拒绝旧会话。删除丢响应后，自动核对原命令，SQLite中DELETED回执先持久化，详情正文清除并回“我的”。B闭号由正式worker执行，可信fixture时钟前进七天，不直接改SQL截止；CLOSED_RELEASE_PENDING回调使B库保留加密关闭墓碑且拒绝重开，A草稿仍存在。

主机auth/key vault为文件替身；上述闭号检查没有证明原生key／数据库文件删除、跨engine锁或跨原生进程。测试用pollInterval=0进行显式及回包触发核对，没有验证生产自动轮询间隔；挂载生产根路由没有执行原生`main()`插件启动。真实handler与fresh数据库也不代证实际部署cmd最小角色、升级、运营安全或生产批准。X06/X07只覆盖本文字／闭号部分，不登记整场景PASS。

## 精确版本与剩余工作

最终279份源码／测试／配置文本摘要 `e42251dfc18b1f718cac19e5b86b5aa8c36ce08b019a9c6c7466a0682f411174`，逐文件与提交`68d35af745098be0ed52d0d448f290795665afa1`核验一致；[指纹](community-flutter-f4-source-fingerprint.json)包含平台源码，但包含文件不代表平台运行过。最终实际主链的main、settings和两份fixture与Linux被测副本一致；早期308及全量Go的后续fixture差异已分开注明。[机器记录](community-flutter-f4-verification.json)与台账currentCommunityFlutterF4为当前入口，F3及认证旧SHA证据继续保留。

下一台机器先按[换机交接](community-flutter-f4-machine-handoff.md)拉对应分支，复跑最终checks、auth-regression、vet；取得认证最终SHA后对照main／AuthFlows／session／HTTP／closure／native／manifest／迁移，整合并重跑本真实链。F5平台证据另行补齐，图片／评论／收藏等仍未开发，不记为只差测试。

## 本机清理

一次性PG与本任务进程均已结束（owned数据库目录0、进程0），Windows本工作树没有本任务.dart_tool／build／__pycache__缓存。Linux任务目录`/tmp/hnuhole-community-flutter-f4-01a11f1a-20261010`删除尝试BLOCKED：WSL根ext4显示emergency_ro，owner/绝对路径/无进程校验后的shutil.rmtree返回errno30。缓存尚在本机，不能登记已删；需要文件系统恢复可写后只清理该目录。未停止其他会话、未全局prune、未删除SDK／AVD／共享模块缓存或用户数据。已导出小型证据，下一台机器不需要复制本机缓存。
