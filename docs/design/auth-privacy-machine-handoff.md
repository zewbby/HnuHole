# 匿名分支：另一台机器接续入口

交付日期：2026-10-03（Asia/Shanghai）。远端：`origin`，仓库 `zewbby/HnuHole`。分支：`codex/auth-privacy-handoff`。本文件随本次源码快照提交；准确交付 commit 以包含本文件的提交及推送结果为准。

## 本次交付包含什么

- 此前未提交的 C/V 正式迁移、非 owner 运行权限、HTTPS/mTLS 开发运行时、持久 worker、目录最终授权及移动端会话衔接。
- 设备／恢复凭据管理、原生 Passkey 桥与真实平台测试源码。
- B02 本人身份基础管理、默认头像、设置入口、迁移 0011、原结果核对与相应 Go/Dart 测试源码。
- [匿名收口清单 AC01–AC06](auth-privacy-closure-checklist.md)、[模块测试交接](module-acceptance-handoff.md)及[机器台账](module-acceptance-ledger.json)。

这次是可接续的源码交付，**匿名缺口没有在本次推送中实施完成**。P01/V 独立 Gate 和已有身份整账号关闭联动仍未实现；B02仍为“基础管理已实现，业务联动待实现”。本次整理／提交不代表编译、SQL、Flutter、设备或生产验收通过。

## 拉取与定位

在正确的仓库 checkout 操作，先查看 `git status --short`，保留本机已有改动，不用 reset／clean 覆盖。工作区允许切换与快进时：

```sh
git fetch origin
git switch codex/auth-privacy-handoff
git pull --ff-only origin codex/auth-privacy-handoff
git branch --show-current
git rev-parse HEAD
```

本机缺少该本地分支时，在 fetch 后用 `git switch --track origin/codex/auth-privacy-handoff` 建立跟踪分支。若已有不同提交或未提交改动阻碍快进，先核对差异，不能强推或丢弃本机工作。

Windows 服务端、POSIX runner 与 Gate 文件应放在 WSL2 Linux 文件系统；不要直接以 Windows 路径运行，也不要把含 iOS Swift 源码 symlink 的 checkout 转成普通文本链接。Android/iOS 原生验收按实际具备的平台、SDK、设备与完整 Xcode 条件分别登记。

## 阅读和执行顺序

1. 先读根目录 `AGENTS.md`、本文件、[匿名清单](auth-privacy-closure-checklist.md)和[HANDOFF](HANDOFF.md)顶部的最新范围。历史“下一片 B05”安排已撤回。
2. 核对实际被测版本、工具与工作区；先执行可用的格式／编译／契约检查，发现阻碍当前匿名开发的失败时修复并登记。
3. **AC01：实现 V 独立 Safety Gate。** 当前 C Gate不能代替它；按清单补 V 专用设计、迁移／权限／配置、最终事务与签名／派发边界及故障测试。
4. **AC02：接入已有身份的整账号正式关闭生命周期。** 协调“至少一项活动身份”、累计创建、永久墓碑／回执约束，落实独立注销占位契约；不先实现完整帖子／聊天。
5. AC03核对当前数据／接口／日志／客户端匿名边界并固定后续业务契约；AC04补实际进程与真实 Dart→SQL 的 B02及新增匿名场景。
6. AC05对当前版本集中验收，AC06更新文档／台账并固定交付。保持通用业务开发范围暂停，不滚动加入 B05/B03 或消息／治理模块。

每次改变共享授权、迁移、会话、持久状态或平台桥，都重新打开受影响模块的当前验收；历史 commit／源码指纹的通过记录原样保留。测试源码持续保留。未执行项明确原因、入口和场景；不能把工具可启动、替身、SKIP或旧版本证据记成当前模块PASS。

## 已知验收入口与限制

准确命令、准备步骤和证明范围以[模块交接 R00–R10](module-acceptance-handoff.md)及各实施报告为准。现有 runner 没有通用 `--module` 参数；不要发明参数。Go无DSN运行会跳过部分SQL，Flutter内存vault／同进程重建不能证明真实设备安全存储／杀进程恢复。

整理机器现有工具盘点：Go/gofmt、Flutter/Dart、Docker/PostgreSQL/Goose、sqlc、oapi-codegen 不在 PATH；完整 OpenAPI validator 依赖缺失。完整编译／动态／设备测试保持 `NOT_RUN`。已保留以下现存命令：

```sh
# 仓库根，已有相应 Python 校验依赖时
python packages/openapi/check-specs.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/check-identity-handoff.py

# services/api；普通go test不能单独证明SQL通过
go test -race -count=1 -p 1 ./...
go vet ./...
sh authlab/run-isolated.sh
sh authlab/run-runtime-isolated.sh

# apps/mobile；按报告用现成Flutter准备依赖后
flutter analyze
flutter test --reporter expanded
```

SQL runner仅使用明确归属的一次性开发／升级库，fixture会reset schema；不得传未知DSN或真实用户库。真实 Dart联调、native设备／进程探针、Passkey关联配置与正负向矩阵继续按[设备报告](auth-privacy-device-credentials-passkey-validation-report.md)和[身份报告](identity-management-validation-report.md)执行。RP域名、Android签名和iOS Team／关联身份尚未提供，不能擅自启用或声称真机闭环通过。

`check-identity-handoff.py`验证的是原B02状态／文件／源码摘要一致性，不是应用行为；本次打包仅清除了 `infra/postgres/grant-verifier.sql` 末尾一处空行，重新计算源码摘要并保留原检查记录，未改业务行为。后续修改实现／格式／依赖后，应按已有算法更新新版本摘要和交接记录，保留历史，不为了通过该检查恢复旧代码或伪造证据。

## 给接续执行者的任务

> 只在 `codex/auth-privacy-handoff` 继续匿名方案收口。先读 `AGENTS.md`、`docs/design/auth-privacy-machine-handoff.md`、`docs/design/auth-privacy-closure-checklist.md` 与模块验收台账。按 AC01–AC06补齐匿名基础缺口、保留测试源码、修复实际失败并更新交接；不进入完整发帖／列表／评论／聊天／治理开发。P02–P06生产运营与独立审计证据单列，未具备时如实登记。未经另外授权不部署或对外发送评审材料。

## 本次交付验证范围

提交前检查补丁、四份OpenAPI的YAML／本地引用／结构、B02源码摘要和交接一致性、机器接续链接及Git暂存内容。检查结果只证明相应静态／交接范围；未新增动态验收证据。测试源码和小型记录随提交保留；不包含本次生成的数据库、私钥、APK、SDK或大缓存。

本次实际执行的 `git diff --check`、`tools/check-identity-handoff.py`、四份OpenAPI的 `check-specs.py --yaml-only` 和交接链接／台账检查均退出0。扫描未发现待纳入的大文件、运行密钥或安装包；测试文件中的TLS私钥是历史公开测试fixture，内容与原HEAD相同。Go／SQL／Flutter／原生设备动态验收没有执行。

暂存检查最初发现上述末尾空行，首次结果为FAIL；清理后重新执行暂存补丁检查、源码摘要与YAML检查，最终均退出0。旧B02检查绑定原摘要保留，本次打包检查绑定更新后的摘要，不增加动态验收通过项。
