# 帖子图片前后端联合联调任务单

> **2026-10-15 主App帖子图片S18真机联调已完成约定范围：**修复实现 `fd2e4c04f48b29ddda0142660188988c4a655f5f`，分支 `codex/post-image-integration`。实际原生Picker/原图跨进程恢复、九图C/V/SQL上传及缺项补传、失败编辑同任务RETRY、受保护查看、Gal原格式保存与Gallery动画回放、删帖/退出/切账号/迟到隔离取得本轮证据；修复成功核对后残留旧错误提示。最后修改后分析0、相关宿主69、Python守卫15、bundle、Android Debug20263116构建/验签及上机复验PASS。手机窗口结束，系统设置已恢复、自己的App/后端已停、映射已撤；Linux专用私钥/库已清理。Windows清理被自动审批拦截，材料仍保留且私有目录ACL受限，不能写成已清理。iOS原始选图仍未实现，最大资源预算/库存升级/生产与评论私信另列；不重测旧TalkBack、不宣称全模块/双端通过。见[本轮报告](post-image-android-device-report.md)与[机器记录](post-image-android-device-verification.json)。下方旧记录保留各自版本与范围。

2026-10-15；用户指令“做完整前后端联调”。仅在独立 `codex/post-image-integration` 完成，不合并 main、不部署、不操作手机或其他会话环境。

1. **固定与装配**：前端 `075b567ee6093319a0dcb48ab40919aada5cb8f2`，后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587`，共同基线 `e0c128033682923d519ea99546d72503b085a99e`。独立clone `E:/Hnuhole-post-media-joint-20261015/repo`，Linux副本/私有工具、缓存与空数据库根 `/home/hnuhole/post-media-joint-20261015`（WSL虚拟磁盘在E盘）。合并双方交接与台账，保留历史范围，不占用或清理认证/社区资源。
2. **真实链路、修复与交付**：运行实际 `cmd/api`、`cmd/verifier`、正式 Goose 和受限运行角色，图片使用锁定 Pillow/libwebp 子进程。实际 Flutter 页面/API/控制器、文件 SQLite 串联九图/空正文、媒体摘要、丢CREATE响应与进程恢复、部分补传/丢PUT收据、完整验证后公开、原图读取/保存resolver、取消保留原草稿、失败编辑新尝试、失效/迟到响应和真实60秒租约。每项由客户端断言与独立SQL/计数交叉核对，修复实际问题后重跑受影响检查；同步完整宿主回归、后端SQL/race/vet/编译/校验器/OpenAPI及原生构建范围，正常提交推送本分支。

原生选图器、Keystore/Keychain、Gal系统相册、物理交互与iOS不由宿主替身证明；本轮没有手机窗口，不调用ADB或安装App。宿主只在选图、vault和相册写入边界使用合成来源/文件替身，真实C/V、Gate、业务、HTTP/TLS、PG、图片校验器不替换。

工具不得升级共享SDK。复用现有 Go1.22.2、PostgreSQL16.15、Goose3.22.1和同版 Flutter3.47.5/Dart3.13.4的独立副本；新 Python 只向本任务环境安装固定 Pillow12.3.0（wheel约6.9MB）。不复用真实账号、Bearer、密码、恢复材料或签名。代理只注入明确网络断点并原样转发真实响应，不伪造业务受理/公开/授权结果。

当前执行结果以最终 `post-image-joint-report.md` 与 `post-image-joint-verification.json` 为准；计划本身不登记通过。
