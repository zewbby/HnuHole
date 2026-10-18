# 电脑网页审核工作台

`apps/admin` 是唯一静态源码目录，无构建依赖或第三方资源。由 C 的同源 HTTPS 服务提供：

| 路径 | 文件 | 类型 |
| --- | --- | --- |
| `/admin`、`/admin/` | `index.html` | `text/html; charset=utf-8` |
| `/admin/styles.css` | `styles.css` | `text/css; charset=utf-8` |
| `/admin/app.mjs` | `app.mjs` | `text/javascript; charset=utf-8` |
| `/admin/core.mjs` | `core.mjs` | `text/javascript; charset=utf-8` |

接线只允许上述预定义文件，不能把整个目录作为文件服务器公开，不能暴露测试、文档或目录索引。
响应设置 `Cache-Control: no-store`、`X-Content-Type-Options: nosniff`，并通过 HTTP CSP 增加
`frame-ancestors 'none'`。页面内 CSP 已限制脚本、连接为同源、图片为同源及 raster data URL，禁止对象和外部表单。
部署入口必须使用 HTTPS；HTTP 页面禁止登录。不提供跨域 API 地址输入，不使用 CDN、遥测、字体服务或 Cookie 凭据。

登录复用 `POST /api/v1/auth/sessions`：32 字节规范 base64url `Idempotency-Key`；
JSON 仅含 `username`、`password`、随机 16 字节 base64url `installationId`。
随后读取 `/api/v1/moderation/me` 获取最小角色与六位平台编号。返回的内部账号 ID 不展示。
现有认证的单设备接替规则继续生效，因此管理人员应使用专用账号；本页不另造认证系统或修改互斥规则。
密码提交后清空，Bearer 仅存在当前页面内存，刷新／关闭后不恢复；禁止存入浏览器持久存储。
退出立即清 Bearer，再按既有 `HNUHOLE/SESSION-REVOKE/V1` 域导出仅能撤销旧会话的能力并调用
`POST /api/v1/auth/session-revocations`。网络失败时保留内存中的撤销能力供“重新确认退出”，不会恢复 Bearer。
关闭页面会丢失未确认的撤销能力，不能将本地清除表述为服务器已确认撤销。

当前工作区包含案件列表、授权证据、领取、下架／禁言／封禁、仅针对本案身份的违规昵称／头像重置、申诉独立复核、账号列表／平台编号查询、处罚撤销、审计及管理员权限变更。
审核员界面隐藏封禁及权限管理，申诉按处罚类型和原处理人回避；服务端仍必须逐次执行权威授权。
材料只经 `textContent` 展示，禁止 HTML 内容；补图只接受 PNG/JPEG/WebP/GIF 的合法 base64，不执行 SVG 或服务端链接。
任何页面都不遍历／输出完整账号对象、邮箱、验证标记、槽位映射、其他面具或举报人身份。

案件命令、申诉结果、处罚撤销及角色变更使用内存中的 UUID `commandId`。
结果未知时保留原命令与负载，原样重试不会生成新命令；不能改写原因或期限另发。
冲突提示先刷新当前记录；版本与重复事实的最终裁决由服务端事务负责。
重载页面会丢失待核对命令，重新登录后必须先加载案件／处罚现状，不能把客户端超时当成未处理。
账号处罚提交前读取该账号全部有效处罚，显示各自独立计时后的预计恢复时间；未核对成功时禁止提交账号处罚。
图片材料、处罚投影、通知投递、申诉额度和案件竞态均由配套 API 负责，本页不创建客户端替代事实。
案件及待复核申诉使用服务端 `(createdAt,id)` 游标分页，原样传回 `before`，不自行按时间推算下一页。
申诉工作区默认待复核队列，已结案材料保留在原工单与通知对应详情，不增加历史统计页。
账号工作区初次进入即展示有限账号列表；可按六位编号搜索，清空编号或点击“全部账号”回到列表，支持 `nextBefore` 追加分页。
列表只展示平台编号、注册时间、账号状态、已确认违规数和“查看处罚”入口，不通过列表展开其他面具或历史发言。
案件详情只自动展示首份举报材料，申诉详情只自动展示首批材料；存在 `nextReportsCursor`／`nextMaterialsCursor` 时明确提示后续材料未加载。
“加载后续材料”将 opaque cursor 原样交给案件 `/reports` 或申诉 `/materials` 接口，按服务端升序一份一份追加，保留先前批次；失败保留旧材料和原 cursor，允许重试。
不自动扫描所有举报或追加批次，也不把首批材料标成完整证据。页内追加同时受会话 epoch、详情请求版本与当前挂载状态保护，切换案件、退出或登录失效后的迟到结果不能串入新详情。

