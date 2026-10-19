# 固定 Android 集成候选的保留与复现

仅针对产品 `1a810944787eacb66e2115e1ce77de08190c366a`。普通 APK 是固定测试候选，开发 CA 截止 **2026-11-18 04:48:27 UTC**；到期后不绕过证书检查。此文是后续操作者入口，不授权重新开启已关闭设备窗口或恢复旧预发布任务。

## 保留材料

本机交付根为 `E:/HnuHole-android-integration-20261019/runtime/`，不在 Git 中存 APK、数据库、日志或秘密：

| 路径 | 内容/分发边界 |
| --- | --- |
| `candidate/` | APK、构建时 manifest、公有配置、公开签名证书、INSTALL、SHA256SUMS；不含夹具凭据 |
| `integration-source.bundle` | 真实产品源码1a810944；与本 PR 交付工具提交分别固定 |
| `integration-private-runtime.tar.gz` | 已停止的3个隔离PG实例、正式备份、C/V/authdev二进制、私有测试PKI/签名、合成数据和必要Mailpit/Pillow运行依赖；只供本机授权操作者 |
| `integration-private-runtime-receipt.json` | 私有归档SHA、大小、逐文件读回核验数量与停止事实 |
| `integration-private-runtime.contents.private.json` | 归档每文件摘要；不会代替实际备份恢复证据 |
| `phone-window-20261019/` | 本轮安装、截图/XML、错误与关闭回执；含私有连接记录/合成凭据，不能当普通交付包 |
| `downloads/`、`tool-download-receipt.json`、`browser-tools-receipt.json` | 固定安装器及来源/摘要；不是恢复后的SDK或其他session缓存 |
| 本目录的准备/执行 `.py` | 实际bootstrap、原构建调用配方、窄范围继续、严格浏览器与收尾脚本；历史失败保留，不盲目重跑有副作用入口 |

提交内的[构建](android-integration-build-20261019.json)、[新增恢复](android-integration-restore-20261019.json)、[设备](android-integration-device-20261019.json)是脱敏证明。原始构建 manifest 保留 device NOT_RUN 时间快照，后续验收见设备回执。后端配置摘要在 manifest 中，私有配置内容不提交。

## 使用已固定 APK

先在 PowerShell 核对 `candidate/SHA256SUMS` 每项及 APK 摘要。包名 `org.hnuhole.hnuhole_mobile`，版本 `0.1.0+2026101901`，ARM64/API29起，测试证书 SHA256 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。这是 debug 模式的普通 main.dart 包，仅用于 App 内开发 CA；不是正式签名/发布包。

实际安装需新的设备窗口：用本任务独立工具和空闲的专用 ADB server 端口，先核对连接设备、包名与证书；同包不同签名先取得当时用户的卸载/数据删除授权。不要使用5037或停止未知ADB。使用本任务公有端口建立 `tcp:51245→tcp:51245`、`tcp:49747→tcp:49747` reverse，安装 `-t` APK。账号由私有运行材料另行取得，不注入编译配置。只公开这两个本地HTTPS入口，不转发PG、mTLS、SMTP或Mailpit，不安装手机系统CA。

本轮上述实际操作已完成并关闭；APK仍安装在 vivo S18，两个reverse/专用ADB5159已收回。重新连接手机不自动继承本次已结束的窗口。

## 后续恢复同机隔离运行材料

归档内绝对路径绑定 `/home/hnuhole/android-integration-20261019-runtime`，适用 `HnuHole-Ubuntu-24.04` / 非root `hnuhole`、PostgreSQL16.15、Python3.12.3。目标已存在时先核对归属，不能覆盖其他资源。原目录清理后，后续有实际需要时：

