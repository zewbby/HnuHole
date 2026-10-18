# OEM 双实体手机搬家实测：2026-10-18

NI-X01 在本轮实际可用 OEM 路径范围 PASS：vivo S18（Android 15）→真我 GT 大师探索版 RMX3366（Android 14），官方欢太手机搬家，唯一应用 HnuHole Stage4、100 MB，成功1项、失败0项。第二次传输 11:57:19–11:57:25（Asia/Shanghai）。本记录不改变 NI-X02 的延期状态。

## 固定制品与范围

起始及最终 HEAD `dd5745a10bb0c732b5cf8b5ffc25a471e26f1b13`，分支 `codex/community-flutter-pages`。产品、协议、SQL、依赖、锁文件、其他分支未改；本轮只写脱敏交接，未提交或推送。

包名 `org.hnuhole.hnuhole_mobile.communityf5.passkey.control`；APK SHA256 `6cce56a7879bd76b2db9c1ed1b63c6326b1abb029a6f6f853d9c7a250470229c`，证书 `3309ce001a5dfd93148c14e35159147a6711e4b61d881b7a223b3e8429665e34`。源官方工具14.7.34_third，目标16.10.1。使用用户明确允许的官方搬家配对二维码，没有触发 Google/Passkey 扫码。

实际选择为“应用”下唯一 HnuHole Stage4。应用数据、微信/QQ及其他数据未选；目标原已安装同签名测试 App。官方提示目标系统较低、部分数据不支持搬家。因此证明该路径接收专用应用且不带入源账号控制权，不外推为强制导入私有数据、新清空设备、全部 OEM 或 Android 版本的通过。

## 实测结果

| 检查 | 本轮结果 |
|---|---|
| 官方搬家与唯一明细 | PASS：1 App、100 MB、0失败，成功明细为 HnuHole Stage4 |
| 搬家前对照 | PASS：源已登录第13代会话且有 Stage4Local 草稿；目标已为访客 |
| 目标重开 | PASS：真实 App 强停重开仍显示“登录或注册”，没有源草稿或自动登录 |
| 源重开 | PASS：真实 App 强停重开，“我的”和 Stage4Local 草稿标记保持 |
| 原生私有存储 | PASS：打开 App 前采证，两侧各自三个 no_backup 文件哈希原样保持，源目标密文/数据库哈希不同；未导出文件字节或 Keystore 密钥 |
| 服务端事实 | PASS：前后 SQL 账号、会话、计数一致；仅源第13代会话有效，无新目标会话；credentialVersion6/resetGeneration2/Passkeys0 |
| 隔离与收尾 | PASS：两机原 APK 和 provider/autofill 保持；最终进程 nativeBegun0；仅移除本轮新反向映射、停止精确自有34881 ADB进程，5037未动 |

首次搬家 11:47:24–11:47:30 也成功1 App/100 MB/0失败，但目标当时保留自己的第12代有效会话、源旧会话已被替代；这只证明已有目标会话变体，未单独据此授予 NI-X01。随后正常登录源、让目标成为访客，完成上述补充对照。期间没有卸载、清数据、换签名、改 provider、同步账号或协议。正常 App、认证 App 及其他任务数据保留。

本轮仅验证原草稿标记保持，未重新逐字核对草稿全文。早前一次 apps-only 自动选择因用户已进入发送流程而停止，未扩大选择；补充搬家在发送前复核唯一应用及100 MB，完整保留前次证据。

## 命令、证据与后续

实际入口、逐项记录及外部日志 SHA256 见[机器记录](community-android-oem-transfer-20261018.json)。执行根为 `E:/HnuHole-community-f4-20261012/stage4-execution-20261016/oem-execution-20261018`；原生哈希和 SQL 位于其父目录，均为脱敏布尔事实/计数/哈希。检查入口为该根的 `window.py inspect/native-files/app-inspect`、`app.py reopen`、`finish.py`，只读 SQL 使用父目录 `owned-sql.py oem-final-after-reopen-20261018`（WSL HnuHole-Ubuntu-24.04/hnuhole）。结果7项限定PASS，日志及设备命令成功退出；不是旧主机测试计数。无需重建，当前同一 APK 覆盖全部本轮动态检查；本轮没有重跑 host/mobile 套件。

手机无需继续配合。最终源保持第13代登录及草稿、目标为访客；两机数据、原生材料及明确归属的临时后端保留，今后使用设备需重新建立专用连接。已有恢复码双实体8项PASS维持原范围；本次补齐NI-X01后，原四任务 Android 清单剩 NI-X02 跨设备 Passkey（用户延期，真我当前 ROM 缺凭据 feature/service、官方 OTA 无新版）。后续用具有相应能力的第二实体 Android 及获准兼容 provider 验可发现恢复、完整新凭据确认和旧会话失效；不再循环尝试 Google 扫码。iOS、生产部署、灾备及独立审计仍在本轮范围之外，完整 App/四阶段不记全部PASS。
