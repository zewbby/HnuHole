# Flutter社区 F4 换机接续

日期2026-10-10。对应分支 **codex/community-flutter-pages**，源码提交`68d35af745098be0ed52d0d448f290795665afa1`。先读[HANDOFF](HANDOFF.md)、[F4计划](community-flutter-f4-plan.md)、[报告](community-flutter-f4-report.md)、[机器记录](community-flutter-f4-verification.json)与[台账](module-acceptance-ledger.json) currentCommunityFlutterF4。F1—F3已完成，不重复画图或开发既有文字页。

## 当前已完成和未完成

固定后端514a944＋认证基线0eff47a上的生产根路由、登录、文字编辑／确认／固定身份、列表／详情／我的、原命令恢复／删除、冻结／会话接替、A/B隔离与B闭号SQLite边界8项主机真实HTTPS/PG检查PASS。源码／测试／小型证据在仓库中；原生vault在主机链使用替身。

最终认证候选尚不存在，FP14/F4联合终验BLOCKED。最终设置入口改动后尚未完成全量mobile与R05/vet回归：WSL系统命令段错误、根文件系统emergency_ro；早期308及Go/SQL结果保留原范围。F5本轮APK／native7／跨原生进程／物理Android／IME／读屏／备份／iOS等NOT_RUN。

## 新电脑拉取（PowerShell）

在你准备存放项目的目录使用一个不存在的目录名：

```powershell
git clone --branch codex/community-flutter-pages --single-branch https://github.com/zewbby/HnuHole.git HnuHole-community
cd HnuHole-community
git status --short
git branch --show-current
git log -2 --oneline
```

预期分支codex/community-flutter-pages，工作区无输出；最新为本轮交接提交，上一条源码68d35af。若已有仓库，先保留未提交改动，再fetch并选择本分支；不要在auth工作树强制reset/checkout，也不要把其他会话未提交包拷进来。

## 下一执行顺序

1. 在新的可写WSL/Linux文件系统核对现有Flutter/Dart、Go1.22、PG16、sqlite3、rsync/python3；PG runner必须非root。未安装工具时如实登记，不自动下载大型SDK或复制本机专用缓存。
2. 先运行最终mobile checks，再auth-regression和最终vet；保留相同pubspec.lock并enforce-lockfile。认证依赖未固定前不要宣称F4完成。
3. 取得认证会话最终提交SHA，逐项解决与本分支main/settings/AuthFlows/session/HTTP/closure/native/manifest/SQL重叠，保留F3原命令／闭号／删除围栏。只借固定提交，不借旧SHA或T4未提交设备证据。
4. 在最终整合SHA重跑integration、checks、auth-regression和受影响Go/SQL检查；重新更新四份交接、台账和指纹。之后按F5补原生平台；完整业务未实现部分另行任务，不扩范围。

runner路径为`tools/run-community-flutter-f4-linux.sh`。本机默认Flutter路径不适合新电脑；通过环境变量F4_FLUTTER_ROOT指定已有SDK，F4_TASK_ROOT指定新任务专用/tmp/hnuhole-community-flutter-f4-*目录。例如在Linux终端，仓库根目录（将SDK路径替换为实际路径）：

```bash
export F4_FLUTTER_ROOT=/your/existing/flutter
export F4_TASK_ROOT=/tmp/hnuhole-community-flutter-f4-new-machine-20261010
bash tools/run-community-flutter-f4-linux.sh checks
bash tools/run-community-flutter-f4-linux.sh auth-regression
bash tools/run-community-flutter-f4-linux.sh integration
bash tools/run-community-flutter-f4-linux.sh server
```

每条分别核对退出码，失败先处理该步；server使用真实一次性PG，耗时可能数分钟。Go vet可在runner复制后的`$F4_TASK_ROOT/source/services/api`目录使用已有Go运行。脚本的Go/PG路径按本机已存在工具写死；新机先审查并适配，不发明--module参数。Windows Git可能转换换行，执行Linux shell前核对LF；库／服务／Gate均在Linux副本与专用/tmp运行。默认DSN由runner新建，不把正式库／未知库DSN传给reset fixture。

## 原电脑剩余缓存

本任务Linux缓存尚未删：`/tmp/hnuhole-community-flutter-f4-01a11f1a-20261010`，marker为`hnuhole-community-flutter-f4-01a11f1a-20261010|/mnt/c/Users/Administrator/.codex/worktrees/community-flutter-pages/HnuHole`。删除errno30，WSL根ext4 emergency_ro；相关PG／进程已结束。先由本机另行恢复文件系统可写，核对绝对路径与marker后只删这个任务目录；不要删除WSL虚拟盘、SDK、全局缓存或其他会话目录。当前电脑不安全做全局WSL停机，认证会话仍有设备工作。缓存无需搬到新机。

可交给新会话的指令：

> 在codex/community-flutter-pages接续F4。先读HANDOFF、community-flutter-f4-machine-handoff.md、F4报告/机器记录/计划和台账currentCommunityFlutterF4；已有文字页与主机8项真实链PASS。先在可写Linux环境补最终mobile/R05/vet；等待并固定最终认证提交，整合重叠源码后重跑真实链，最后更新四文件。F4终验和F5平台尚未通过，保留历史证据和未验边界，不重做F1—F3。
