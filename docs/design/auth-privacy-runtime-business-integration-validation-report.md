# C/V 开发服务与目录授权实施／验证记录

实施开始：2026-10-01；最近静态复验：2026-10-02（Asia/Shanghai）。**状态：T0–T6 代码与复验入口已写入工作区，编译和动态验收未完成。**本机缺少必需工具；本报告不将源码检查或历史通过记录作为本次运行证据。

## 基线与执行环境

- 分支：`codex/auth-privacy-handoff`；实际 checkout：`/Users/zewbao/Desktop/workspace/Hnuhole/remote-auth-privacy-handoff`。
- HEAD 与计划源基线均为 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`。修改未提交／推送，没有新的 commit SHA；逐文件源码摘要记录于[机器记录](../../services/api/authlab/runtime-business-integration-verification.json)，报告和机器记录本身不参加摘要，避免循环引用。
- 保留开始时的规划、HANDOFF、进度和第40轮讨论改动；未合并其他分支、未在外层父 Git 仓库实施。
- 平台：macOS 26.2（25C56），Darwin 25.2.0 arm64；Apple clang 17.0.0；Xcode 仅 CommandLineTools。Python 3.13.3；已有 Anaconda Python 3.12.7／PyYAML 6.0.1 可做 YAML 静态检查。
- `go`、`gofmt`、Docker、PostgreSQL 命令、Goose、sqlc、oapi-codegen、Flutter、Dart 不可用。Docker 的旧符号链接指向不存在的应用，不构成运行环境。CGO／race 未执行。
- 模块仍声明 Go 1.22；开发镜像固定 PG 16.6、Mailpit 1.21.8，工具锁定见[服务说明](../../services/api/README.md)。Go 1.22／PG16、Linux／WSL2 均未在本次实测；历史 Go 1.27.1／PG18.6 结果不能外推。

## T0–T6 对照

| 步骤 | 已写入的实现 | 本次证据与缺口 |
| --- | --- | --- |
| T0 | 独立 C/V 配置，私有材料文件、有界超时／worker／限流、固定 origin／证书／peer、schema／角色启动校验及负向测试；开发与平台说明 | 仅源码复核；配置负向 Go 测试、版本兼容未执行 |
| T1 | C `0003`–`0010`，V 独立 `0001`–`0003`；实验从正式 Up 段加载，删除重复 SQL；NOLOGIN owner、迁移连接、运行／恢复／业务角色；旧会话 fence，Down 拒绝事实回滚 | `0001_sessions.sql`／`0002_channels.sql`保持原文件；空库、重复、升级逐字段／UUID、原子失败、最小权限需运行实际 runner |
| T2 | `cmd/api`、`cmd/verifier`，public HTTPS／独立 internal mTLS；live／ready、信号与停止流程；`authdev init/issue/recover/freeze/watch`；两 PG＋Mailpit loopback Compose | 没有启动任何 C/V／DB／Mailpit 进程；PKI、SMTP、mTLS 正反向与证据 TTL 仍待运行 |
| T3 | 有界调度、独立 deadline、并发、退避、取消与脱敏观察；邮件摘要 QUEUED claim，DISPATCHING／UNKNOWN 不重投；outbox 持久 lease／generation／CAS，读取、签名、epoch、ACK、清理最终 Gate；退役终态写／重放和收据响应使用原请求最终 Gate；ACK 起点不重置 | 新增竞争／崩溃／晚签名／晚 ACK／冻结／清理、退役锁等待／ACK 后重签与 scheduler 测试，全部未执行；网络跨库副作用不承诺原子回滚 |
| T4 | 从 sessionView 提取最小账号→限制→会话事务；解码 token 字节 SHA；同事务读取完整 `public.channels`、最终 Gate／状态／ban／截止／代次复核与≤7天续至最终时间＋30天；启动不再使用旧 validator | SQL 锁 barrier、损坏目录、数据库错误、旧 token、接替、冻结、并发续期测试已写入；真实 SQL／提交故障与完整回归待执行 |
| T5 | 200 body 仍为七记录／五字段；权威 `Session-Expires-At`、requestId／no-store、400／403／429；移动端同 token／requestVersion 先安全存储截止再发布节点；真实 TLS 目录替换占位并加阈值续期／重启检查 | 三份 YAML／本地引用／契约结构检查通过；完整 OpenAPI validator、生成漂移、Flutter analyze／test／真实联调未执行 |
| T6 | `run-runtime-isolated.sh`：正式 Goose、非 owner、一次性旧通道升级、实际 cmd、真实 Mailpit、注册／接替／退出／恢复／目录阈值续期／进程重启／Gate 冻结与恢复／到期关闭释放 ACK；报告、机器记录、交接与 README | runner 实际尝试在工具检查处退出1（缺 go）；本次实际进程闭环未执行，计划完成标准仍开放 |

数据库时刻按微秒存储。本轮同时修正 C Gate 纳秒时刻与 PostgreSQL／文件锚点不一致：保留原时钟的 TTL／回退检查，在最终权威点向上归一到微秒，再检查证据截止；SQL、锚点与响应持久截止采用同一值。新增纳秒时钟回归未执行。

独立源码复核已促成修正：probe 状态文件参数、内部证书 CA 验证、非继承 owner membership、错用途操作私钥、目录数据库错误分类，以及 freeze 后尚未启动的认领项再次经过 Gate。收尾发现原 `RetireSlot` 直接提交终态，现将退役新写／重放纳入原请求代次的最终 Gate；READY 收据响应和 ACK 清理后的只读重签也在最终响应前复核原代次。新增测试用 SQL 锁／签名 barrier 覆盖冻结及恢复交错；缺 Go／PostgreSQL，未观察 red／green 运行结果。静态复核不能证明编译、SQL 约束或运行行为。

## 实际命令结果

以下结果是本次调用的退出码，详细摘要／命令目录见机器记录。

| 命令 | 退出码 | 结论 |
| --- | --- | --- |
| `git diff --check` | 0 | 补丁空白检查通过 |
| 新增／修改 shell 脚本语法检查 | 0 | 只证明 shell 可解析 |
| 已有 Python＋PyYAML：`packages/openapi/check-specs.py --yaml-only` | 0 | 三份 YAML／引用／契约结构通过，不包含完整 OpenAPI 规范验证 |
| JSON／Compose YAML／源码摘要检查 | 0 | 结构和记录一致性检查，非启动证据 |
| `go test -race -count=1 -p 1 ./...` | 127 | 找不到 go；编译／测试／race 均未执行 |
| `go vet ./...` | 127 | 找不到 go |
| `go test ./cmd/authdev`／聚焦退役 Gate 回归 | 127 | 找不到 go；配置和新增退役用例未执行 |
| `sh authlab/run-isolated.sh` | 1 | 前置检查：Missing tool: go；未建数据库 |
| `sh authlab/run-mobile-isolated.sh` | 1 | 前置检查：Missing tool: go；未运行 Dart 联调 |
| `sh authlab/run-runtime-isolated.sh` | 1 | 前置检查：Missing tool: go；未建容器／临时材料 |
| `flutter analyze`／`flutter test --reporter expanded` | 127 | 找不到 flutter |
| `python3 packages/openapi/check-specs.py` | 1 | 默认 Python 缺 PyYAML；已有 Anaconda 也缺完整 validator |
| `sh packages/openapi/generate-channel.sh` | 127 | 找不到 oapi-codegen；未生成或证明无漂移 |

`gofmt` 不可用，新增 Go 文件尚待标准格式化；没有声称 Go 编译通过或 Dart 类型检查通过。缺失项没有跳过后计入通过。

## 下一电脑的必要复验

先复用现成的锁定工具／缓存，从本仓库根目录按[infra 首次初始化与平台说明](../../infra/README.md)及[API 说明](../../services/api/README.md)执行。Windows 的 Go、POSIX 文件锚点、临时材料和 runner 必须位于 WSL2 Linux 文件系统；Go fixture 与 headless Flutter 必须同平台，不能传 Windows `.bat` 给 Linux fixture。

```sh
# 仓库根目录；先格式化，再记录本次变化的源码摘要
gofmt -w services/api/cmd/api services/api/cmd/verifier services/api/cmd/authdev services/api/cmd/runtimeprobe \
  services/api/internal/authprivacy services/api/internal/authprivacyhttp \
  services/api/internal/authprivacyruntime services/api/internal/channels
