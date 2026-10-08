# 文字后端 T1 设计与静态验证交接

日期：2026-10-08（Asia/Shanghai）。分支 `codex/community-text-posting`；HEAD／认证源码基线 `0eff47a21cd4f4ab1636b4468f7d5df9769a264f`。本轮设计为未提交工作区，小型记录中的逐文件SHA256标识检查范围，不拿HEAD单独代表设计版本。

Git交付补充：2026-10-08用户已授权将本轮材料提交并推送到GitHub，提交说明使用中文。本文及机器记录中的未提交／未推送字段保留T1检查时快照；后续实际交付提交以本分支Git记录为准。Git交付不改变业务NOT_RUN或模块验收状态。

状态：**T1_DESIGN_COMPLETE / BUSINESS_IMPLEMENTATION_NOT_STARTED**。用户授权做T1；本轮没有posts handler、正式SQL迁移、worker或Flutter业务实现。业务验收与生产均NOT_RUN。原认证会话的后续未提交验收增量尚未接入。

## 1. 交付范围

- [实施计划](community-text-posting-plan.md)：文字闭环与CP01–CP15；Q0文字范围、Q1可见字符计数、Q2独立注销占位均保留用户答复。
- [后端设计](community-text-posting-backend-design.md)：C同一最终事务、数据约束、锁顺序、两次成功时点、stop generation／不可变停止事件、worker、分页、回执及清理／权限。
- [API接入清单](community-text-posting-api.md)和[post-api.yaml](../../packages/openapi/post-api.yaml)：14个操作、严格公共／本人DTO、状态／错误／headers及原意图摘要framing。
- [ADR 0006](../adr/0006-text-post-command-publication-boundary.md)、[术语表](../../GLOSSARY.md)、[共享向量](../../packages/post-protocol-vectors/post-command-v1.json)、[专项checker](../../tools/check-community-text-contract.py)与[机器记录](community-text-posting-t1-verification.json)。

本会话负责后端契约及服务端后续任务。Flutter页面、UI图审查、业务SQLite与原生存储由并行 `codex/community-flutter-pages` 任务负责；这里只固定其必须满足的接口／持久恢复要求。没有替前端批准图稿或编写页面。

## 2. 源码审查落实的关键边界

| 当前事实／风险 | T1确定的处理 | T2必须验证 |
|---|---|---|
| 目录wrapper在Gate前读静态目录；正文和身份资料会变 | 新内容read在最终Gate callback普通JOIN读取当前可见性及资料，不锁其他作者行 | 改名／删身份／闭号／作者删帖并发与无锁环，CP10–13 |
| 会话代次在退出／接替／重设推进，产品要求既有任务继续 | 发布停止代次独立；申请注销和生效mute/ban同最终事务推进并记录TrustedAt | 取消注销和处罚到期不复活旧attempt；重试是明确新attempt，CP09–11 |
| 当前restriction/session仅判断ban，mute尚无实际写入hook | posts最终发送权限读取mute，并新增最小受信变化hook | 权限生效前后及多副本旧writer禁用，CP09–11／15 |
| 命令查询查无仍有迟到提交可能 | UNKNOWN_NOT_OBSERVED与NOT_ACCEPTED分开；seal原命令和受理按账号锁串行 | 迟到提交／丢响应／同key异意图／双账号，CP05–08 |
| worker直接先锁attempt可能反转账号锁 | owner account先锁；当前Gate snapshot只约束本轮事务；不存Bearer | 多worker、重启、冻结恢复、cancel竞争，CP07／09 |
| 身份删除后旧帖公开且从本人列表移除 | 公共生命周期投影＋独立12位随机编号；删除权限按原owner，单独capabilities接口 | 公开字段、旧帖删除、编号独立稳定，CP10／12／13 |