本轮界面采用中文系统无衬线、白色阅读区、暗灰蓝操作色及双栏案件工作区，兼顾键盘焦点与窄窗折叠。
已应用项目 `frontend-design`、`ui-ux-pro-max` 及 Operate 参考；两次设计系统检索仍偏营销，未采纳其营销布局、字体下载和发光效果。
定向 UX 检索采纳了表单可见标签与错误朗读规则。本页面不是已有手机图稿的重画，不声称全局主题已定稿。

验证：`node --test apps/admin/test/*.test.mjs`，或在本目录运行 `npm test`。
测试覆盖真实登录形状、撤销秘密、未知提交重试、旧响应围栏、角色回避、重叠期限、图片 allowlist 与源码隐私边界。
浏览器合成夹具另用 `node apps/admin/test/browser-smoke.mjs`：环境变量 `PLAYWRIGHT_MODULE` 指向已有 Playwright 包，
`ADMIN_UI_TEST_ROOT` 指向本任务独立运行目录；可指定 `ADMIN_UI_BROWSER` 为已有 Chromium/Edge 可执行文件、
`OPENSSL_BIN` 为已有 OpenSSL。它仅在随机 loopback 端口生成一次性自签 HTTPS 夹具，浏览器证书例外只属于此合成测试 context，
不修改系统证书或产品 HTTPS 检查；测试结束关闭浏览器与服务并清理本次 TLS 材料。截图写入指定运行目录，不提交到源码。
夹具操作覆盖审核员禁言、两类资料重置、案件／申诉追加分页、举报／申诉材料逐批加载与失败重试／迟到页围栏、初始账号列表／搜索／分页、申诉复核、处罚撤销、管理员永久封禁选项与权限管理、材料 XSS、图片预览、390px 窄窗及零第三方请求。
测试替身不代证真实 HTTPS／SQL／角色权限、通知投递或物理设备验收；这些结果随本任务整链回归另记。

真实 C／SQL 浏览器入口：`node apps/admin/test/live-api-smoke.mjs fixture.json output.json`。
同样使用 `PLAYWRIGHT_MODULE`、可选 `ADMIN_UI_BROWSER`；调用者先准备专用真实 Go C HTTPS 服务、4 个合成账号与待处理案件。
fixture 只存在本任务运行目录，字段为 `url`、`reviewerUsername`、`reviewerPassword`、`caseId`、`outputDirectory`；可用 `playwrightModule`／`browserExecutable` 提供调用者独立工具路径，环境变量优先。
脚本只接受 loopback HTTPS，直接从 Go `/admin` 加载页面，不创建替身服务；登录后领取／禁言三天，检查真实处理响应 `ENDED` 与可见审计，截图后退出。
输出 JSON 只有检查结果、固定失败阶段和截图位置，不导出 Bearer、密码、邮箱或响应材料；stdout 只输出安全的 PASS／FAIL 阶段。
使用 Windows Node 时，fixture／output 参数与截图目录须为 Windows 可访问的路径；从 WSL 调用前用 `wslpath -w` 转换本任务路径。
该脚本本身不是通过证明，须随固定候选、真实服务与独立一次性数据库执行后记录结果；fixture 文件不得提交。

本分支已通过上述真实 Go C／SQL／Dart／Edge 链路，实际配置、首位管理员引导和最终证据见 [API 运行说明](../../services/api/README.md)与[阶段1报告](../../docs/design/report-moderation-validation-report.md)。不扩大到真机或生产验收。
