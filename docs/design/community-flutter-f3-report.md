# Flutter 社区文字页面 F3 实现与验证

日期：2026-10-09（Asia/Shanghai）。分支：`codex/community-flutter-pages`。对应任务：[F0–F5计划](community-flutter-pages-plan.md)。本轮实现按F2锁定的`514a944560988e3d8d599e6f9fe9d5d99fe07f88`逐文件复用，不合并后端工作树及未提交T4，不代入后端历史通过记录。

源码版本：`eb6c9143d785a01fcc8b141b323accf0fbf812d2`；当前F3完成，分析0问题、20文件308项PASS（其中SQLite30、controller34、screens23含14帧），FAIL0／SKIP0。92文件源码与实际Linux测试镜像和此Git提交一致，源指纹见机器记录。全部平台／真实系统链仍按下方NOT_RUN。

## 当前范围

F3覆盖文字编辑、确认、默认／选择身份、通道最新列表、详情、本人内容混排、本机多草稿、失败重试、未知结果核对及本人删除。主导航已接通通道页与本人入口；身份管理返回后刷新当前公开投影。作者与所有权分开：公开DTO不含内部账号／身份ID，删除能力单独查询。

源码入口：`apps/mobile/lib/src/posts/`；`apps/mobile/lib/src/storage/post_store.dart`；`apps/mobile/lib/main.dart`；`apps/mobile/lib/src/config/mobile_environment.dart`；闭号桥为`auth_flows.dart`和`auth_state_codec.dart`；原生业务key/path/purge为`packages/auth_vault/`。固定部署配置在打开任何store前校验C与V HTTPS origin，scope保留历史URI字符串字节规则；没有默默切换旧账号库的命名空间。

## 页面及状态

[F1 22场景清单](ui-reviews/f1-completion-audit.md)是图稿依据，正式PNG没有改动。文字片的通道／本人采用批准的双列自然高度混排，详情沿用标题、作者、正文阅读顺序；编辑、确认及身份面板映射现有白框／灰蓝页面。未来图片、评论、点赞、收藏、搜索、标签筛选与置顶没有接口，本片隐藏入口，图稿保留完整产品范围。

确认后先持久原发布意图，再立即返回原通道；处理中、失败和未知入口留在本人列表。保存或ACCEPTED不产生成功提示，仅本机原CREATE／RETRY意图首次持久核对到PUBLISHED才生成当前通道短提示，重复核对不重复提示。失败重试保留原身份／通道／attempt关联；UNKNOWN、RESULT_EXPIRED不能当成可以新发的失败草稿。本人删除确认与丢回包核对成功后清正文、移除列表、直接返回来源页，已删围栏阻止迟到详情／分页重新显示正文。

确认弹窗正文指定SimSun／Songti／Noto Serif CJK fallback，动作仍无衬线及朱红确认；真实手机是否具备相应宋体族待F5字体验证。截图测试可加载机器现有微软雅黑与宋体，仅用于实际Flutter几何／中文排版复审，不打包商业系统字体或冒称手机字体已验。当前default-v1／inactive-v1均使用统一图标投影，没有虚构身份照片或赞数。

## 持久化及补齐的边界

- Drift真实文件库保持三表schema v1；打开时先检查user_version和三表DDL，再运行持久PRAGMA／迁移。未来版本、旧有表的版本0、缺表／坏DDL拒绝且保留原文件。该检查允许额外trigger/index供受控故障注入，不声称完整sqlite_master白名单、全库抗篡改或快照抗回滚。
- 草稿、原intent／digest、task/version等以AES-GCM密文和AAD绑定。新retry buffer为CSPRNG随机行ID；旧`retry-task-version`在同一事务重新绑定AAD并迁移command FK，保持revision、payload、原摘要及恢复关联。检索关联仅在解密后比较，重复关联拒绝猜选。
- 删除COMMITTED先持久compact，再发页面成功信号。写盘失败继续核对同一命令；连点、丢响应与重复确认只用原命令，不新增POST。通知／异步核对期间再次复核账号与授权，原账号迟到结果不会污染新账号。
- 业务vault/key/path与认证namespace分开。关闭仅以持久权威CLOSED_RELEASE_PENDING／RELEASED及originalAccountId清理原scope；退出、401、冻结和未知状态保留隔离数据。Android将closed检查与read/write/path放入和purge相同的同进程多engine临界区，防止迟到writeOnce在清理后重建key。不是并发多OS进程锁证明。

