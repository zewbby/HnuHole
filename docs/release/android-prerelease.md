# Android候选与隔离预发布

2026-10-18：实施和实际验证进行中，未合并、未正式发布。结果必须对应精确源码SHA；
GitHub Actions的Android制品和后台演练证据分开保存，手机验收NOT_RUN。

## 候选构建

独立 [workflow](../../.github/workflows/android-prerelease.yml) 在本分支push/相关PR运行，
指定提交checkout后保留Pub锁，构建真实 `lib/main.dart` ARM64 release APK并临时测试签名。
最终APK读取包名/版本/minSdk/备份排除/证书摘要，附制品SHA256及锁文件摘要。
输出只上传APK、manifest和SHA256SUMS；私钥不上传且构建后删除。
测试证书每次不同，不能用作相同包的稳定升级签名。

当前编译默认API为 `.invalid`，未连接真实服务，release保持正常系统TLS验证；
这只验构建交付，不等于手机业务闭环。设备窗口前须准备本任务专属debug/pinned-CA候选、
独立端口和测试签名，不改变正式包的Passkey身份或系统信任设置。

## 私有Linux环境

先显式准备 Go1.22.2、Goose3.22.1、PG16、Mailpit1.21.8、Python3和独立venv，
venv按 `services/api/media/requirements.txt` 安装固定Pillow。工具不隐式安装依赖。
所有Go缓存变量显式指向本任务目录；先 `go mod download`，演练内固定GOPROXY=off。
使用非root用户、Linux文件系统、规范绝对新路径，父目录先存在。

```sh
export GOCACHE=/absolute/owned/go-build
export GOMODCACHE=/absolute/owned/go-mod
export GOPATH=/absolute/owned/go-path
export PRERELEASE_IMAGE_PYTHON=/absolute/owned/python/bin/python
export GOTOOLCHAIN=local GOPROXY=off
# 当前已合入main的完整SHA，作为实际回滚二进制来源
python tools/prerelease/environment.py --root /absolute/new-lab init --rollback-sha FULL_MAIN_SHA
python tools/prerelease/environment.py --root /absolute/new-lab rehearse
```

`init`从正式迁移初始化C/V，另外将schema13实际备份装入新C实例再前向升级；
不添加业务迁移、占位表或运行down。源库、升级库、恢复库均归该root，PG只监听loopback及私有socket。
`rehearse`运行真实HTTPS合成注册/登录/目录/文字/图片上传和原字节读取，
冻结拒绝、停写备份、两个新实例恢复、schema与数据摘要/权限复核、旧token拒绝与重新登录，
再运行实际失败部署、旧main二进制回滚和候选重部署。只保留开发同机证明范围。

手动启停可复用同一root：

```sh
python tools/prerelease/environment.py --root /absolute/new-lab start
# init后仍FROZEN；仅显式recover才开放Gate并推进代次
python tools/prerelease/environment.py --root /absolute/new-lab recover
python tools/prerelease/environment.py --root /absolute/new-lab health
python tools/prerelease/environment.py --root /absolute/new-lab stop
```

仅 `evidence.json`可脱敏发布；root里的其他文件包括合成密码、密钥、库、邮件和大日志，均不能提交。
备份恢复保留同任务的加密/HMAC/协议key和Gate锚点，只改目标DSN；新建key不能冒充旧数据恢复。
应用回滚与数据库兼容分别核验；旧二进制若不能通过当前schema/权限/startup检查，阻止回滚并前向修复或恢复。

## 未验范围

手机安装/原生存储/Picker/Gal/物理UX和本候选Passkey均NOT_RUN；跨设备Passkey和iOS延期。
schema13快照仅合成目录/迁移历史，不含真实用户历史数据。真实云、正式签名、生产主体独立、
外部独立备份运营与正式发布不属于已获批准的本地演练。媒体仍沿用现有SQL存储。
