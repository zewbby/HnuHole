# IDENTITY-AVATAR-01：身份头像与首次设置

更新：2026-10-23。分支 `feat/identity-avatar-onboarding`；原基线 main `6e09baf`，提交前已无冲突整合最新 main `8dca780`（含 #61 文档与 #62 私信顶部布局）。分支实现与宿主／隔离服务端聚焦验证完成，主会话独立审查无剩余阻断；未合并、未发布，真我隔离包待验。

用户最新要求：注册完成后、首次进入社区前设置昵称与头像（可保留默认头像）；已有身份不重复设置，旧零身份账号补设。初始身份沿用原始身份及公开发言默认规则，至少保留一个身份。

范围：C 受保护头像上传、规范化存储、独立引用、原子绑定/清理与迁移；严格 HTTP/Flutter DTO、持久幂等意图；系统图库选择、共享头像显示；独立于 DM 的首次身份入口。头像修改不受昵称三十天限制，不消耗创建次数；不改变已定稿私信布局、帖内身份绑定和首次联系规则。

方案：头像资源只保存经过现有受限媒体验证器完整解码、EXIF 处理及移除元数据后的静态 WebP；随机资源引用按身份隔离。CREATE 原子绑定可选上传引用，已有身份独立 AVATAR 操作。上传引用仅所属账号可绑定，受保护读取只允许仍有效的绑定或本人未过期草稿。替换、删除、注销、审核重置由同事务清理。

完成标准：受影响 Go/真实一次性 PostgreSQL/HTTP TLS、Flutter analyze 与聚焦状态测试、API 契约检查；独立复核与隔离 Android 验收由主会话接续。iOS、生产、真实掉电和推送缺口沿原记录，不升级结论。

实现包含静态图库图片上传与持久恢复、默认头像保留、CREATE／AVATAR／组合 RENAME 的原子资料保存、头像生命周期擦除、首次身份强制入口、公开帖子／评论和已有私信当前头像投影。旧 v1 未决意图重试不补头像字段，不改变指纹版本。复用 Telegram 主题和既有私信布局。

验证见[机器记录](../design/identity-avatar-onboarding-verification-20261023.json)。Go 构建／vet、受影响包单元、真实一次性 PG 的迁移 24→25／新建、受限运行角色／权限审计／触发器负向、最终 Gate／会话失权、真实 HTTPS 组合保存及头像恢复、EXIF 方向／元数据剥离、帖子／评论／私信投影均取得限定 PASS。Flutter 身份管理 30 项、关联 UI／runtime 83 项及旧零身份入口预期更新后的单例、最终新增恢复／入口／缓存 10 项 PASS；完整 11 份 `*-api`、3 份 DM 规范及 DM 契约检查 PASS。真实字体 360dp 普通与键盘模拟图可交主会话复核。独立 Android APK、真实图库／原生 AuthVault／强杀重启读回仍待主会话；不把宿主 bytes／vault 替身当原生结论。

新增产品 CI：`.github/workflows/identity-avatars.yml`，实际执行私有 PostgreSQL／真实图片验证器／TLS／Goose／Flutter／完整契约；远端执行待 PR。本地所有数据库由 private socket 一次性 runner 创建，未连接或重置共享开发库，未操作日常账号或设备。

配套升级要求：C 必须先以受控 migrator 应用 0025 并重新执行 `infra/postgres/grant-community.sql`，新服务以受限 runtime 启动检查；0025 Down 禁止。新头像及扩展 DM DTO 需要前后端配套升级，旧 2313 严格客户端不能视为兼容。当前只向主会话的 C25 隔离环境和 `.identityavatar` 独立包交付，禁止以本记录授权更新共享 C24／日常包或生产。

原生入口：设置 Gradle 环境 `HNUHOLE_IDENTITY_AVATAR=1`，目标 `apps/mobile/tool/identity_avatar_owned.dart`，传 `IDENTITY_AVATAR_OWNED=true` 及既有 `AUTH_COMMUNITY_BASE_URL`、`AUTH_VERIFIER_BASE_URL`、`AUTH_DEV_CA_BASE64`；仅允许显式 debug + 独立 loopback HTTPS。构建 wrapper 必须校验最终包名 `org.hnuhole.hnuhole_mobile.identityavatar`。入口复用真实 main，凭据和 control token 不编进包。使用隔离 SMTP 收码注册，恢复码确认和可选 Passkey 完成后进入初始身份弹窗；图库→昵称→完成→强杀／重启→管理页读回，再连续换图及默认头像复核。系统图库的合成样例和私有 OTP 查询由主会话 lab 提供；`/otp` 只在私有 control origin 带 lab capability 查询，不能成为公开注册替身。

现有 `registerOwned` helper 默认明确等待 Feed 或初始 gate 后返回；仅调用方传 `initialIdentityNickname` 才显式创建默认头像身份，零身份场景不会静默填设。

限制：目前图库适配沿用 Android 的原图选择器，iOS 原生路径尚未验收；真实掉电、远程推送、旧 P3 人工 SKIP、规模与生产缺口保留，不提升历史 B02／B08／B09 整模块结论。HTTP 测试中的“丢响应”只证明真实服务 PUT 后按原 ID GET 与客户端 timeout 替身恢复的组合，不宣称真实 TCP 丢包或设备故障矩阵通过。

主会话独立审查已逐项确认 R01–R06 修复：上传未知保留原草稿／连续更换清理、已有身份未决不重开初始入口、组合改名换头像、键盘边距、旧 v1 指纹、上传恢复后继续昵称保存。此为 agent 审查，非 GitHub 成员批准。478 项作者输入按 LF 比较无差异；真实 SQL 最后快照的四项差异均仅换行／gofmt，未重跑未变用例。

主线整合增量：#61 大图内存证据及 #62 既有布局验证按各自任务来源保留，未重复其设备／视觉验收；`dart analyze` 检查 inbox、共享 DM 头像、初始 gate、头像组件及关联测试共 7 个目标，0 issues；`flutter test --no-pub test/identity_initial_gate_test.dart test/identity_avatar_scope_test.dart --reporter expanded` 共 5 项 PASS。头像入口与缓存集成证据单列于机器记录，不将上游 CI／用户确认冒作本任务原生通过。

下一步：Sol High 提交冻结→主会话真我独立包图库与重启验收→补实际证据后按授权推送／提交 PR。当前仅冻结源码，不 push／PR／merge，不更新共享后端或日常包。