python3 packages/openapi/check-specs.py
sh packages/openapi/generate-channel.sh
sh packages/openapi/generate-channel.sh --check

cd services/api
sh authlab/run-isolated.sh
go test -race -count=1 -p 1 ./...
go vet ./...
sh authlab/run-runtime-isolated.sh
```

移动端从 `apps/mobile` 执行 `flutter pub get`、`flutter analyze`、`flutter test --reporter expanded`；随后回到 `services/api`：

```sh
export AUTHLAB_MOBILE_FLUTTER="$(command -v flutter)"
sh authlab/run-mobile-isolated.sh
```

单独执行 `go test` 时 SQL 用例无隔离 DSN 会跳过，不能作为数据库通过证据。完整生成器应来自 README 锁定版本；静态 `--yaml-only` 不能替代 validator 或生成漂移检查。新 runtime runner 不下载镜像、模块或 Go toolchain，缺缓存须在复验电脑依用户工具政策准备，不能悄悄转用 latest。

实际 cmd runner 使用真实七天申请验证截止和取消，再在标记的一次性数据库、自己的合成账号上建立独立的已到期 fixture，交由真实 worker 关闭／V 释放／C ACK；不修改真实申请的不可变截止、关闭约束或生产 HTTP 时间控制。该加速 fixture 不等于等待七天实测。

完整故障矩阵按[计划第4节](auth-privacy-runtime-business-integration-plan.md#4-授权并发与故障矩阵)检查，尤其迁移权限、错 peer／证书／origin、时钟证据停止、重启与迟到结果、SMTP DATA 未知、ACK 本地提交前故障、冻结与清理交错。失败必须修复并重跑，不用本报告当前摘要证明修复后的源码通过。

## 保留限制与资源归属

V 本片仍用 `clock_timestamp()` 判断 OTP 有效期／发送间隔／预算／设备锁、资格窗口、确认与签名结果、配额／退役和清理；整库旧快照可能复活预算、已消费 OTP、资格或槽位状态。具体入口见 API README 的 V 时间风险清单；V 独立可信时间／快照 Gate 是下一安全切片，C Gate 证据不能代证 V 灾备安全。

C 的开发证据签名、文件锚点与私有 operator 只证明同机开发边界；生产独立授时、外部锚点、灾备、密钥托管／运营分权及人类独立审计未验收。原生 Android／iOS、完整 app、真实安全存储和 Passkey 原生桥继续按[既有平台报告](auth-privacy-mobile-native-integration-validation-report.md)单列。

本轮未下载／重建大型运行时、SDK、APK 或构建缓存，未创建数据库／容器／开发私钥，未连接未知库。只清理本轮可确认归属的临时编辑脚本／Python 缓存；用户现成 SDK、AVD、历史证据和未知资源保持原状。runner 的 trap 仅清自己本次随机 Compose 项目与私有临时目录；没有全局 prune。历史验证 JSON 不修改。

**下一步为完成本片的编译与动态验收；当前不能据此推进生产放行。**
