# B5 双实体 Android 验收记录

2026-10-16（Asia/Shanghai），分支 `codex/auth-privacy-handoff`，产品源码基线 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。

**固定24项累计23 PASS／1 FAIL／0 BLOCKED；NI-X01通过，NI-X02未通过。** 第二手机已经到位，不再把当前缺口写成“缺设备”。完整非iOS开发验收仍为false；iOS、生产和未来业务没有因此通过。10月13日B6的22／0／2是原日期快照，未改写。

| 场景 | 实际执行和结果 |
| --- | --- |
| NI-X01，N01／A12 | PASS。vivo S18（V2323A，Android15）经官方欢太手机搬家／换机流程向真我RMX3366（Android14）实际迁移隔离测试App及其应用数据；只选1个App和1项App数据，未选个人资料。接收成功1／失败0。产品no_backup密文和夹具秘密没有迁入；真机目标App实际无会话、未自动登录，显示正常登录入口。源端原生存储会话仍可恢复并由实际C验证；独立SQL无新增授权。 |
| NI-X02，A07／N03 | FAIL。vivo原生创建1次成功并真实提交C，SQL为1账号／1 Passkey／1有效会话／0恢复意图。真我累计4次原生get均本地60秒超时，没有成功证明或C恢复意图。后续每次重试均有单独人工授权，保留原请求和失败，不重放证明。第2、3、4次实际出现Google跨设备二维码；第3、4次vivo实际显示“设备无法连接／确保设备相互靠近，然后重试。”两台蓝牙均开启，用户确认相邻；这些事实不能确定根因。 |

本轮停止于NI-X02的原生跨设备证明之前。完整恢复码确认、重设提交、不自动登录、旧会话／密码／恢复码／Passkey失效和新密码显式登录在这轮均 **NOT_RUN**，不能用其他版本的通过替代本场景。

新增源码是完整产品App的有界设备夹具 `apps/mobile/integration_test/auth_android_b5_device_test.dart` 和宿主操作器 `tools/control-android-b5-device.py`，没有修改产品鉴权、原生60秒期限、服务器或公开DAL。夹具Dart分析、ARM64构建和批准签名核验实际通过；这些检查不代替NI-X02。最终宿主UI守卫补齐Google hybrid／assisted sign-in窗口识别，只做静态核对，没有再发起认证。当前记录及各次APK／夹具摘要见[脱敏证据](../../services/api/authlab/android-b5-20261016-verification.json)。记录校验入口为 `python tools/check-android-b5-evidence.py`，只核对交接及源码范围，不运行设备认证。

首轮OEM迁移因夹具把合成测试秘密放在普通files目录而被拒收；移入no_backup后重新进行了干净官方迁移，才接受NI-X01。首次绑定因合成标签不符原生调试格式而在原生调用前失败，修正夹具标签后才真实创建成功；没有放宽产品格式守卫。构建工具失败、原OEM污染轮、标签预检失败及4次get超时均保留，旧历史UNKNOWN不改写。

两台原credential provider／primary／autofill设置均已逐项恢复，两台已退出前台失败提示；没有清除Google账号或个人凭据。主HnuHole、账号、草稿未删除。隔离B5包和测试状态、既有SDK／缓存及独立C/V环境暂留，便于后续在新授权下继续定位；没有宣称完成临时材料清理。用户为搬家手动调整的vivo网络助理和后台高耗电设置，原值未被工具采集，需按本人记忆恢复。原测试APK备份仍在，不将“原provider恢复”写成“原APK已恢复”。本轮尚未提交／推送。

下一步仅处理NI-X02的跨设备连接失败；重新发起认证须取得新的人工授权，并保存本轮失败。既有23项保持各自实际设备／版本／证明边界，不重跑OEM，不再重新创建源端Passkey。

## 同日 Bitwarden 同步路线预检

用户已在两台登录同一Bitwarden账号。两台均安装2026.9.1（21929），系统能查询到Bitwarden CredentialProviderService，但**服务安装不等于系统可接入**。vivo API35实际存在`android.software.credentials`特性和`credential` Binder服务；真我RMX3366 API34两者均缺失。真我的Bitwarden“通行密钥管理”实际跳转到仅有普通自动填充的OEM设置页，切换自动填充后原生凭据设置没有改变。Android框架官方文档明确要求该feature；本机证据据此将这条原生提供方路线标为BLOCKED。不能把Android14版本号当作完整兼容证明。

新增`auth_android_b5_bitwarden_test.dart`夹具已实际Dart分析、ARM64构建和批准签名核验PASS，预备在保留原Google凭据的条件下新增一条Bitwarden绑定；宿主操作器扩展尚未实现。**未安装这个APK，未发起新的创建／获取，未新增绑定。** 两台旧测试APK摘要和实际SQL均未变，两台原provider／primary／autofill已恢复；Bitwarden登录状态保留，未读取或导出个人密码库。固定矩阵仍23 PASS／1 FAIL，NI-X02原失败保留。

详见[Bitwarden预检机器记录](../../services/api/authlab/android-b5-bitwarden-20261016-verification.json)。后续若坚持不使用Google，需要另一台具备第三方原生Passkey支持的Android，或由机主自行确认官方系统更新是否补齐；未安排刷机、系统升级或更换手机。恢复码可作为产品恢复路径，但不代证NI-X02的Passkey验收。
