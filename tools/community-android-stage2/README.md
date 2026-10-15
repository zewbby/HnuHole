# 任务2：原生存储与生命周期

当前只完成不接触手机的准备。设备 35 项原生测试、3 组认证进程中断、真实插件跨进程/整机重启，以及实际账号/IME/读屏检查均须在获批窗口执行。构建成功不能代证设备通过。

任务2与任务1顺序执行，不共享账号或业务数据库。任务1的隔离包 `org.hnuhole.hnuhole_mobile.communityf5`、APK、签名、手机待验空库及测试时钟保留。任务2使用独立包、独立新调试签名和合成的本地 fixture：

| APK | applicationId / instrumentation target | 内容 |
|---|---|---|
| storage.apk | org.hnuhole.hnuhole_mobile.communityf5.storage | Flutter integration_test、实际 vault 插件、PostStore/openNative、打包 SQLite |
| vault.apk | org.hnuhole.communityf5.storage.vault.test | AndroidBusinessStorageTest 7、AndroidAuthVaultTest 16、AuthVaultProcessRestartTest |
| passkey.apk | org.hnuhole.communityf5.storage.passkey.test | PasskeyCodecTest 9、PasskeyAcceptanceErrorsTest 3 |

两个原生 APK 都是自包含、自目标 instrumentation，runner 为 `androidx.test.runner.AndroidJUnitRunner`。不是将测试包指向任务1或认证 App。35 项按本次实际输出核数，跳过/崩溃/测试数不符不能通过。codec/错误分类没有系统 Passkey 正向 ceremony，不要求或变更公开 RP 关联。

## 无手机复验

现有专用工具：`/home/hnuhole/community-android-stage1-20261014-tools`；task1 cache root：`/home/hnuhole/hnuhole-community-flutter-f4-s1-20261014`。这两处均只属于当前社区任务。仅顺序复用其 SDK/cache，本次原生构建另用 task2 HOME、调试 key 和镜像；不调用原始共用 SDK。

本机已执行 wrapper 位于 `E:/HnuHole-community-f4-20261012/stage2-preparation-20261015/`。WSL root 为 `/home/hnuhole/community-android-stage2-20261015`，其 `.owner` 为 `HNUHOLE_COMMUNITY_ANDROID_STAGE2_V1`。Windows 输出 root 同一 owner，`device-window` 保存可用制品。配置、key、cache、APK 和原始日志不进 Git，按用户要求保留到设备窗口。

重新准备时先检查容量、owner、canonical path、其他构建占用与工具路径；不能直接覆盖已有 source 或已开始的设备记录。需要全新 root 时由操作者先核对其归属、建立 owner，再配置：

```bash
source /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/env.sh
export STORAGE_ROOT=/home/hnuhole/community-android-stage2-20261015
export STORAGE_REPO=/mnt/e/HnuHole-community-f4-20261012/repo
export STORAGE_SQLITE_ASSET=/mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/assets/libsqlite3.arm64.android.so
# 只复制既有公开 Maven blob；原 cache 只读，保留 POM/module 的原始字节和版本。
python3 -B "$STORAGE_REPO/tools/community-android-stage2/import-test-dependencies.py" \
  --work "$STORAGE_ROOT" \
  --public-cache /home/hnuhole/.cache/hnuhole/gradle/caches/modules-2/files-2.1
bash "$STORAGE_REPO/tools/community-android-stage2/build.sh"
```

build.sh 拒绝已有 source，所有 Flutter/Gradle 工作在独立镜像内。pub 使用 `--offline --enforce-lockfile`；Gradle 使用 `--offline`。本轮仅补入约 4.5 MB 既有公开测试依赖；本地 Maven repository 是镜像 overlay，原依赖版本、产品 Gradle/manifest、SQL、协议和锁均不变。仓库解析保留未获选的多平台版本缺口；最终 Android 构建已实际证明所需依赖齐备，不将非 Android 分支缺失误报为设备阻塞。

`verify.py` 需要显式 `--work --repo --output --windows-output --build-tools --stage1-window`；本机 `verify-artifacts.sh` 给出全部实际参数。它核对 450 项 task1 输入、199 项镜像输入、签名、DEX 中的测试类、真实 testApplicationId/targetPackage/runner、35 项源码计数、编译后的备份排除规则及打包 SQLite。随后导出 manifest/APK/公开 ADB 文件；仅复制、校验 ADB 二进制，绝不执行。SQLite 校验区分 pinned raw ELF 与 Gradle strip 后 ELF。

