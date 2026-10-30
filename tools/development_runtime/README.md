# 已核验日常开发版本的恢复器

仅用于本机 Linux/WSL、原非root部署用户；不用于生产或初始化新环境。修复旧入口选择C27而数据库已经C28的问题。版本由所有者批准的私有清单和receipt绑定，不按目录mtime/名称猜最新版，不自动回退。

## 本次已安装入口

2026-10-30原三个入口（邮箱reconnect、评论reference resume-development、shared-rate safe-resume）均已私有备份并改成薄转发，指向部署用户私有 `~/.config/hnuhole/development-runtime/` 中的固定恢复器release及 `current.json`。原命令仍可使用；三个入口只执行同一清单，不再导入各自历史部署脚本。未创建Windows计划任务或新自动开机服务，USB/透明TLS转发仍单独恢复。

当前清单批准的服务为a2e98eb C28/V7、两个独立限流Redis及第三个快照Redis。恢复器和清单位于私有Linux目录，release以源码SHA256命名；三个旧入口及私有清单不提交Git。安装前备份旧文件、验证候选清单，再原子替换清单及各薄入口；记录旧/新摘要及备份位置。跨文件替换不是事务，失败时应检查私有安装回执，不能盲目回退启动历史版本。本轮三个入口均已逐一实际调用验证。

## 运行与变更清单

```sh
python3 <已核验release>/resume.py --manifest <私有目录>/current.json --check-only
python3 <已核验release>/resume.py --manifest <私有目录>/current.json
```

`--check-only`只校验静态文件摘要、部署批准状态及adapter静态输入闭包，不连接数据库、不启动进程；输出明确不是就绪证明。正常模式先锁定同一私有目录的 `.resume.lock`，完成全部静态检查后核对进程、启动原库/Redis，同步双resume，最后按需启动watch/API并验证严格TLS就绪和代次/RECOVER审计不变。

清单是部署所有者输入，必须在所有者私有绝对Linux目录内、普通文件权限600，目录700，不可由不可信请求提供。不得把清单、密码摘要清单或原进程日志提交Git。更新部署时，负责人必须在核对新receipt/实际配置/schema/二进制后显式重新生成并审查清单、更新薄入口；不能给旧清单换个source字段骗过检查。代码或静态配置变化会拒绝启动，需要重新批准，不是自动支持任意未来部署。

清单 `DEVELOPMENT-RESUME/1` 必需字段：

| 字段 | 含义 |
| --- | --- |
| source / receipt / deploymentState | 已PASS启用部署的source和不可变回执/state路径（本适配器支持PASS_ENABLED_DAILY_DEVELOPMENT/PASS_ENABLED），schema须匹配真实DB |
| bin / config / operators | 当前community/verifier/authdev目录、C/V运行配置与目的绑定operator路径 |
| adapter / adapterState | 已审查的本机部署适配器源码及其ROOT/sourceSha/phase；本轮复用已pin的旧部署辅助函数，只用于SQL连接、Redis归属、spawn/health/quiesce，不调用其safe_resume/upgrade |
| files / dependencyFiles | 绝对路径→SHA256映射：当前API、authdev、恢复器源码、回执/部署状态、C/V/op静态引用、两限流Redis配置/ACL/operator及引用、快照配置/ACL、Redis和PG可执行文件及本次声明的共享库 |
| databases | 原data绝对路径、PG16 pgctl/postgres路径、原启动options、私有日志；不调用initdb/reset/restore/migrate |
| snapshotRedis | 原配置/ACL/pidfile/loopback端口与已核验initialProcess（PID/startTick/exe摘要）；运行后仅更新本恢复器私有process journal |
| schema / apiPorts / legacyCommands | 预期C/V版本、原公共loopback监听端口及明确拒绝的旧命令集合；未知端口占用同样拒绝 |

静态输入覆盖从adapter实际读取的文件递归推导，缺项拒绝；不是只有“清单列了的文件”才检查。Gate evidence/anchor及共享Redis可变进程journal不做整文件hash，否则正常续证据或一次Redis冷启就会导致下次漂移；它们分别由Gate验签/代次/外部锚和PID/startTick/exe/loopback归属校验。配置里的静态密钥文件继续pin。

## 失败与幂等边界

- schema/receipt/source/config/二进制漂移、旧API/watch、重复进程、未知监听占用、Redis PID复用、冻结均拒绝；不recover、不清Redis/AOF、不初始化namespace、不改变会话代次。
- 同步双Gate完成前不启动新API；失败时仅停止本轮新启动的服务（API按双Gate行锁quiesce）。已存在的进程、数据库/Redis持久数据不清理；新起的依赖保留供检查和重试，不声称事务式全回滚。
- 正确已有进程被保留；重复执行只resume证据/检查就绪，startedServices=0，PID不变。当前部署需先平稳停旧服务再换批准清单，脚本不会擅自替换已在跑的错版本。
- 清单/回执只表示当前明确批准的部署，不会扫描机器所有未来目录。未来部署必须更新本恢复器的批准清单；否则应视为未完成运维交接。

## 验证

`python3 -B -m unittest discover -s tools/development_runtime/tests -v` 及 `python3 -O -B ...` 均10项PASS。新CI运行同样边界回归，不用模拟测试冒充真实库。

最终安装源码已实际完成：三旧入口幂等PASS，平稳停4个API/watch、2个PG、3个Redis后从原入口冷启PASS；source/配置/二进制核验、严格C/V TLS ready、代次和RECOVER计数、会话记录不变；错误source私有副本在任何进程改变前拒绝。详见[任务](../../docs/branches/fix-development-runtime-resume.md)与[脱敏证据](../../docs/design/validation/development-runtime-resume-20261030.json)。