T1冻结文字规则为Unicode16 extended grapheme clusters、原文不trim/NFC；JSON体、UTF-8字节及控制字符另设资源／编码边界。Dart/Go候选库的Unicode版本通过原始版本资料核对，未运行其算法；[Dart 1.4.0](https://pub.dev/packages/characters/versions/1.4.0)与[Go v2.4.0版本说明](https://raw.githubusercontent.com/clipperhouse/uax29/v2.4.0/README.md)是选型依据。7组字素期望只为后续输入，不能记跨端PASS。

## 3. 实际检查与复验入口

| 检查 | 结果 | 精确范围 |
|---|---|---|
| `packages/openapi/check-specs.py`＋openapi-spec-validator 0.9.0／PyYAML 6.0.1 | PASS | channel、community-auth、identity、post、verifier-auth全部五份规范／引用／已有契约约束 |
| `tools/check-community-text-contract.py` | PASS | 14个受保护操作、重复键／引用、closed public DTO、必需headers、UNKNOWN封印、固定身份retry、Unicode16字数元数据、9组frameHex／SHA256 |
| 文档本地链接、空白及台账历史保持核对 | PASS | 11份文档／本轮入口的80个本地链接，19个新增／修改文件空白及18个设计输入指纹一致；原台账字段保持不变 |
| `git diff --check` | PASS | 已跟踪修改的Git空白检查；新增文件另做空白核对 |

Windows PowerShell，工作目录为本任务独立工作树：

```powershell
Set-Location -LiteralPath 'C:\Users\Administrator\.codex\worktrees\community-text-posting\HnuHole'
python -B tools/check-community-text-contract.py
wsl -d Ubuntu-24.04 -e sh -lc 'cd /mnt/c/Users/Administrator/.codex/worktrees/community-text-posting/HnuHole && PYTHONPATH=/mnt/d/zewbbyTest/Hnuhole-env/linux/python-validation python3 -B packages/openapi/check-specs.py'
git diff --check
```

专项checker预期输出 `PASS: 14 protected operations` 和 `9 framing vectors`，并声明static-only。完整规范检查预期逐份打印五行 `OpenAPI/contract passed`。这里复用已安装环境，没有下载Go／Flutter／Python依赖，没有启动服务、操作数据库或接触原认证验收设备。

## 4. 未执行项、原因及环境

| 未执行项 | 结果／原因 | 后续入口与依赖 |
|---|---|---|
| 正式迁移／权限／guard与升级 | NOT_RUN：T1只设计逻辑表，无可执行SQL | T2编写迁移后，用明确归属的一次性WSL2 Linux开发／升级库验证；编号按最终认证候选核对 |
| Go业务／Unicode计数／摘要向量、SQL／race／vet | NOT_RUN：没有posts实现或业务测试 | T2新增源码与聚焦测试，再执行实际PG、全量SQL／race／vet并映射CP05–15后端边界 |
| 实际C HTTP／worker／cmd故障链 | NOT_RUN：新路径尚无handler，无posts fixture | 新增fixture／场景后复用authlab框架；R01/R03/R05没有posts筛选参数，当前不提供虚构runner命令 |
| Dart摘要与字素／Flutter页面与SQLite | NOT_RUN：归并行Flutter任务，尚无本片实现证据 | 两端共享向量及post-api；分析／单元／widget范围单列；CP01–04／14需实际本机存储 |
| Android完整App、跨进程／重启、原生业务vault/noBackup；iOS | NOT_RUN：T1设计范围，没有本片设备构建或测试 | 独立设备／明确窗口，不借用原认证资源；iOS需macOS/Xcode/设备，不能拿Android代证 |
| 认证候选整合及共享边界回归 | NOT_RUN：最终认证候选未交付 | T2新增hook后重开A/B影响项；T4固定版本、合并认证最新交接，验证真实链路 |
| 独立安全／容量／WAL备份清理与生产恢复 | NOT_RUN：本片设计不提供生产证据 | P01–P06相关放行证据另列，不以永久墓碑设计或开发库测试通过生产 |

## 5. 模块映射与下一入口

沿用B02／B03／B05／B06／B10，不新增重叠模块ID。本片仅覆盖文字业务子范围，完整模块仍待实现／验收；CP01–CP15全部NOT_RUN。未来最终授权／stop hooks影响A01／A03／A06／A08／A10／A13，客户端存储影响A12／N01，公开隐私映射X06/X07；本轮未修改这些运行源码，不重写它们旧版本PASS。

四份交接已同步：[模块交接](module-acceptance-handoff.md)、[台账](module-acceptance-ledger.json)的currentCommunityTextT1、[HANDOFF](HANDOFF.md)与[progress](progress.md)。台账已有认证字段及记录保留，新增设计记录独立注明分支／版本／证明范围。

下一步为T2 S1–S4：迁移／权限与授权包装 → 命令／任务／生命周期hooks → worker／阅读／默认身份 → 实际SQL／HTTP并发及共享回归。后端初估52–80有效工时，Flutter独立估算；T4候选整合、环境与设备预算另列，不据此承诺上线日期。

本轮只有源码／测试源性质的设计契约、checker和小型脱敏记录，没有创建数据库、私钥、APK、大日志或专用缓存。远端同名分支已在先前创建，当前设计未提交／推送／部署。