可随时执行的只读计划和主机守卫：

```powershell
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --plan-only
& E:/acanda/python.exe -B -m unittest discover -s tools/tests -p test_community_android_stage2_phone.py -v
```

## 获得手机窗口后

先向用户确认实际实体设备ID、时段、认证会话释放、允许安装上述三个新包/创建本任务 USB 调试 key，以及只强停这三个包。任务1包的强停/重开和**整机重启**分别说明影响并确认；没有确认不执行。预备 manifest 的 `deviceWindowGranted=false` 不是授权。不得卸载、清数据、更换已安装包的签名、修改 provider/同步/备份/安全设置或操作其他 App。

以下 flags 仅能在真实授权后设置；每个阶段的回执保存于 `device-window/device-state.json`。示例 `<设备ID>` 必须替换为已确认的实体 ARM64 Android。

```powershell
$manifest = 'E:/HnuHole-community-f4-20261012/stage2-preparation-20261015/device-window/manifest.json'
$device = '<设备ID>'
$approval = @('--confirmed-window','--allow-isolated-install','--auth-session-released','--allow-owned-adb-key','--allow-owned-force-stop')
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase suites
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase write
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase read
# 暂停：仅在另获整机重启许可后，请用户手动重启、解锁并重新允许 USB 调试。
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase reboot-read --confirmed-manual-reboot
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase purge
& E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest $manifest --device $device @approval --phase closed
```

没有重启许可可略过 `reboot-read` 后继续 purge/closed，但 CA-A09 保持 NOT_RUN；purge 后不能再将 pre-purge 重启项补记通过。需要以后补验须准备另一合成 run，不能清空当前记录盲重试。两个中断 probe 会有意结束**测试包自身进程**，不会强停其他包。

每阶段检查固定 APK/hash、已安装包的归属、专用非 5037 端口和 ADB server 的 PID/启动时刻/可执行文件；清除继承的外部 ADB socket/serial/key，USB key 写在 task2 `adb-home`。只对指定设备执行命令，不调用全局 ADB，不替换已有未知端口或包。实际 VM 结果只导出必要布尔值/计数/PID，不导出 URI、key、密文、正文、token 或原始证明。每阶段开始先落 latch；失败/未知时停止，先审查原结果，不能删 latch 自动重放。

跨进程探针使用实际 Keystore、业务 vault 和实际打包 SQLite。write 写入 A 草稿/原 commandId-digest-identity-channel 及 B 草稿，read 核对不同原生 PID 和原状态；reboot-read 另核对 boot ID 已变。purge 只对合成 A 调用现有本地 adapter，closed 在新进程核对墓碑、文件擦除与 B/认证记录保留。它不调用 main、不登录、不发送 HTTP、不构造可用账号凭据，**不代证服务端权威闭号或实际账号会话恢复**。

## 同一窗口还需人工事实

在任务1成功后，核对任务1实际 normal.apk 和本任务合成账号 A，先保存一条可识别的中文草稿，再仅强停/重开任务1包：记录前后 PID，确认实际 main/会话 HTTP 正常恢复、草稿及原身份/通道未变、没有自动新发帖。允许整机重启时一并复核这些实际账号事实。需要核对未决命令的真实 HTTP 恢复时，使用 task1 已有的丢响应控制入口和原键查询，禁止另发 CREATE 或交换身份/通道。

用户以真实中文输入法输入/换行/收起键盘，核对正文和草稿；记录机型、OS、IME及已有读屏状态。若 TalkBack 已开启，检查实际控件名称/焦点/错误消息；若未开启，必须先询问是否允许改变该系统设置，未许可则记 NOT_RUN，不自动切换。合成探针内字符串与 enterText 不代证输入法/无障碍。

原生 7 项与实际 App noBackup 路径/编译备份规则属于当前单机范围；真实 OEM 搬家和系统 Passkey 跨设备恢复继续归任务4 NI-X01/NI-X02，不能由静态规则或文件手工复制代证。任务3独立公开 RP/实际 provider、iOS及生产仍另行验收。
