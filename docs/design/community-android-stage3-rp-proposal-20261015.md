# 第三项 RP／域名／签名关联待确认方案

2026-10-15。**这里只准备方案，尚未获准登记域名、部署关联或应用安全配置。**第三项当前是主机准备范围；系统 Passkey、实际账号、手机及跨设备均未通过。产品固定 b5accf36b90e27829b6d039cd58a5b9c189a3da8，认证来源固定 d859cb05c772cdf8d8b75e439a2bfedf0414dd46；并行手机守卫提交 e0c128033682923d519ea99546d72503b085a99e 已保留。

用户已回复“按你的方案来”，本方案据此选定并继续只读核实；提问已明确不授权注册、公开部署或应用安全配置，此边界保留。公开核查取得DNS解析，但未取得可验证的HTTPS关联文档；不能据此证明项目名可注册或用户拥有控制权。公开草案及核查记录另存于[版本化审阅目录](community-android-stage3-review-20261015/)，仍为DRAFT、没有应用到产品/运行配置。

## 拟批准的精确范围

| 配置 | 拟议值／事实 |
|---|---|
| 独立 RP 候选 | `hnuhole-community-passkey.pages.dev` |
| 域名状态 | 仅候选名称，可用性、托管账号与控制权均**未确认**；没有注册、创建项目或部署。可以改为用户已有、可控制的独立域名，然后重新生成差异。 |
| 公开 HTTPS origin | `https://hnuhole-community-passkey.pages.dev` |
| 唯一拟授权 Android 包 | `org.hnuhole.hnuhole_mobile.communityf5.passkey` |
| 本任务新调试证书 SHA256 | `3309ce001a5dfd93148c14e35159147a6711e4b61d881b7a223b3e8429665e34` |
| C 允许的 Android origin | `android:apk-key-hash:MwnOABpd_ZMUjBTjUVkUemcR5LYdiBt6Ijs-hClmXjQ` |
| 公开文件 | `https://hnuhole-community-passkey.pages.dev/.well-known/assetlinks.json` |
| DAL 两项关系 | `delegate_permission/common.get_login_creds`、`delegate_permission/common.handle_all_urls` |

