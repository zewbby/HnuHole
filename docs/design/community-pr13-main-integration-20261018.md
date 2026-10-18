# PR #13 与最新 main 整合回归

2026-10-18，分支 `codex/community-flutter-pages`，PR [#13](https://github.com/zewbby/HnuHole/pull/13)。社区起点 `2abda5935e2e5618ca90bb7e60314d7c6572fe85`，主线固定 `8fa9cbc8bc69e490ddfcf4d0fce4e289e32e7903`。先整合main `65a8dbf`（提交 `8a72f75`），再补入其后只含文档/契约工具的main增量 `8fa9cbc`。在 `E:/HnuHole-pr13-main-20261018/repo` 独立 clone 正常合并；保留两个真实父提交，不改写历史、不强推、不向 main 推送。

## 冲突与保留能力

76份原始冲突均逐文件整合。由于主线经 squash 导入大量共同功能，使用已提交 `7e185b1` 作为内容对齐参考进行逐文件三方合并；它不替换 Git 祖先。代码与证据的两侧输入/结果摘要见机器记录。文档保留两侧有日期的历史，台账按稳定ID整合；旧验收不能借给新候选。

保留 main 的图片选择、上传、查看器、原始图片持久化与权限、图片生命周期擦除、B5闭号终态先持久化再清理以及 epoch/closureId围栏。原生认证、Passkey、SQL、manifest及依赖锁均与 main 相同。保留社区通道单次语义、中文导航/数字、身份选中语义、必填/列表失败自动提醒、恢复码与OEM历史证据和获准USB传输守卫。

整合修复：F4镜像入口补复制 `packages/image_viewer`；旧纯文字必填断言适配既有“正文或图片”契约，仍验证 live region、输入框与不发布；stage1/stage2共享传输 API 同步。默认未获准Windows身份仍在读取manifest、绑定socket或ADB前阻断；没有为过测试放宽认证。现有产品CI扩为全mobile和工具回归。

## 当前源码实际验证

| 检查 | 结果 |
|---|---|
| checks | PASS，分析0、全mobile 395项 |
| auth-regression / R05 | PASS，真实Flutter→C/V HTTPS→一次性PostgreSQL |
| integration / F4 | PASS，真实main根、身份/通道固定、原command核对、删除丢响应及8项F4检查 |
| server | PASS，完整真实SQL/race及vet入口 |
| posts-privileges | PASS，受限角色与正式schema |
| auth-runtime | PASS，实际C/V进程、正式迁移、隔离runtime角色、Gate/mTLS/隐私检查 |
| 最终vet / build | PASS |
| 图片验证器 / 图片SQL | PASS，含子项 251 个通过事件，0 个跳过事件 |
| 图片组件 | 分析PASS，112项宿主测试PASS |
| Passkey / vault包 | 两包分析PASS；Passkey 9项Dart宿主测试PASS；vault无Dart测试入口，原生测试本轮未执行 |
| 工具 / runner隔离 | 191项Python PASS；专用root/SDK缓存/端口/锁/外来DSN与路径守卫PASS |
| 最新main契约增量 | 14受保护操作、9文字＋2图片向量、6份OpenAPI规范PASS；只证明静态契约 |
| Android ARM64 | 标准Debug、Release构建PASS；未安装、不发布 |

本轮新源码输入 595项，规范化指纹 `65070a6f14d23b236ef13df7b3e5f10f6fd0386b5d9f56295e53d9b261a4e8ac`。585项镜像输入与10项直接验证的OpenAPI输入均逐项核对一致。当前代码树对应上述执行；最终仅交接文档和CI描述更新。没有用旧334、恢复码8项或OEM7项替代本轮回归。详细命令/开始结束/退出码及日志摘要见[机器记录](community-pr13-main-integration-20261018.json)。外部执行根 `E:/HnuHole-pr13-main-20261018`；Linux独立工作/缓存根 `/home/hnuhole/hnuhole-community-flutter-f4-p13`，独立SDK根 `/home/hnuhole/community-pr13-main-20261018-tools`，PG55718只用新建私有socket库。实际runtime项目按runner随机命名和自有trap清理，未连接原设备或认证数据库。

首次工具回归8处参数错误及修复后182PASS、补入归档契约增量后191PASS均保留原日志。posts-privileges首轮因原任务目录生成109字符Unix socket路径而在数据库启动前失败，AF_UNIX实际返回路径过长；只缩短本任务根后路径99字符，重跑通过，没有更改SQL、权限或检查。开始时发现旧专用SDK复制件的clang为零字节，在构建前保留该复制件、另复制现成完整SDK。新增OpenAPI检查首次缺少固定验证库，之后只在任务venv补仓库锁定的PyYAML6.0.1和openapi-spec-validator0.9.0。没有安装大型工具链或修改共用SDK、产品锁文件、全局PATH/代理/证书。

外层临时脚本曾因运行中改写而在所有构建子命令成功后发生收尾解析错误；已保留首轮日志，并对稳定脚本整段重跑成功。第二次Release在线依赖查询较慢，最终正常完成，应用锁文件未变。

## 遗留与审查边界

跨设备Passkey NI-X02按用户要求继续延期，不循环Google扫码。恢复码8项/OEM7项仍只证明原固定APK与设备链，本轮未操作手机，合并候选的原生设备状态NOT_RUN；当前原生插件与main逐字一致，构建/宿主回归不冒充新设备验收。iOS、生产/灾备/独立审计、完整App均不升级PASS。

最新协作policy与当前PR历史存在独立阻碍：旧分支名 `codex/community-flutter-pages` 不符合新命名规则，79条继承非merge提交标题不符合新格式。正常合并不会改变这些历史；本任务保留用户指定分支，不自动例外、改policy或强推。最终GitHub检查按PR真实结果记录，不能将产品回归PASS等同于所有CI/成员批准通过。PR保持draft，独立成员审查及协作送审安排仍待维护者处理；没有合并、发布或部署。
