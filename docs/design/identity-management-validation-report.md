# B02身份管理基础：实施与验收交接

日期：2026-10-03（Asia/Shanghai）。任务单：[I1–I4](identity-management-plan.md)。本片登记目标为 **基础管理已实现，业务联动待实现**；完整动态验收另行登记，源码完成不等于验收通过。

## 实现边界

在 `codex/auth-privacy-handoff` 的 `/Users/zewbao/Desktop/workspace/Hnuhole/remote-auth-privacy-handoff` 继续开发，HEAD仍为 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`，保留原认证／设备工作区改动，未提交／推送。当前源码指纹、真实命令输出和测试入口见[机器记录](../../services/api/authlab/identity-management-verification.json)，旧报告的证据不改写。

| 范围 | 实现位置 | 待验边界 |
| --- | --- | --- |
| 本人列表／创建／改名／删除与默认头像 | `services/api/internal/authprivacy/community_identities.go`、`identity_rules.go`、迁移 `0011_identity_management.sql` | Go编译、真实SQL／race未执行 |
| 全部访问经最终Gate／会话／归属／可信时间复核 | 账号→限制→会话→Gate锁顺序，业务读写在最终授权回调内；`identity_endpoints.go` 仅序列化本人字段 | 冻结、接替、过期、禁言／封禁与异常提交验收待执行 |
| 资源并发与原意图核对 | 账号行锁串行化；效果与成功或拒绝终态回执原子提交；永久账号归属键摘要／意图HMAC | 真实并发／丢响应／迟到请求／跨账号同键待执行 |
| 移动端设置入口、列表和编辑 | `apps/mobile/lib/src/identity`、`main.dart`，我的→设置→身份管理 | Flutter分析、API／controller／widget和真机验收未执行 |
| 持久待核对操作与会话失效 | origin隔离vault内按accountId＋username保存不可变操作；同Bearer截止先持久再展示；authorityVersion及请求代次过滤迟到结果 | 本机对象重建测试不代证真实进程；杀进程／安全存储失败／账号切换仍需真机证据 |

注册不自动建身份，无身份不影响目录浏览。当前最多保留三个，不能删除最后一个；累计成功创建计数不因删除减少。第三次累计创建后开始六个月间隔，每次成功创建重新计时；按上海日历加六个月并夹紧目标月末，保留原时分秒。昵称NFC归一、大小写敏感、同账号判重；二至十二可见字符，输入法组合结束后过滤非法字符和截断。创建不启动改名等待；首次成功改名后等待满30天。同名改名是无副作用成功，不重置时间。默认头像标识固定 `default-v1`，用户可不上传头像直接建立身份。

独立复核发现“先查不到回执→重试确定拒绝→原请求迟到成功”的窗口，因此确定业务拒绝也绑定原键并成为不可重执行的终态。查询 `COMMITTED`／`REJECTED` 可结案；`NOT_FOUND`只证明当前无回执，不能当作旧请求永不执行，继续保留原意图并只用同键重试。失败不消耗创建机会或改名时间，但已终结的操作键不能用于新意图。SQL／Gate／未知提交故障不记录假拒绝。

删除保留稳定ID、归属和删除时刻并清除昵称／头像；原始身份标记不转移。列表不暴露其他账号或已删除资料。帖内绑定、发送任务、旧帖占位与本人列表移除、聊天／备注清理均随B05/B06/B07/B08/B09/B10实现；本片删除确认说明既定业务影响，不据此声称投影已实现。自定义头像上传／审核登记到后续媒体功能，审核员强制重置昵称与改名例外随B11治理实现。首次发帖／评论创建身份后恢复原输入也随发送模块接入。

## 实际检查与未执行项

只使用现有工具，未下载Go／Flutter／数据库工具或大型缓存，未创建数据库、私钥、APK或服务进程。

- YAML／本地引用／身份契约字段与必需header结构通过，覆盖四份OpenAPI；此项不等于完整规范或实现验收。
- `git diff --check` 和文档／台账／路径一致性检查的最终结果及命令输出以机器记录为准。
- 完整OpenAPI校验缺 `openapi-spec-validator 0.9.0`，记 `BLOCKED`；校验未实际完成。
- Go／gofmt、Flutter／Dart、Docker／PostgreSQL／Goose缺失，编译、格式化、SQL、race、真实HTTPS联调和移动端测试记 `NOT_RUN`；相应工具启动尝试另记 `BLOCKED`。
- Android／iOS小屏大字、无障碍、输入法、真实安全存储及进程重启未执行；不以源码或内存vault代证。

## 保留测试与复验命令

服务端纯规则入口 `identity_rules_test.go`；真实SQL入口 `community_identities_test.go`；真实TLS替身／HTTPS＋SQL入口 `authprivacyhttp/identity_endpoints_test.go`。移动端测试文件在[机器记录](../../services/api/authlab/identity-management-verification.json)和[台账](module-acceptance-ledger.json)列出。全部保留源码：3个Go纯规则函数、11个SQL函数、2个HTTP函数，以及35个Dart案例；这些数量不是通过数。现存依赖锁定文件纳入本片指纹。

先格式化新增Go/Dart，固定被测指纹；复用已确认归属的全新一次性开发／升级库。现有runner会reset schema，不能传未知或真实用户DSN；WSL2使用Linux文件系统。没有 `--module` 新参数。

```sh
# 仓库根：锁定既有校验环境
python packages/openapi/check-specs.py

