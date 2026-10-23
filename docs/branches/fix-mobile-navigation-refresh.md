# MOBILE-NAV-REFRESH-01 导航、刷新、图片与个人页加载

- 更新时间：2026-10-23（Asia/Shanghai）。
- 分支：`fix/mobile-navigation-refresh`；基线 `e8ff488`。用户要求分支名不含codex。
- 范围：用户视频问题1／2／5先完成，随后明确加入3／4，现覆盖全部五项。用户随后授权前后端更新、真我安装2303并开始统一验收。
- 状态：[PR #57](https://github.com/zewbby/HnuHole/pull/57)已Squash合入main `1686a063328bb919ee8a38b51e0ae70f4d6536e2`；最终head `f1e85fc` 的20项适用CI全PASS、独立只读审查无阻断（非GitHub成员批准）。开发后端和真我限定验收已完成，用户导航视觉确认、动图保存、短时Profile帧采样及新增30分钟照片大图列表内存测试通过；原生相机多样本、更久时长与生产仍待验，未生产发布。

## 实现

1. 四个同级栏目使用按需创建、保留状态的 `PrimaryTabs`／`IndexedStack`，外层只有一个底栏；切换直接显示目标栏。返回键从非首页回到保留的首页；详情／设置保留独立路由。账号及授权窗口变化重建受保护栏目。
2. 同通道刷新期间保留帖子组件，成功才替换第一页；失败保留内容和分页游标。切通道／账号清除旧作用域，新屏蔽规则立即过滤旧行。
3. 图片仓库按账号、授权代次、postId共享清单和资源Future，同帖并发请求合并；列表与详情分别持有消费句柄，释放一个不影响另一个。闲置LRU最多12组、48MiB估算权重（编码字节＋包含动画帧及ResizeImage的保守解码估算）；正在展示的资源不计入闲置配额。无磁盘缓存，读字节并发最多2。释放最后一个消费方时尚未完成的请求立即撤销，不保留队列／迟到结果。
4. 显式 `X-Post-Preview: thumbnail-v1` 协商独立预览；服务端用现有受限Pillow子进程按需生成EXIF归正、最长边640px、最多512KiB的WebP静态首帧。列表按feed返回的有序尺寸先占位；新客户端连旧后端时使用稳定方形占位及原来源。Flutter按实际显示尺寸／DPR以ResizeImage限解码至1280px边界。动图预览标注“动图”；完整查看及主动保存仍读取原图、保持原格式／动画／字节，保存每次重新授权。
5. “我的”并行读取帖子、任务与本机数据；主体先展示，身份资料独立加载／提示，已有本体身份时不再等待发布上下文。翻页不重读资料，栏目往返保留数据、空态和滚动位置。

图片缓存复用不延长原清单最多60秒的授权窗口，失效是终态。退出／换账号、权限失效、已知删帖及时清除资源与解码缓存；无推送事件时沿用既有到期撤销。旧消费方释放后不能收到另一个消费方仍持有的迟到结果。

缩略图每次读取复用原资源／会话／C Gate授权；编码在SQL事务外执行，完成后再次读取受保护清单，编码期间发生的删帖／退出／冻结先于返回生效。校验器沿用两并发、384MiB地址空间、5秒CPU、8秒超时、可信helper哈希检查；不新增依赖、SQL迁移、公开URL或持久派生缓存。无协商头时后端继续输出原严格v1形状，兼容旧客户端。

## 自动验证

- PASS：原pub.dev锁文件 `flutter pub get --offline --enforce-lockfile`，无依赖升级。
- PASS：本分支 `flutter analyze --no-pub` 零问题；完整 `flutter test --no-pub --reporter expanded` 为742 PASS／1 SKIP。跳过项为缺少专用 `DM_HOST_FIXTURE` 的既有真实私信联调。
- PASS：`flutter build bundle --debug --no-pub`。
- PASS：Go全包 `go test -mod=readonly ./...`、build、vet；此无DSN宿主检查中的SQL跳过不代表SQL通过。最终HTTP测试修改后，HTTP包test／vet另行通过。
- PASS：专用Linux源码镜像及新建私有socket PostgreSQL，`POST_MEDIA_TEST_PATTERN='^(TestPost|TestRealHTTPSPost|TestFeed)' sh authlab/run-post-images-isolated.sh`，含race：104个顶层／含子项334 PASS，1 SKIP。跳过的feed Goose新建／升级项缺专用Goose fixture，本轮无迁移，未将其记通过。
- PASS：补加真实HTTPS“缩略图编码期间删帖”的最终授权回归；单独新建隔离库重跑对应case及前置媒体／posts／runtime包，30个顶层／含子项79 PASS，无SKIP。
- PASS：固定Pillow12.3.0 Python合成图5项，覆盖方向、元数据剥离、动图首帧、原图不变、尺寸／传输预算和坏图拒绝；11份OpenAPI／contract检查通过。
- 新增客户端边界覆盖：并发清单／字节合并、独立释放、跨滚动复用、LRU与字节淘汰、复用不延长到期、账号失权清理、实际MemoryImage／ResizeImage键定向驱逐、预览／查看／保存独立读取、几何预留与DTO严格限制、动图标记。1／2／5原有导航中间帧／返回／刷新／个人页回归仍在全量中通过。
- CI：feed-ui列入导航／个人控制器回归；post-images沿用全量客户端／Go／隔离库并补Python单测入口。远端CI尚未运行。
- 本机日志：`E:/Hnuhole-env/media34-{all-tests,analysis,bundle,go-all,go-build,go-vet,sql-https,final-gate,python,openapi}.log`；日志不纳入Git。

## 候选包与交接

- 统一候选 `2026102303`／`0.1.0-media-cache-preview`，包名 `org.hnuhole.hnuhole_mobile`，APK构建／apksigner／kernel与arm64 engine存在性通过。路径：`E:/Hnuhole-env/deliveries/media-cache-preview-20261023/hnuhole-media-cache-preview-2026102303.apk`。
- SHA-256：`76c0c978ac69ac8daea0df452a6cc08176691f3397122130826256c7ea936f83`；测试签名证书SHA-256：`adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。
- 独立构建镜像冻结既有2301认证反馈代码，来源于此前2302候选快照；不追随另一认证工作区后续修改，也不夹入本Git分支。冻结后完整客户端744 PASS／1 SKIP、分析0、bundle PASS，源码哈希核对通过。镜像与build-inputs／delivery记录保留在本机。
- 认证overlay哈希：auth_screen.dart为 `4f10351e3ae3698e8d4788aaf53b89519b8a5798dc30dd315a12103f5dec8458`；auth_screen_test.dart为 `d17fc5779616a2b53c39a184c4d5120a95d039634013eced93920ad0cf3a462d`。
- 此前2302只含1／2／5的候选包保留为历史制品，未安装；本轮2303也未安装。没有操作手机业务界面或改动共享服务。
- 真缩略图和feed准确几何需要部署本轮服务端及可信helper，并更新validatorSHA256后重启；仅装新APK连接旧服务时仍使用兼容原图／稳定占位。此次未部署，不宣称手机已生效。
- 待用户恢复验收后：四栏快速往返／详情返回、刷新断网恢复、长列表上下滚动后的缓存／内存与帧表现、横竖与动图原图查看／保存、过期／退出／删帖、“我的”首次及往返。独立review、远端CI、真机视觉和帧性能均NOT_RUN。
- B03／B06／B10／PM01／IV01仅记录本轮限定证据，不升级历史完整模块、iOS或生产结论。相关[台账](../design/module-acceptance-ledger.json)、[总交接](../design/HANDOFF.md)、[媒体契约](../design/post-image-media-contract.md)已同步。

## 2026-10-23 续：已授权并执行更新／真我统一验收

- 开发C替换为本轮community-media-2303，可信helper及其SHA同步更新，Pillow12.3.0启动探针与TLS ready通过；在C Gate行锁内停止旧API／watch，同代次resume并重启，原授权代次及会话数量未变，未调用recover／迁移。V继续原服务。本机reconnect入口已指向此次配置及二进制，旧文件与回退路径保留。
- 真我原包2306已备份，`adb -s 7e0660f1 install -r -d <2303.apk>`保数据覆盖成功，dumpsys核对2303。登录既有合成front_b测试账号，未记录凭据，未操作vivo。
- 单底栏与目标栏目静态结构、个人空态往返、系统返回首页通过。短期TLS观察只记录路径／状态／长度，不记录头、令牌或正文；列表协商尺寸正常，预览1834–2196字节，点击进入原图查看正常。24.48秒滚动及栏目往返中，每张已读取预览仅一次；个人帖子／任务未随同一次启动内栏目往返重读。此为合成样本，不证明实际照片流量或帧性能。
- 只撤掉真我C USB转发模拟断网，刷新错误时原帖子／图片仍在；恢复后重新刷新清除错误并显示内容。一次脚本截图与故障注入有重叠，其fast-tabs截图不作为独立无故障证据；断网和恢复专门截图、初始栏目组、后续返回组分别保留。
- 系统screenrecord两次直接退出1、无录像，因此只记静态结构PASS，切换瞬间重影、真机帧性能仍NOT_CONFIRMED，不能标五项全面验收完成。60秒后图片租约终止提示已实际观察，缓存没有延长原授权。
- 临时观察代理已停止，手机恢复直连开发C。测试账号、2303和首页留给用户继续验收，设备占用标记保留本任务；不自动回退2306。前述“未安装／未部署”均为本次授权之前的历史状态。
- [本轮脱敏证据](../design/validation/mobile-nav-refresh-realme-20261023.json)，原始截图／界面树／请求记录在 `E:/Hnuhole-env/media-cache-preview-20261023/device-realme/`。尚未提交／推送／合并或生产发布。

### 用户视觉确认

用户在真我2303上明确确认切换瞬间重影／闪首页“这个是好的，没问题”。导航视觉验收PASS，依据为用户实机确认；不扩展为帧性能或其他全部项目的用户验收。

### 真我动图保存与帧性能续验

- 真我通过系统照片选择器发布合成GIF与动WebP各一张，原图页分别保存，均提示“已保存到相册”。MediaStore显示正确格式；从相册拉回的两份文件分别与上传源逐字节SHA-256一致，均为4帧。HnuHole原图页截图跨时刻可见两类动图播放。ColorOS相册的ACTION_VIEW页面只显示首帧，这是外部相册播放限制；原生保存保留了全部帧，不把外部播放器行为算作应用保存失败。
- 性能专用Profile包2304已同签安装真我，在60Hz下用Flutter FrameTiming和SurfaceFlinger呈现时间测了12次底栏切换、8次列表滑动、3次下拉刷新、GIF/WebP原图页。切栏357帧、build/raster P95为5.400/5.190ms；列表332帧，3.039/6.791ms；刷新204帧，6.412/6.794ms。三者各有至多1帧单独超16.67ms，末127个呈现帧样本均无超过20ms的连续活跃间隔；未见持续超预算。动图页134帧，4.730/5.666ms，呈现间隔受动图节奏影响，不用来评价滑动掉帧。
- 初版Profile包因开发CA仅允许Debug而在启动时报错；已将开发信任限定为Debug或显式`AUTH_DEV_PROFILE=true`的Profile，仍要求两个不同的固定loopback HTTPS源，Release保持拒绝。修正后Profile真机启动、账号与帖子保留；`app_transport_test.dart` 4项PASS。性能包加帧回调仅作测试，不进入2303日常包。
- 采样后已在真我保数据恢复2303并启动至首页；2304性能包留在本机交付目录。
- [结构化证据](../design/validation/mobile-animation-frame-realme-20261023.json)；原始帧样本在本机 `E:/Hnuhole-env/media-cache-preview-20261023/device-realme/frame-profile-2304.json`。只覆盖短时合成内容，真实大图长列表和长时间内存压力仍NOT_RUN；远端CI和独立review以PR最终回执为准。

### 主线整合与送审

- 本分支提交 `eb1f38f` 保存五项改动和真我续验证据；整合 `origin/main` 的 `93d3ed6`。处理的运行时代码冲突是主线私信通知点击与新单底栏结构：通知先选中保留的私信栏目，再打开目标会话，返回只有一个底栏且身份正确。
- 整合后Flutter分析0、全量`flutter test --no-pub test`为803 PASS／3 SKIP；新增私信通知与底栏定点4 PASS，debug bundle构建PASS。Linux隔离源码镜像Go全包test/build/vet PASS。远端CI及独立审查待PR回执。
- [PR #57](https://github.com/zewbby/HnuHole/pull/57) 首次CI发现feed命令行联调探针不能编译引入Flutter `Size`的传输层；`f7c3968`已改为纯Dart宽高记录，只在界面映射`Size`。两份探针本机编译、相关Flutter测试及分析PASS。独立只读审查对完整改动和此修正均无阻断；GitHub成员review未提交。
- 送审期间main新合入启动欢迎页修正 [PR #56](https://github.com/zewbby/HnuHole/pull/56)，本分支已整合`6cd686f`，保留恢复会话期间欢迎页行为。新基线的远端CI和测试以最新提交回执为准。
- 最终主线整合后本机Flutter全量805 PASS／3 SKIP、分析0；两份feed命令行探针编译PASS。新增启动页修正与五项功能一起进入PR #57的最终CI。

### 合并回执

- [PR #57](https://github.com/zewbby/HnuHole/pull/57)于2026-10-23 Squash合并，主线提交`1686a063328bb919ee8a38b51e0ae70f4d6536e2`，最终待合并head`f1e85fc2b51050170eb7e7955638be6b8d80a585`；20项适用CI全部成功，包含曾失败后修复的真实feed联调、Flutter、Go／PostgreSQL、Android候选及预演。独立只读审查无阻断；GitHub成员review为空，未伪造批准。
- 合并当时真我保数据安装日常2303、开发C维持本轮后端；代码进入main不代表生产发布或把设备限定验收提升为全模块通过。彼时大图长列表／长期内存、iOS及生产环境未验；大图30分钟续验见下方。

### 真我照片大图长列表内存续验

- 在专用合成账号通过受保护开发API建立30条3000×4000 JPEG帖子，图片源自摄影样本，经放大和色彩／噪声变化，每张约2.69–2.71MB；并非原生相机原片。Profile2304真机从首页滚动到分页，32轮都实际点击“加载更多”、走到较早帖子并返回顶部，历时1807.9秒，采集77个`dumpsys meminfo`样本。
- 同一PID维持全程；顶部同位置PSS从254.6MB到254.9MB，前8轮／后8轮中位数255.6／256.1MB，全部样本252.6–268.2MB，峰值后回落。运行结束后另行手工抽查，闲置约两分钟PSS为252.6MB、logcat相关关键词0匹配；这两项未纳入逐轮原始JSON，仅作补充观察。原生堆首末为49.1／55.0MB，在总PSS回到基线的同时仍有约6MB差异，暂不能单独判为泄漏或完全回收。
- 结论限定为本机30分钟、多页照片型JPEG负载下未观察到持续PSS增长、进程重启或OOM；不代替原生相机多样本、隔夜、iOS或生产验收。已删除本轮创建的30条帖子，保数据恢复真我日常2303并重登测试账号，首页可见原有帖子；无需代码修复。见[结构化证据](../design/validation/mobile-large-photo-memory-realme-20261023.json)。
