# Android任务1实测与交付

2026-10-15：**任务1限定范围PASS：真实Android八自动检查PASS＋人工IME USER_CONFIRMED。**完整App/模块、任务2–4、iOS和生产未通过。自动原始device-result当时仍为PARTIAL_MANUAL_IME_NOT_RUN；未改写它，当前汇总结论另合用户手工事实。用户对明确的中文/换行/emoji、键盘遮挡、返回保存及“我的”重开清单答“一切正确”；这是用户综合确认，不是逐项原话或自动观察。默认IME组件另由只读系统查询补齐，未单独获得输入法友好名称。

产品固定b5accf36b90e27829b6d039cd58a5b9c189a3da8，认证固定d859cb05c772cdf8d8b75e439a2bfedf0414dd46。起始7ded6bd、守卫提交e0c1280，保留并行8981f6a（仅文档与stage3工具/测试，未触本次受测产品输入），随后限定本任务追加提交。所有失败只读定位由gpt-6-astra完成，修复/验证/设备执行由gpt-6.1-sol high完成。

| 本轮执行 | 结果与范围 |
|---|---|
| 实体vivo S18（V2323A），Android15/SDK35 | CA-A01/02/03/04/05/06/07/10八点PASS，实际main/原生端口/真实C/V/SQL；无host vault替代 |
| CREATE/RETRY/DELETE丢成功回包与原结果核对 | creates2/retry1/delete1，unique相同；三次预期丢回包，没有重放原业务 |
| 权威闭号及本地scope | closed1、pending0，闭号payload/private receipts/credentials残留全0；精确marker[1]、7种db/auth文件不存在、拒绝reopen，A草稿保留/B不可见 |
| 同签名normal更新及真实IME | normal安装摘要核对/正常main启动；用户亲手操作并综合确认；账号A会话与App数据保留 |
| 最终mobile全量 | 327 PASS、0失败/跳过；新增5项纯文件证据测试PASS，分析0问题 |
| Python相关主机选择 | Windows144 PASS＋3 POSIX SKIP／147；Linux147 PASS；聚焦phone31 PASS。固定选择排除并行stage3测试，不声称它们已在本轮执行 |

本轮最小改动只涉及验收harness/helper/test及stage1主机控制器：显式复用既有USB身份（默认仍阻断、真实OS profile逐层metadata拒reparse且不读/复制/hash key）、已知旧manifest/proof双SHA＋owner/latch/同设备/记录结果/旧APK与同签名更新守卫、getIsolate专用1MiB上限（driver128KiB、handshake16KiB保留）、失败install私有bounded stdout。产品plugin的隐匿错误、Dart业务lib、Go、SQL、协议、依赖/锁和全局配置均未改。原七stage产品证据保留原版本，此轮未冒充重新运行。

历史失败原样保留：首次专用key隔离未证明；复用USB身份后仍无transport；用户明确允许仅结束精确已核的旧PID59948后，自有60761出现目标device。原App getIsolate单帧172543字节越界，经method限定修复后只读收取原结果；原业务FAIL为harness误要求native精确内部Closed错误，未改产品映射。随后另建新fixture/runID和真正不同C/V origin，保留旧闭号库/localdata；新APK仍原任务签名/同包。首次更新被系统安装确认中断，旧APK仍在、新库全0；用户明确已解锁盯手机后在原新latch下仅attempt2安装/启动成功。最终mobile wrapper首次遗漏原任务SQLite LD_LIBRARY_PATH，262成功/29failure/36error；仅补当前子进程环境后一次327全量重跑PASS，原失败日志未覆盖。

452项构建/测试输入及APK镜像已核。APK构建快照与最终控制器指纹分别见机器记录：构建后仅Python私有安装诊断及其测试更改，所有编入APK的输入均保持相同；无需借此重放手机场景。新manifest/原自动结果/原失败均保留各自指纹。签名、包、ARM64/SQLite、新TLS空库clock0在运行前实际核对；场景只推进专用测试时钟，不改系统/手机时钟。

资源按要求保留：本轮normal/A会话与草稿、专用server/reverse/当前fixture/SDK/cache继续可用；旧失败lab、旧本地scope和日志待审计，不在此轮扩大清理。任务2实际原生35项/跨进程/重启、任务3系统Passkey、任务4双实体及iOS/生产仍独立NOT_RUN；本次既有USB身份例外只接入stage1，stage2默认守卫未放宽。

外部证据：E:/HnuHole-community-f4-20261012/device-validation-20261015-rerun-01。关键文件为device-window/device-result.json（自动历史）、attempt2-device-result.private.json（不入Git）、manual-ime-user-confirmation.json、normal-transition.json、native-closed-evidence-tests.log、analyze-final.log、mobile-final-tests.jsonl（失败历史）、mobile-final-rerun-tests.jsonl（327 PASS）、windows-final-host-tests.log、linux-final-host-tests.log、final-source-fingerprint.json及aggregate-sanitized-result.json。最终源SHA/远端/限定改文件与dirty状态由同目录git-delivery.json记录。原阻断和原业务失败证据链接/目录见机器记录。
