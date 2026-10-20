# FEED-INTERACTIONS-UI-01

## 当前收口（2026-10-20）

最新增量：2005实测发现FA-D04（B已登录但旧My仍捕获A窗口）和FA-D05（503原令牌核对/401重登成功后旧Feed仍失效），两项P2尚待新包复验。根路由现按账号/epoch重建My与Feed，保留旧页面/编辑器/异步回调围栏；目录另行更新props，同通道回用须匹配窗口及存活路由实例。新增真实生产root/AuthScreen/Session/PostController回归9项，原c90运行文件9FAIL、修后9PASS，App全量589PASS/分析0。准备新同签debug2006，最终main再递增；2005失败不改成PASS。[旧My实际失败图](../design/feed-interactions-ui/assets/android-2005-old-my-window.png)。完整范围及输入摘要见本轮机器记录的routeRecovery；原首次账号页退回经driver日志核实为过时IME判断发Back，非产品认证自动成功，独立D04/D05复现不变。

已整合工具[#32](https://github.com/zewbby/HnuHole/pull/32)/[#33](https://github.com/zewbby/HnuHole/pull/33)后的最新main `938f7e7`。2005已有真实FA15、评论202丢响应恢复/回复删除、旧通道及时返回、B个人旗标与SQL限定证据；本轮修复提交及新设备/最终CI仍待，不以前版CI/宿主结果代证修复真机。

后端 [#30](https://github.com/zewbby/HnuHole/pull/30) 已合入 `c923fa5a`，本分支通过 `c1b92f0` 整合；真实条件写探针原先依赖 main0020 的失败条件已消除。`ca38c70` 的 Feed UI CI 已通过真实 C HTTPS／一次性 PostgreSQL 步骤，最终提交仍须重核全部适用 CI。

本轮修复 26–50 项摘要被 1024 字节默认上限拦截、FA-D03 查看器前景对比度、有效同账号续期丢评论页面/草稿、已释放媒体租约迟到拒绝误伤新租约。宿主分析0、App580及Viewer116项PASS；查看器主题、评论续期与旧租约分别保留失败复现及回归。Max独立静态复核至`ca38c70`未发现阻断，未替代 GitHub 成员批准。

更新后的共享 main `c923fa5a`／C0021／V0004，生产 Dart 探针7项PASS：50项摘要1963字节、单图及三图保护字节、条件赞藏、B账号旗标写前/后不变、恢复原状态及旧条件412。环境由负责人升级，前端不操作环境或设备；历史独立CAS及2004证据保留原范围。

同签 debug／`main.dart` 候选2026102005已交Android：源码`ca38c70b21ee97bcf761be689a09b43b0e213ad0`，APK SHA256 `c0e7569ea53457a369ae2dd3e06ad9c0078e67cf156462ca49c7d9d1f3191431`，98,791,052字节。当前2005矩阵及响应丢失/迟到写/重试/切账号补验待收口；不使用2004的CAS结果代证2005。隔离入口只有私有CA，release/profile真实链路和性能明确NOT_RUN，保持debug-only CA guard，不正式发布。最终main候选须等合并后重建，不能用2005代替。

当前详情、命令、输入摘要与待办见[本轮机器记录](../design/feed-interactions-ui-finalization-20261020.json)。用户已授权在相关验收无阻断、独立审查完成及最终head适用CI全通过后将[#31](https://github.com/zewbby/HnuHole/pull/31)转Ready并合并；目前保持draft。

Android 2005 的 FA15 已独立 PASS：赞/藏各真实200提交后hold20秒丢响应，原UI核对与详情/列表/只读SQL一致；各旧PUT在入口扣住，15秒超时后保持未知并锁住两动作，原UI显式重试复用条件成功，取消后再释放旧PUT得到真实412，最终0/0且写版本不变。点赞78.63秒、收藏46.86秒释放，均早于120秒入口终止上限，不是abort代证。其余2005补验仍待收口。FA-D03浅色实际页码已确认可读，[2005查看器实际渲染](../design/feed-interactions-ui/assets/android-2005-viewer-contrast.png)由Android确认可公开合成内容，前端再目视核对，不代证深色/多图全项。

## 原送审及2001–2004历史快照

以下内容保留原版本、环境和时点；其中未合并、565项、FA15缺入口等不覆盖上方当前状态。

> 续办（2026-10-20）：用户已授权在后端#30真实合入、最新main整合、更新后的共享测试环境联调、Android补验无阻断及最终head适用CI全通过后，将#31转Ready并合并；随后从最终main重建同签候选，不正式发布。前端不操作设备或更新环境。等待期间独立复核发现合法26–50项batch被默认1024字节上限拦截，已复现并修为本接口4096字节，补26/50项真实TLS与51唯一ID发送前拒绝回归；历史交付证据按原版本保留，最终收口材料另补。

- 更新：2026-10-20（Asia/Shanghai）。用户指定分支 `feat/feed-interactions-ui`，独立 worktree `E:/Hnuhole-env/source/HnuHole-feed-interactions-ui`；基线最新远端 main `444d25862a83d3a8d40168ef660e50da0712b71e`，旧工作区保留。
- [Draft PR #31](https://github.com/zewbby/HnuHole/pull/31)，候选源码 `f8133cf819e655a98d5d53d234a26e4a705c2d10`。实现/宿主/真实接口/构建限定通过，2004两缺陷真机复验PASS，2004评论/SQL对照已收口并交接独立报告；未合并或发布。
- 依赖独立后端 [#30](https://github.com/zewbby/HnuHole/pull/30) 的条件版本契约与0021；本PR不夹带后端提交。依赖获授权合入后须重新整合main/核对CI。0020不支持条件写，客户端不会回退到无条件写。

## 实现

每页feed成功后以postId批量读取赞/藏/评论摘要，空页不发空数组，严格FeedPost不改。批量404刷新feed一次；读取失败保留未知计数及重新读取入口。列表与详情共享账号内存状态，401/503沿原认证边界；相同有效token的活动续期保留互动锁。切账号时清视图，迟到响应及旧页面回调不能操作新账号。

同帖赞/藏共用同步锁，连点不排队产生相反请求。新意图先GET取 `Interaction-Version`，PUT发期望bool及 `If-Interaction-Version`。超时重试复用原条件；同版本即使bool相同仍不能解锁。版本永久旋转后才终结未知，412后同步当前状态，未达到期望时明确失败，用户重试才取新条件。读写重试分开，重新读取不会暗中重发旧赞/藏。

读取ticket阻止旧摘要覆盖新结果；写忙、写前失败和刷新打断的读取保留dirty需求，收尾重新查询。评论发布/删主楼及回复仍走原接口，重新读取服务端数量，不猜整楼删除量。保留原认证、发帖、身份、存储、图片及评论链路，不扩展私信、收藏列表、通知或热榜。保持确认的X布局/Telegram字体配色，收藏数在详情及列表无障碍标签使用真实数据。普通360dp保持单行，大字体合理换行。

## 验证与渲染

完整命令/输入/失败历史/摘要见[机器记录](../design/feed-interactions-ui-verification-20261020.json)。Flutter分析0、全量565项、生产bundle及全插件arm64 Android构建/验签PASS；26项互动状态/渲染及5项新增媒体回归覆盖连点、超时、412、迟到读、续期、切账号旧回调、重建Controller后旧CAS最后恢复、读写重试分离、评论刷新及360dp几何。真实TLS HTTP检查包括精确header、缺失/非法/重复版本、输入/响应绑定与412分类。

生产Dart客户端对共享444d258/C0020/V0004完成A/B登录、游标分页、commentCount与原context一致、单图/三图manifest及保护字节（CAS NOT_RUN）；对独立未合并aab1061/C0021/V0004完成前述检查、条件赞藏、账号旗标、取消后旧条件412及最终状态（6检查PASS）。另编译原生Linux探针，由环境负责人在aab1061的一次性PG55443运行 `TestRealHTTPSFeedDartPostgres`，实际10.02s PASS、零FAIL/SKIP。环境、CA、账号及结果分开；前端未更新服务/数据库。

七张实际宿主Flutter图使用合成内容、Roboto400/500/700、Noto Sans CJK SC及MaterialIcons：[浅色](../design/feed-interactions-ui/assets/interactions-light.png)、[选中](../design/feed-interactions-ui/assets/interactions-selected.png)、[深色](../design/feed-interactions-ui/assets/interactions-dark.png)、[未知重试](../design/feed-interactions-ui/assets/interactions-retry.png)、[原详情](../design/feed-interactions-ui/assets/interactions-detail.png)、[200%文字](../design/feed-interactions-ui/assets/interactions-large-text.png)、[360dp](../design/feed-interactions-ui/assets/interactions-360dp.png)。宿主图不代证设备触控。

## 候选与设备缺陷

APK不进仓库。包 `org.hnuhole.hnuhole_mobile`，main.dart/debug/arm64，min29/target36，原测试签名SHA256 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。同签升级保留数据，环境namespace隔离会话。配方/公开defines摘要在机器记录，私钥和密码不外发。

| 候选 | 源码/环境 | APK SHA256 | 结论 |
| --- | --- | --- | --- |
| 2026102001 | abd9f35/共享0020 | `2c80ed9d6da047a3ff1afc781838389adf160aa6b645c740bb705ef247a505fb` | 历史包，FA-D01，不代证最终包 |
| 2026102002 | c3cc3bb/共享0020 | `56dca4a763c5fca8f1b8ee15b26316d1b56418e3fec8b7e1a6a2497332bb9884` | 360dp修复/原业务限定PASS，CAS NOT_RUN |
| 2026102003 | 5b5cad5/独立未合并0021 | `8b1736e6cb875586ccffc67b94b15532b8cd5776e81e8972e2f42bb3a49b3416` | 历史包，FA-D02/FA-O02，不代证最终包 |
| 2026102004 | f8133cf/独立未合并0021 | `d661bc58414a2789a0c383dc854366b135f7b5a65b50f0bdd89853ecf76be55b` | FA-D02/FA-O02真机复验限定PASS |

当前APK：`E:/Hnuhole-env/source/HnuHole-feed-interactions-ui/apps/mobile/build/feed-candidates/feed-ui-cas-2026102004.apk`，119,545,527字节。绑定独立C50649/V41979、新CA与aab1061；不是共享环境更新或正式发布。

FA-D01由设备唯一操作人在vivo S18/Android15、360dp/font_scale1.0复现互动三行/浮钮靠近分享。阈值308→260，并补360dp单行及大字体换行回归；2002真机已复验PASS，[实际修复截图](../design/feed-interactions-ui/assets/android-360dp-fixed.png)。旧图保留验收目录。该会话另报告2002原文字发布、原生三PNG选择/上传/列表与第2张查看器/原字节保存、主评及回复2→4/删主楼4→2限定PASS。准确版本分别保留，不能提升完整App/iOS/TalkBack/生产结论。前端未操作设备，详见“新版列表 Android 验收与交付”会话的独立报告（原始私有材料不复制到本PR）。2003设备另完成A→B UI登录/新身份、SQL偏好与旗标隔离、20/20/3分页及原离线评论核对封口，按原版本限定记录。

FA-D02为2003忙态按钮失去tap recognizer，外层卡片收下连点误进详情；FA-O02为图片60秒授权到期替换短占位导致操作栏移位。f8133cf以稳定no-op手势层、仅尺寸缓存及立即移除图片子树修复，覆盖按钮/媒体down-up中途状态切换、重读pending/error、迟到图片、账号失效，以及180宽2x/3x文字重读可达。Max最终静态复核无阻断；局部占位滚动设primary:false。2004已由Android唯一操作人实际同签升级、设备pull字节校验一致，B会话保留；FA-D02/FA-O02复验PASS。

有图42与无图36各10次赞+10次藏（约0.35–0.6秒），始终在列表、结束无处理中；忙态忽略点击，不声称全部点击均提交。禁用分享未导航。[有图连点](../design/feed-interactions-ui/assets/android-2004-rapid-both.png)／[无图连点](../design/feed-interactions-ui/assets/android-2004-plain-rapid-both.png)。自然83.84秒到期ImageView=0，卡片/操作栏坐标保持，赞按钮始终[400,1533][584,1677]；断C映射重读失败与恢复成功也保持同Y。[失权占位实际图](../design/feed-interactions-ui/assets/android-2004-media-expired.png)。三张图由设备负责人确认可公开的合成内容，前端再目视核对，普通状态栏图标/时间保留。

2004另用原UI完成主评+回复：详情0→1→2，回列表2；主评赞0→1→0；删除自己的主评后详情/列表均0。环境负责人对同一操作做7项只读SQL核对PASS：各marker唯一发布/受理、deleted=true/bodyPresent=true、可见0及本人评论赞false/0；仅可见删除，不称物理擦除。独立Android报告位于 `E:/Hnuhole-env/source/HnuHole-feed-android-acceptance/docs/design/feed-android-acceptance-20261020.md` 与同名JSON，保留其版本和验收边界。

验收侧最终24项用例按实际被测版本累计13 PASS／9 NOT_RUN／2 BLOCKED；不是2004单版本24项全通过。FA15缺设备可控丢响应入口，FA24等待前后端合入后的最终main重建。独立报告及JSON摘要已核对，未提升完整模块结论。

FA15设备强制“请求已受理、响应丢失”暂缺可控故障入口，明确BLOCKED；普通断网、宿主交错、真实CAS及后端SQL证据分别保留，不互相代证。

## 审查及剩余

用户指定Max独立只读竞态复核，发现并修复未知写解锁、续期清锁、忙时刷新丢失、读重试误发旧写及旧账号回调等问题；最新复核未再发现阻断竞态，前提为后端版本永不复活。审查者未运行测试，不冒充GitHub成员批准。

保持draft，等待后端#30合并授权、main整合/适用CI；2004设备缺陷已限定复验PASS，FA15保留BLOCKED；缺陷继续修复补回归。不自动合并或发布，不更新共享环境、不操作设备。B03/B06增加本范围证据，B04/B07/B12/A03仅回归受影响项，完整模块结论不升级。

5b5cad5的GitHub Feed UI已实际读取job118437037626日志：宿主分析/回归/bundle通过，真实C探针conditional_like因PostFailure失败；该main0020不具条件契约。其它六workflow通过。f8133cf亦已实际读取run39366060156/job118443062283：宿主PASS、conditional_like PostFailure FAIL，其它六workflow已实际确认PASS，不从旧结果推断；#30候选上的真实Linux探针通过单独保留。
