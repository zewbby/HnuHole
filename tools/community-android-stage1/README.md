# 第一项：单机文字社区验收工具

本目录准备实际生产main、真实C/V与正式SQL、原生端口的第一项设备流程。准备阶段不调用手机或ADB。现有主机脚本用替代vault排练相同流程，不能计为设备PASS。

## 当前工具

- lab.py：在带本任务marker的独占镜像内建立新C/V库、正式迁移/角色、Go cmd、signed Gate evidence和TLS故障代理。CLI从不接受外部DSN。
- community_stage1_scenario.dart（apps/mobile/integration）：共用流程。host用生产HnuholeApp和文件SQLite/替代vault，device调用实际app.main与原生存储。
- community_android_stage1_test.dart（apps/mobile/integration_test）：Android验收入口。
- phone.py：Windows集中现场启动器，Python标准库直接使用固定Flutter SDK的VM/integration_test协议；不调用共享Flutter SDK。

故障代理保留请求字节、正常TLS验证与真实上游响应，只在收到成功响应后丢一次CREATE/RETRY/DELETE回包；持有原结果GET时只阻断读取，不重放写入。计数按内存HMAC区分原命令，报告没有原token/证明/命令ID/正文。

## 测试构建与安全边界

三个Go文件通过独立overlay构建：Gate.Clock、authdev签发开发evidence的时间，以及posts job的暂停调度。原Go/SQL源码、认证检查、publication方法体、七天SQL期限、系统/手机时钟均不修改。offset只允许0–8天；advance-closure要求恰有一个PENDING_CLOSE，推进七天加一秒后通过原operator签发/恢复流程更新开发evidence。其他worker继续正常执行。

真实失败任务由正式申请注销停止已受理发布，再正常密码登录撤销申请形成；不直接写FAILED、不伪造回执。第一账号正常发布/删除，第二账号保留真实未公开任务与本地草稿再正式闭号，核SQL载荷/私有关联及本地关闭墓碑，同时保留第一账号草稿。

## 准备与主机排练

在已核对可用的本任务SDK/Go/PG/Goose/cache中，先运行仓库F4 prepare同步源码和锁，再调用：

```bash
python3 -B tools/community-android-stage1/lab.py prepare --work "$F4_TASK_ROOT/stage1-host-labNN" --source "$F4_TASK_ROOT/source/services/api"
```

work必须是已登记F4私有根的直接子目录，且首次不存在。Docker只使用已存在的postgres16.6-alpine/Mailpit1.21.8和本次随机project；新库/密码/角色材料独立。依赖按锁获取，不安装工具链或改全局配置。

主机配置在work/host-config.private.json。完整调用模板：

```bash
COMMUNITY_STAGE1_HOST_CONFIG="$work/host-config.private.json" flutter test --no-pub --machine --dart-define-from-file="$work/host-config.private.json" integration/community_stage1_host_test.dart
```

必须使用本任务镜像、专用SDK与缓存。配置路径可记录，JSON内容含合成控制token不公开。主机结果的checkpoint前缀为HOST-CA，nativeMain=false/hostVaultSubstitutes=true，均不移作手机证据。

用于手机的stage1-device-lab另建空库/新材料，不能复用彩排账号或已推进的时钟。构建两个同签名独立包：acceptance.apk跑自动流程，normal.apk供最后真实中文键盘/手工查看；都是org.hnuhole.hnuhole_mobile.communityf5，产品布局不改，仅构建镜像applicationId覆盖。APK、签名、材料和缓存均在本任务目录，不入Git。

## 集中手机窗口

先确认型号/设备ID、约30–45分钟窗口、认证会话已释放、允许新建本任务专用USB调试key并在手机确认（不复用现有ADB私钥）、允许安装/更新本任务独立包与数据影响。第一项不卸载、不清数据、不整机重启，不触及认证包。若同名包不是本次准备的APK摘要，则停止，不覆盖未知包。系统Passkey与原生独立测试套件属于后续第二/三项，本工具不借此计通过。

获明确确认后再由当前会话调用：

```powershell
& 'E:\acanda\python.exe' -X utf8 -B tools/community-android-stage1/phone.py `
  --manifest 'E:\HnuHole-community-f4-20261012\stage1-preparation-20261014\device-window\manifest.json' `
  --device '<确认的设备ID>' --confirmed-window --allow-isolated-install --auth-session-released --allow-owned-adb-key --launch-manual
```

此命令只在确认后运行。现在检查计划可用--plan-only，完全不读设备、不调用ADB。工具检查本任务marker/ADB与支持DLL哈希/两APK哈希、实体ARM64设备、同名包归属；使用本任务非5037的独立ADB server端口并拒绝被占用端口，清除子进程继承的其他会话ADB socket/serial/key变量，将ADB home限定为本任务adb-home；只在获得USB调试key确认后生成新key；只新建自己的reverse/forward映射、不覆盖既有映射。debug VM URI只在内存与App私有witness中处理，不进入公开日志。通过后更新本任务包为同签名normal APK，保存自己的测试数据；不卸载或清除。

device-started.json为一次运行门闩。失败/中断后先核原结果及本任务SQL，不自动重启或重放注册/发布操作。VM结果只导出checkpoint、布尔值和计数；手机标识使用摘要。日志中的自动通过只覆盖自动流程，task1Result仍为PARTIAL_MANUAL_IME_NOT_RUN，直到现场补真实键盘证据。

## 现场最后配合

自动流程完成后，正常App已保留本任务账号A会话。用户在隔离App中进入文字编辑，亲自用系统键盘输入中文、换行并检查显示/布局；返回/保存草稿，查看列表、详情和我的。记录机型/OS、输入法、操作时间及不含秘密的结果。不得用tester.enterText或人工一句“完成”替代实际操作记录。若需要重新登录，使用本任务合成材料，秘密只在手机/私有本地处理。

最后更新任务1报告/模块台账，区分自动设备检查、手工IME和剩余任务2–4。只清自己创建的映射/服务/材料；数据是否保留按确认窗口约定。旧源版本的通过记录不改写。
