# Android 集成候选（2026-10-19）

状态：固定 APK、必要新增恢复和限定设备治理连接完成；待本任务 PR 审查/检查后合并，未部署或正式发布。中途 Gate incident 已正式恢复，根因待所属模块分析；不宣称持续可用。

产品源码固定 `1a810944787eacb66e2115e1ce77de08190c366a`，包含完整评论 [#19](https://github.com/zewbby/HnuHole/pull/19) 与评论举报 [#22](https://github.com/zewbby/HnuHole/pull/22)。不继续追新 main。交付工具和文档的提交与产品源码分别记录，不能把文档提交当作重新构建或设备已测版本。

## 普通集成包

入口为真实 `lib/main.dart`，ARM64、API29起，实际版本 `0.1.0+2026101901`。采用独立测试签名和 App 内开发 CA 的 debug 模式；正常 HTTPS 证书链/主机名检查继续开启，无 RP override，无手机系统 CA 或安全设置变更。

仅接收 `communityOrigin`、`verifierOrigin`、`caPem` 三项公有配置；两个地址均为各自固定的 loopback HTTPS 端口。普通候选不接收 `COMMENT_DEVICE_FIXTURE_BASE64`、账号、密码、token 或原生验收控制端点，不分发含夹具凭据的验收 APK。APK、完整 manifest、公开测试签名证书、公开配置、SHA256SUMS 与安装说明在构建后一起归档。后端私有运行材料单独保留，不进入普通包或 Git。

本轮核对出旧同包测试证书 `09309fe3…` 与新签名冲突，用户在本轮窗口明确授权后才卸载旧 App 及本机数据。仅使用新准备的 platform-tools 37.0.1 / ADB5159，保留系统既有 USB 身份，未读/复制私钥。实际 vivo S18/V2323A、Android15/API35（用户称 OriginOS5），候选保持安装，窗口及专用 ADB 已关闭。

| 固定项 | 实际值 |
| --- | --- |
| 产品/后端源码 | `1a810944787eacb66e2115e1ce77de08190c366a` |
| APK / 大小 | `4df3f7c85f6bb312fde1034d577c093136b6f0c989daeea70a65f32aa624ac0f` / 98,625,420 bytes |
| 包名 | `org.hnuhole.hnuhole_mobile` |
| 测试签名证书 SHA256 | `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea` |
| 公有配置 SHA256 | `cd61245e0db4f150fe4be11932975a9e2606203aeaf579dd1d5b4573947d7f57` |
| C / V | `https://127.0.0.1:51245` / `https://127.0.0.1:49747` |
| 开发 CA PEM SHA256 | `57487d56e2d50327bfbf2ca9bb0db4952a050efef6c4fb85ac9990ffbf9cbda4` |
| CA 有效期（UTC） | 2026-10-19 04:47:27 至 2026-11-18 04:48:27 |
| C / V 迁移 | 正式0001..0018 / 0001..0004，逐文件摘要见构建回执 |

[原始构建 manifest](android-integration-build-20261019.json) 保留构建时 device NOT_RUN 快照，另用[实际设备回执](android-integration-device-20261019.json)记录后续验收。实际调用配方 SHA256 `c60238bfa7a5a6cd31b04e9cf27ec5cbe621fa8f1e5e683e9908acef6f7a7152`；审查后补守卫的最终 `build.py` 为 `e0b7dc994d7460cffc8ef6a5ca2b83f7a6ad7324b909a900ae1dd18c2afd00b0`。该 APK 由前者构建，不能称由后者构建；产品输入不变，因此复用 APK。

## 继承的证据

- [原预发布合并回执](android-prerelease-main-merge-20261019.json) 和[运行手册](android-prerelease.md) 已交付/清理，不恢复旧环境或重跑全套注册、图文和 V 恢复。
- [评论限定 Android 报告](../design/comments-connected-report-20261019.md)、[机器记录](../design/comments-connected-verification-20261019.json)：原生 journal、真实进程恢复、单图、选图、失败通知/重试等沿用原 APK 范围。固定 main 的57项输入中45项相同，12项差异来自后续治理入口/可见性及对应测试。
- [评论举报报告](../design/comment-report-validation-20261019.md)、[机器记录](../design/comment-report-verification-20261019.json)：固定 main 的699项产品/测试输入与已测清单一致，指纹 `bdda093c4c40ff60e8ff4d4820f2f7b5d0cdec2c5f5ebeb89c34638b853654a6`。既有 SQL、迁移/权限、Dart HTTPS 和业务闭环直接继承。
- 旧网页自动测试使用了仅测试上下文的 `ignoreHTTPSErrors:true`；其页面功能证明不作为本轮严格 TLS 的证明，本轮不得复用此例外。

## 必要新增恢复影响

本轮新的独立环境使用正式 C0001..0018 / V0001..0004，显式配置 posts、postImages、comments 和 moderation，并通过同源 C HTTPS 提供 `apps/admin`。独立 Go/Goose/Pillow、SDK、缓存、端口和测试密钥均在依赖实际合入后才准备，旧环境未恢复。

新增 C 恢复包含3条评论、1张评论原图、1条举报、1条处罚、1条申诉、2个管理员角色、3条审计及通知单条已读事实；实际备份恢复到新 C 实例后，62份表/sequence摘要及规范评论/治理权限匹配。V继续使用本轮原实例，未重做旧 V 恢复。新 C 恢复后旧会话拒绝，正常重登后原举报和已读时间保持；另一管理员对原申诉复核，原图字节摘要保持一致。

0018前的 #19 后端在新配置/新schema下实测拒绝启动。独立审查要求收紧泛化 runtime marker 的归因后，又在真实恢复库以受限角色执行旧/新 checker 的只读精确谓词：旧版本多出不允许 UPDATE 的 `moderation_hidden`，新版本零项；旧/新 checker 源码摘要与结果已保留。旧 `WithComments → CheckCommentSchema` 无法满足0018新增授权契约，未撤回所需权限去迁就旧 binary，不将其列为安全回滚版本。不执行 Down，也不以旧 binary 能启动代证新评论下架语义兼容。当前固定1a810944后端已恢复可用。

工具失败历史保留：SDK下载超时后仅续装缺失组件；合成准备客户端首次漏32字节登录幂等头、帖子状态读取层级错误；最终原图读取使用了错误字段名。均修正交付工具后窄范围继续，没有改业务或重跑旧全套。见[真实恢复及精确兼容诊断回执](android-integration-restore-20261019.json)。

## 本轮实际设备治理连接

本轮在新窗口只执行新增范围，见[机器回执](android-integration-device-20261019.json)：

1. 普通 App 正常登录合成举报人，对 `集成 deviceReply 合成评论` 真实回复举报；网页收到准确 commentId 与合成说明。
2. 严格 TLS 的真实网页 UI 认领并禁言三天；实际案件 outcome 为 `UPHELD`，处罚 action 为 `MUTE`。最初 helper 错把 outcome 期待为 MUTE，修正回执核验，没有重复处置。
3. 举报人 App 收到提交/处理中/已结束通知；作者正常登录，打开处罚通知详情并从 App 提交原处罚的申诉。
4. 另一合成管理员在网页独立接受同一申诉，作者重新登录后 App 显示“申诉通过”、对应材料及处罚已撤销。真实 runtime SQL 验证同一申诉、回复、处罚撤销和该通知 read_at；未以网页结果代替 App 结果。

网页使用独立 Linux NSS 数据库，仅导入本任务 CA，`ignoreHTTPSErrors=false`；同一地址在全新无信任的本任务浏览器 HOME 下实测拒绝 `ERR_CERT_AUTHORITY_INVALID`。无系统 CA、TLS 忽略参数或 Gate 旁路。该网页自动操作是实际页面/实际 HTTPS，非内存替身；不代证物理桌面浏览器或生产运营。

### Gate incident 与范围边界

网页 ACCEPTED 回执与冻结记录时间相距约57ms，C 独立锚点变为 FROZEN，数据库记录 `INDEPENDENT_ANCHOR_FROZEN`；V仍200。时间接近不能证明因果，根因未知，不归咎业务、浏览器或证据过期。以已有独立 recovery 角色/签名 operator 仅恢复 C 至 OPEN/代次3，未手改 Gate、撤权或重置数据；C/V readiness 恢复200。旧会话按代次失效；自动凭据输入受安全键盘/Bitwarden影响，错误登录保留，最终用户按本地私有说明清空重填、正常登录后完成 App 最终结果读回。最终严格 HTTPS C/V200已记录。此 incident 交授权/Gate 模块后续分析，当前结论为恢复后的限定连接 PASS，不能称无中断、持续可用或生产 Gate 完整通过。

未重验完整注册、图片发布、评论恢复；沿用有效原证据。新增治理补图/系统选图、实体 TalkBack、多机型矩阵、iOS、跨设备 Passkey、云端及生产/独立运营均 NOT_RUN。未弱化 TLS、Gate 或权限检查。

普通与 `-O` 下各8项交付边界测试通过；当前受限 seed helper 编译成功但未重复播种；Go1.22.2、Goose3.22.1、PostgreSQL16.15、Python3.12.3/Pillow12.3.0、Flutter3.47.5、Java17.0.20.1、build-tools36、NDK28.2.13676358/CMake3.22.1已固定。独立只读复审无剩余 P1/P2，agent 审查不冒充 GitHub 成员批准。CI/合并事实由本任务 PR 和最终合并回执补充。

候选、私有运行材料、安装/运行/恢复入口及清理回执见[复现说明](android-integration-reproduction-20261019.md)。后端私有凭据仅存专用本地材料；不进普通交付包或仓库。

任务与接续：[任务详情](../branches/ci-android-integration-candidate.md)、[HANDOFF](../design/HANDOFF.md)、[进度](../design/progress.md)。
