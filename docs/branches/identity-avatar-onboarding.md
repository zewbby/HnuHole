# IDENTITY-AVATAR-01：身份头像与首次设置

更新：2026-10-23。分支 `feat/identity-avatar-onboarding`；原基线 main `6e09baf`，提交前已无冲突整合最新 main `8dca780`（含 #61 文档与 #62 私信顶部布局）。分支实现与宿主／隔离服务端聚焦验证完成，主会话独立审查无剩余阻断；未合并、未发布，真我隔离包新增链路限定验收通过。

用户最新要求：注册完成后、首次进入社区前设置昵称与头像（可保留默认头像）；已有身份不重复设置，旧零身份账号补设。初始身份沿用原始身份及公开发言默认规则，至少保留一个身份。

范围：C 受保护头像上传、规范化存储、独立引用、原子绑定/清理与迁移；严格 HTTP/Flutter DTO、持久幂等意图；系统图库选择、共享头像显示；独立于 DM 的首次身份入口。头像修改不受昵称三十天限制，不消耗创建次数；不改变已定稿私信布局、帖内身份绑定和首次联系规则。

方案：头像资源只保存经过现有受限媒体验证器完整解码、EXIF 处理及移除元数据后的静态 WebP；随机资源引用按身份隔离。CREATE 原子绑定可选上传引用，已有身份独立 AVATAR 操作。上传引用仅所属账号可绑定，受保护读取只允许仍有效的绑定或本人未过期草稿。替换、删除、注销、审核重置由同事务清理。

完成标准：受影响 Go/真实一次性 PostgreSQL/HTTP TLS、Flutter analyze 与聚焦状态测试、API 契约检查；独立复核及隔离 Android 新增链路限定验收已由主会话完成。iOS、生产、真实掉电和推送缺口沿原记录，不升级结论。

实现包含静态图库图片上传与持久恢复、默认头像保留、CREATE／AVATAR／组合 RENAME 的原子资料保存、头像生命周期擦除、首次身份强制入口、公开帖子／评论和已有私信当前头像投影。旧 v1 未决意图重试不补头像字段，不改变指纹版本。复用 Telegram 主题和既有私信布局。

验证见[机器记录](../design/identity-avatar-onboarding-verification-20261023.json)。Go 构建／vet、受影响包单元、真实一次性 PG 的迁移 24→25／新建、受限运行角色／权限审计／触发器负向、最终 Gate／会话失权、真实 HTTPS 组合保存及头像恢复、EXIF 方向／元数据剥离、帖子／评论／私信投影均取得限定 PASS。Flutter 身份管理 30 项、关联 UI／runtime 83 项及旧零身份入口预期更新后的单例、最终新增恢复／入口／缓存 10 项 PASS；完整 11 份 `*-api`、3 份 DM 规范及 DM 契约检查 PASS。真实字体 360dp 普通与键盘模拟图可交主会话复核。主会话已在精确 `fca05299` 独立 Android APK 完成真实图库／原生 AuthVault／进程强杀冷启读回；具体范围与宿主替身证据分别记录。

新增产品 CI：`.github/workflows/identity-avatars.yml`，实际执行私有 PostgreSQL／真实图片验证器／TLS／Goose／Flutter／完整契约；远端执行待 PR。本地所有数据库由 private socket 一次性 runner 创建，未连接或重置共享开发库，未操作日常账号或设备。

配套升级要求：C 必须先以受控 migrator 应用 0025 并重新执行 `infra/postgres/grant-community.sql`，新服务以受限 runtime 启动检查；0025 Down 禁止。新头像及扩展 DM DTO 需要前后端配套升级，旧 2313 严格客户端不能视为兼容。当前只向主会话的 C25 隔离环境和 `.identityavatar` 独立包交付，禁止以本记录授权更新共享 C24／日常包或生产。

原生入口：设置 Gradle 环境 `HNUHOLE_IDENTITY_AVATAR=1`，目标 `apps/mobile/tool/identity_avatar_owned.dart`，传 `IDENTITY_AVATAR_OWNED=true` 及既有 `AUTH_COMMUNITY_BASE_URL`、`AUTH_VERIFIER_BASE_URL`、`AUTH_DEV_CA_BASE64`；仅允许显式 debug + 独立 loopback HTTPS。构建 wrapper 必须校验最终包名 `org.hnuhole.hnuhole_mobile.identityavatar`。入口复用真实 main，凭据和 control token 不编进包。使用隔离 SMTP 收码注册，恢复码确认和可选 Passkey 完成后进入初始身份弹窗；图库→昵称→完成→进程强杀／冷启→管理页读回，再仅换头像并复核；整机重启与原生默认头像创建未在本轮重复。系统图库的合成样例和私有 OTP 查询由主会话 lab 提供；`/otp` 只在私有 control origin 带 lab capability 查询，不能成为公开注册替身。

现有 `registerOwned` helper 默认明确等待 Feed 或初始 gate 后返回；仅调用方传 `initialIdentityNickname` 才显式创建默认头像身份，零身份场景不会静默填设。