候选站点拟在用户控制的独立托管项目中创建，仅承载测试用公开关联文件。Cloudflare Pages 的项目可以具有其独立 `pages.dev` 地址，但名称和账号控制权须实际确认，本方案不声称已取得这个名称。[Cloudflare 官方域名文档](https://developers.cloudflare.com/pages/configuration/custom-domains/)

DAL 文件须由正常公有 HTTPS 证书提供，直接返回200及 application/json，不经登录、跳转或访问挑战；本地 C/V API 仍使用本任务独立、校验链与主机名的 loopback HTTPS 和私有开发 CA，不能把公开 RP 文档当作关闭 API TLS 校验的理由。[Google DAL 要求](https://developers.google.com/digital-asset-links/v1/create-statement)

保留两项 DAL 关系与当前生成器和固定认证交付一致；Google FIDO 原生关联文档仍说明迁移期间同时声明两项。只加入上表精确包名与证书，不向其他包或证书扩权。[Google FIDO 原生文档](https://developers.google.com/identity/fido/android/native-apps)

## 已准备、但尚未应用的文件

正式草案目录：`E:/HnuHole-community-f4-20261012/stage3-preparation-20261015/review-bundle-final`。所有内容均为公开配置与证书摘要，没有私钥、账号、恢复码、数据库或签名证明。

| 文件 | 确认后的用途 |
|---|---|
| `proposal.json` | 逐文件 SHA256、域名/关联未批准状态及排除项；它不是授权凭证 |
| `site/.well-known/assetlinks.json` | 新独立公开站点只增加1个包／1个签名条目 |
| `candidate-debug/passkey_associations.xml` | 仅新 task3 构建镜像的 debug资源指向独立 RP |
| `candidate-debug/manifest-snippet.xml` | 保留现有 debug `asset_statements` metadata；main/release manifest 不改 |
| `candidate-debug/dart-defines.fragment.json` | 新调试候选的固定 `AUTH_DEV_PASSKEY_RP_ID`；必须同时配置本任务合法 debug CA 与独立 C/V loopback origins |
| `runtime/web-authn.config.fragment.json` | **全新一次性 task3 C 配置**，固定 RP、HTTPS origin和唯一签名 origin |
| `runtime/authdev-init-extra-argv.json` | 新 `authdev init` 所需3个真实 flag 及精确值；不改正在运行的任务1或认证配置 |
| `review-only.patch` | 现有 debug资源到候选 RP 的可审阅差异；目前没有应用到产品或构建镜像 |

当前仓库 Debug 资源仍含历史认证 RP `zewbby.github.io`。本轮不改它、不向该站点增加关联，也不复制其账号、签名或运行材料。现已构建的三个 APK **只用于未配置基线／签名对照**，仍含原始源码 Debug 资源；它们不是独立 RP 的可验收正向候选，必须在域名及安全配置获准后以本任务新 TLS/C/V 配置重建并重新核对。

## 明确不授权的两个负向对照

| 对照 | 配置与判断 |
|---|---|
| 错误签名、同一包 | `org.hnuhole.hnuhole_mobile.communityf5.passkey`，证书 `08cddd6d4eff8b50315ecd1a4496d847a3d86048c6da5d08019b11aaa412e849`；不加入 DAL 或 C 可信 origin |
| 正确签名、未关联包 | `org.hnuhole.hnuhole_mobile.communityf5.passkey.unassociated`，使用正确调试证书；不加入 DAL |

错误签名 APK 的560个非签名条目已与控制 APK 逐项相同；未关联 APK 只改变 applicationId。当前只是构建与字节对照通过；系统是否实际拒绝仍须设备验证。通用取消、超时、网络错误不能冒充 RP／签名关联拒绝。错误签名同包不能直接覆盖正确签名包：后续要么先采用单独的、经用户批准的可丢弃测试包生命周期，要么延期该项；本方案不授权卸载、清数据或替换已有 App 签名。

## 确认与执行顺序

1. 用户先确认是否采用上述独立域名方案，或提供已有可控制的独立域名，并确认使用哪个托管账号。名称不可用或无控制权则重新生成方案，不退回认证 RP。
2. 审阅唯一包／签名、两个关系、上述具体文件和新 C 配置；确认仅在新的测试站点与一次性 task3 环境应用。公开部署另按用户授权进行，不从“准备方案”推断授权。没有审批则保持 DRAFT。
3. 获准后才创建站点／发布最小 DAL，保留提交或部署ID与确切文件哈希；用只读 `check-association.py` 核对HTTPS链/主机名、无redirect、200/JSON和精确文件。HTTP文档通过不代证 Google/provider 通过。
4. 新建 task3 C/V一次性数据库、独立端口与合成账号；使用原正式迁移/最小权限和独立材料，从 `authdev init` 起固定 RP。不得修改任务1待验库、认证环境、原协议／UV／resident／ES256／五分钟期限或 Gate。
5. 只在新的构建镜像套用获准的 debug XML/Dart define与唯一 applicationId，保持产品和锁不变，使用已登记本任务签名重建；重核 APK、证书、实际 RP、SQL配置与源码指纹。补跑受影响主机检查后，才能称“设备候选已准备”。
6. 设备前先解当前 USB/ADB key隔离阻断或取得明确、可验证的授权变更；再确认设备窗口、认证释放、具体包及数据影响。当前不使用 ADB、读任何 profile key、创建 OS账户或更改安全配置。

## 手机阶段固定验收

| 场景 | 必须取得的实际事实 |
|---|---|
| 正向绑定 | 真实系统 provider／用户UV、C验证成功、SQL只增1条、App凭据列表一致；系统成功本身不直接赋予会话 |
| 可发现恢复 | 无用户名/allowCredentials的系统get、C恢复intent、新恢复码隐藏后完整确认和新密码提交；不自动登录，按契约核旧凭据／会话失效 |
| 取消／拒绝 | 人工取消、实际系统拒绝分别记录；原待办/SQL/凭据数量不被错误升级，迟到回调不写新会话；必要的系统指纹/密码动作由用户完成 |
| 自然到期 | 原生60秒取消与C五分钟challenge分别计时、自然经过，不缩短期限或改系统时间；原始未知保持未知，不用410/404猜测未提交 |
| 丢绑定提交响应 | 只在实际上游处理后丢/延迟响应，原pending anchor持久化；强停/重开后查原challenge/key，禁止重建系统凭据或重复提交证明 |
| RP／签名／包名负向 | 分别证明客户端固定RP、C验签/RP拒绝、真实provider关联拒绝；每项保留准确边界，不把普通取消当作关联证据 |
| 单机联合收尾 | 完成任务1/2实际社区、原生存储/进程/重启/IME/读屏，最后产品若修复则重跑受影响的mobile/R05/F4/server/权限/runtime/vet；四阶段总任务仍等待双实体NI-X01/X02 |

旧 B3/B4 脚本带原路径、runId、设备和认证账号，不直接执行。本轮准备的是明确的配置/操作方案及已存在产品流程入口；尚未获得 RP/运行配置，因此**没有宣称新的系统端到端统一 runner 或已部署环境完成**。配置确认后还需完成其独立实验环境与最终候选重建，这部分受安全配置授权阻塞，不能冒称只差手机。

当前可直接审阅/复用的无手机入口：`tools/community-android-stage3/build-baseline.sh`、`verify-baseline.py`、`proposal.py`、`check-association.py` 与 `tools/tests/test_community_android_stage3.py`。主机检查结果见[准备报告](community-android-stage3-preparation-20261015.md)及对应机器记录；手机、第二实体Android、iOS、生产全部独立待验。