# services/api：Go编译／规则／所有回归；无DSN的SKIP不计SQL通过
go test -race -count=1 -p 1 ./...
go vet ./...
sh authlab/run-isolated.sh
sh authlab/run-runtime-isolated.sh

# apps/mobile：先用现成Flutter运行pub get，再执行全部聚焦和共享认证回归
flutter analyze
flutter test --reporter expanded
```

现有R03的runtimeprobe和R05的Dart＋SQL fixture尚未扩展B02身份操作序列；动态验收时需补实际非owner cmd身份CRUD／原核对、真实Dart＋SQL场景，不能用原认证runner通过代证B02。Go真实HTTPS／SQL与Dart TLS替身源码已保留，分别验证对应边界。

SQL验收至少包括：零身份浏览；同账号大小写／NFC判重与不同账号同名；2→3并发创建、2→1并发删除、同时同名改名；删建累计阈值；月末／闰年／精确六个月及30天边界；失败机会不消耗；跨账号资源与同键独立；成功／拒绝回执重放、改payload冲突、迟到旧请求不复活；新会话查询旧意图；在账号锁等待中冻结／接替／过期。运行时验迁移10→11、非owner权限、缺表／缺DML就绪拒绝、升级数据保持和重启。

移动端验：空状态与默认头像；三名额／冷却日期／改名日期；合法输入保留、非法提示、最大12与IME；退出编辑保留同机输入；丢响应、重启原键核对、拒绝终态后新操作、查询缺记录仅同键重试；截止持久失败不发布；401／503／账号切换／后台恢复和迟到响应；弹层旧身份资料在会话变化后消失；删除确认包含昵称／头像／创建日期与既定影响。涉及业务投影的验收明确留到对应模块。

共享AuthStore／HTTP路由／运行时迁移变化重新打开A00/A01/A02/A03/A05/A06/A07/A08/A09/A11/A12/A13、N01/N02/N03、B01/B03/B10的相应当前回归，不覆盖历史SHA证据。跨模块X01/X02/X03/X04/X05/X08先验基础；X06已有受限会话源码场景，完整公开任务／关闭清理仍依赖帖子／聊天／治理，X07投影随业务验收。2026-10-03 用户纠正分支范围，下一步改为[匿名收口清单](auth-privacy-closure-checklist.md)；现有身份尚未接入整账号正式关闭的生命周期单列AC02，不能以延后帖子／聊天投影代替该项。该盘点不改变本片源码指纹和未执行验收结果。