限制：目前图库适配沿用 Android 的原图选择器，iOS 原生路径尚未验收；真实掉电、远程推送、旧 P3 人工 SKIP、规模与生产缺口保留，不提升历史 B02／B08／B09 整模块结论。HTTP 测试中的“丢响应”只证明真实服务 PUT 后按原 ID GET 与客户端 timeout 替身恢复的组合，不宣称真实 TCP 丢包或设备故障矩阵通过。

主会话独立审查已逐项确认 R01–R06 修复：上传未知保留原草稿／连续更换清理、已有身份未决不重开初始入口、组合改名换头像、键盘边距、旧 v1 指纹、上传恢复后继续昵称保存。此为 agent 审查，非 GitHub 成员批准。478 项作者输入按 LF 比较无差异；真实 SQL 最后快照的四项差异均仅换行／gofmt，未重跑未变用例。

主线整合增量：#61 大图内存证据及 #62 既有布局验证按各自任务来源保留，未重复其设备／视觉验收；`dart analyze` 检查 inbox、共享 DM 头像、初始 gate、头像组件及关联测试共 7 个目标，0 issues；`flutter test --no-pub test/identity_initial_gate_test.dart test/identity_avatar_scope_test.dart --reporter expanded` 共 5 项 PASS。头像入口与缓存集成证据单列于机器记录，不将上游 CI／用户确认冒作本任务原生通过。

真我原生回执：主会话以精确 `fca05299ba4a0c73ec6aa9a4877faea1a1c6dd8d` 构建 `.identityavatar`2314，APK SHA256 `c1a00b6aa7ce9e5b373729d8bf1bbf2dfeb04a2eb588dc615600a1b3ac2ea7fd`。实际 SMTP OTP、恢复码确认及可选 Passkey 收尾后弹窗；返回／外部点击不能跳过。原生图库 Browse 选择自有蓝色 JPEG，填写昵称并 CREATE；SQL 确认一个原始身份、累计创建 1 次，最后一个删除按钮禁用（后端拒绝由另列 SQL 证明）。真实 IME 展开时完成／退出可达，实际完成成功。进程强杀冷启保持登录、身份与蓝头像；绿色 JPEG 仅改头像并跨新进程保留，身份／昵称／计数不变、改名日期 NULL，旧 payload NULL、新 WebP 无 EXIF，DM 头像更新；添加→取消→返回 DM 无初始／核对页。7 个限定项、9 份私人证据的绝对路径／hash 均见机器记录，未提交图片、APK、日志或秘密。日常2313、共享C24、vivo均未动；整机重启、突然掉电、真实 TCP 丢响应、iOS、规模及生产未验。

验收后的唯一移动端产品文案差异是管理页零身份防御空态旧文案改为“还没有发言身份，请先完成初始身份设置。”及对应断言；正式首次 gate 下该旧空态不可达，未改变头像流程、协议或存储。同步修正 accounts／post-composer／comments 当前规则及 ADR 覆盖说明；`flutter test --no-pub test/identity_management_screen_test.dart --plain-name 'zero-identity account can create default-avatar identity and preserves legal input' --reporter expanded`：1 PASS；仅回归该既有管理空态单例，未重复未变原生矩阵。

PR #63 首轮精确 `a6936ec` 的 21 项 CI 为 17 PASS／4 FAIL：feed-postgres 与 flutter-and-real-feed 同因旧 Goose 行数断言未计 0025；Flutter 唯一旧 wire 夹具枚举 AVATAR 后仍只给 nickname；预发布恢复后 readiness 因 `--no-privileges` 恢复使三个头像触发器函数重获默认 PUBLIC EXECUTE，被原 CheckDatabase 正确拒绝。定点修复将迁移断言改为 count26／max25、旧请求体保留并显式覆盖 AVATAR PATCH，并在 grant-community 重新撤销精确三个函数的 PUBLIC 权限（存在性保护兼容旧 schema）；新增真实无 ACL 恢复回归。真实 feed/race 四子例、wire 单例与分析0、恢复失败复现及修后真实 CheckDatabase、pre10/11/12 grant 投影均 PASS；四个作者输入 LF hash 与主会话 R07 独立审查已核对。未修改运行时检查或放宽 readiness，不声明本地完整 rehearsal PASS，新 head 远端 CI 待执行。

旧设备矩阵边界：现有 `registerOwned` 只保证注册可返回首次 gate，调用方显式提供 `initialIdentityNickname` 才创建身份。旧 B3/B4 六处调用均未迁移新 gate；C01 经旧 accountRoute 进入零身份昵称草稿的路径已不适用，K01 本来专测零身份草稿，不能统一自动创建。旧 runner 的 APK／源码 hash 和历史证据保持原版本，当前完整 B3/B4 矩阵不声称适配或通过；本任务真实 main 的新增 7 项原生验收单列，未重写或重跑历史矩阵。

下一步：提交／推送上述定点修复至 [PR #63](https://github.com/zewbby/HnuHole/pull/63)，核对新 head 适用产品 CI。独立 agent 审查不等于 GitHub 成员批准；本功能尚无合并授权，不更新共享后端、日常包或生产。