## 运行与证明范围

最终命令、计数、被测源码指纹及结果见[机器记录](community-flutter-f3-verification.json)。锁定来源与具体改动见[来源清单](community-flutter-f3-source-lock.json)。

入口：`tools/run-community-flutter-f3-linux.sh prepare/analyze/test`，现成Flutter3.47.5／Dart3.13.4，`flutter pub get --enforce-lockfile`使用锁文件的pub.dev及SHA。runner仅在任务专用Linux目录复制源码与解析依赖；真实SQLite测试使用系统libsqlite3，未启服务端／数据库服务器或设备。初次将镜像源用于官方源锁文件被enforce拒绝，改回相同pub.dev后版本／摘要保持；Unicode测试夹具路径遗漏已补齐。页面复审发现的Semantics const编译错误已修复，随后实际看图补正AppBar字体继承与过渡采样，最终14帧已覆盖诊断版，并[逐帧复审](ui-reviews/community-flutter-f3-ui-review.md)；最终结果以最后源码完整回归为准。

主测试：`post_protocol_test.dart`（9摘要、7字素及1093个官方Unicode16边界）、`post_api_test.dart`（本机TLS fixture与14操作、header／错误／redirect）、`post_models_test.dart`、`post_storage_test.dart`（真实SQLite）、`post_controller_test.dart`、`post_screens_test.dart`、`post_closure_cleanup_test.dart`及`mobile_environment_test.dart`。API的TLS fixture有真实socket／TLS但handler是测试替身，controller和widget网络用替身，不能等同真实C/V、SQL或原生vault。

## 尚未执行与下一阶段

| 验收 | 状态／原因 | 环境与入口 |
|---|---|---|
| F4当前源码＋最终认证候选完整App→真实C/V／Postgres／Gate | NOT_RUN，本片仅F3，认证候选尚在独立会话推进 | 固定认证候选并整合，新增当前SHA真实链；不可借用T4旧分支证据 |
| Android业务7项instrumentation及完整App构建／跨进程／重启／备份、原生密钥故障 | NOT_RUN，本轮未操作设备或构建APK | 当前SDK／专用测试设备安装本版本两APK，再`adb shell am instrument -w -e class org.hnuhole.authvault.AndroidBusinessStorageTest org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner`；现`tools/run-android-vault-probes.ps1`只跑认证类，不能代验业务7项 |
| iOS构建、Keychain、安装、系统字体与设备恢复 | NOT_RUN，缺macOS完整Xcode/iOS目标 | 同当前源码于macOS／iOS执行，保留SPM与CocoaPods源码路径 |
| 物理IME、手势、安全区、读屏焦点、真实48dp命中／系统大字、系统宋体fallback | NOT_RUN，host widget／截图只验证自身配置 | F5专用设备矩阵；模拟输入和PNG不能代证 |
| 图片／标签／搜索／赞藏／评论／通知／治理／作者编辑 | NOT_IMPLEMENTED，超出文字片范围 | 后续独立任务实现后新增接口／验收 |

逐模块源码／测试／证明范围在台账currentCommunityFlutterF3.coverage与testReferences映射；308是一次共享mobile回归，不是每模块各308次。模块映射：B03文字feed、B05文字发布、B06正文／最小作者删除、B10本人文字内容、B02身份投影与绑定；A12/N01共享持久化及账号授权边界重新打开当前回归，X06/X07的真实身份／闭号联动仍待F4/F5。整模块和生产状态没有因F3 scoped PASS变为PASS；旧SHA的基础记录完整保留。

只保留源码、测试、定稿图与小型脱敏记录；本任务专用缓存／SQLite／截图临时产物已核验归属并清理，目标目录已确认不存在，不动现成SDK、AVD、其他会话服务／数据库或用户数据。提交和普通推送按用户已有授权执行，没有部署。