1. 核对私有归档receipt的SHA和大小、源码bundle的HEAD为1a810944；创建上述专属空目录，权限0700。用Python3.12 `tarfile.extractall(..., filter='data')` 解到此目录，不能解到现有旧环境。归档已逐文件读回验哈希，包含可执行Pillow venv而不含大型SDK。恢复为本用户所有、保留私钥0600；校验contents清单。
2. 用保留bundle克隆到该根的 `source/`，确认HEAD和clean tree为1a810944。不要从最新main更新，不改迁移。确认 C18/V4、配置与二进制摘要匹配；核对公有C/V端口和CA有效期，检查所有记录的端口空闲且没有未知PID/socket。
3. 使用解包后经过裁剪的 `tool-env.private.json` 与 `run-owned.py` 启动入口；其中仅保留本任务PATH/HOME/TMP/Pillow等运行变量，不保留继承宿主秘密。启动 `lab.py start` 后通过既有签名operator `recover` 续建证据并启动watch，再运行 `health`。Gate未恢复时503不能当成功。正常恢复改变代次，旧会话拒绝后须正常重登。
4. 停止用 `lab.py stop`；它先在Gate提交之间quiesce服务，再校验PID/start token停止C/V/watch/Mailpit，逐个证明3个PG实例已停止。不要直接杀全局Go/Java/PostgreSQL进程，不改授权表来消除503。

对应命令结构（从本任务交付源码调用，实际根如上；此处不自动执行）：

```sh
python3 /mnt/e/HnuHole-android-integration-20261019/runtime/run-owned.py \
  /mnt/e/HnuHole-android-integration-20261019/repo/tools/android_integration/lab.py \
  --root /home/hnuhole/android-integration-20261019-runtime/lab \
  --source /home/hnuhole/android-integration-20261019-runtime/source start
# 同样参数分别执行 recover、health；结束执行 stop。
```

这是同机开发材料恢复入口，不是生产独立运营证明。当前物理恢复已验证的是新增非空评论/治理数据从备份到新C实例，而不是清理后另一次完整归档启动；不重复旧全套恢复演练。

## 必要时重新构建的固定入口

优先复用本次已验 APK。只有新任务实际需要时，才在空的专属工具根按保留的bootstrap与安装器摘要准备独立Go/Goose/Pillow、Flutter/Java/SDK和缓存；不借其他session。原 `download-tools.py` 中从旧保留安装器复制的步骤仅为历史，不需恢复旧SDK；当前全部对应安装器已保留在本任务downloads。loopback CONNECT relay只转发官方构建主机的TLS字节，Gradle代理只写本任务GRADLE_USER_HOME，不修改系统代理/信任。

新环境使用 `tools/android_integration/lab.py init`、`data.py`、`restore.py`、`build.py`；先完成新增C数据恢复，再构建。`restoreRequest`已存在、候选输出目录已存在时入口拒绝盲目重复。当前恢复库不能重跑init/seed/restore。普通配置仅C/V origin与CA三项，额外凭据/fixture、错误origin/CA/source、非独立cache均拒绝；关键检查在 `python -O` 下仍有效。

```sh
python -m unittest discover -s tools/android_integration/tests -v
python -O -m unittest discover -s tools/android_integration/tests -v
```

实际候选构建命令为 `run-owned.py tools/android_integration/build.py --source …/source --tool-root …/tools --lab-root …/lab --out …/candidate --signing-dir …/signing`。manifest记录原调用配方SHA；后补守卫未改变产品输入，未重建APK。Flutter/Java/SDK完整版本及所有迁移/lockfile/二进制摘要见构建manifest与安装器receipt。

## 回滚和事件接续

应用候选可撤回安装；旧0018前后端不满足新权限契约，实测拒绝启动，不能对新治理库盲目回滚。保持当前固定后端或由所属模块向前修复；数据库不执行Down。原预发布的旧版本应用回滚证据保留原版本范围。

授权/Gate所属模块后续分析一次 `INDEPENDENT_ANCHOR_FROZEN`：固定源码、三个关联ID及恢复后的read_at见设备回执；原始Gate日志/锚点/操作记录在私有归档。网页回执与冻结相距约57ms，只有时间相关，原因未确定。本任务仅以既有签名恢复，没有修改业务。iOS、跨设备Passkey、多机型、生产发布和持续可用证明继续不在范围。

收尾事实见[清理回执](android-integration-cleanup-20261019.json)：Linux专属目录及全部大型SDK/cache已移除，运行材料保留在私有归档；Windows专属ADB SDK删除被自动审批拒绝，目录停用保留，不能宣称已删除。临时登录说明仍位于私有手机证据目录，不能并入普通候选分发。无需为本轮收尾重新启动环境或手机。
