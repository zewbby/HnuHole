# 共享限流部署、恢复与回退runbook

仅为feat/shared-rate-limit-abuse-control的操作交接，不是本次部署授权。当前未部署/发布，样例新增规则全observe；先读[实际配置](shared-rate-limit-plan.md)、[架构](shared-rate-limit-architecture.md)及[验证范围](shared-rate-limit-verification.json)。不连接未知/既有库做隔离runner，不在生产运行authlab。

## 部署准备

1. 由环境owner明确C/V独立数据库、角色、Redis7单primary和namespace；分别准备32字节主体HMAC密钥、runtime/operator Redis密码、DB密码。私有普通文件权限不允许group/other，配置与秘密不入Git。operator JSON及其秘密路径相对该JSON解析。
2. 配套Goose v3.22.1分别前向迁移C至27、V至7，应用当前infra/postgres的C/V/runtime grants。C/V保持原最小权限审计；API不持namespace INSERT/DELETE或Redis CONFIG权限。不要以owner运行API。
3. 按redis-community.example.conf建立单primary/noeviction；V另进程/端口/ACL文件。runtime仅本namespace及样例注释所列命令；operator另加CONFIG GET用于初始化检查。Redis7.0不授权不存在的CLIENT SETINFO，7.2按样例说明处理。禁用默认用户，真实密码外部管理。
4. 复制对应observe/operator样例到私有目录，嵌入真实runtime配置的sharedRateLimit字段；核对runtime/operator政策完全相同，C/V namespace/密钥分离，可信代理CIDR仅显式配置实际链。不要把开发socket/端口当生产事实。
5. 构建services/api/cmd/ratelimitctl。只对确实全新、已迁移、空namespace元数据环境执行初始化（以下路径均为占位）：

```sh
ratelimitctl --config /private/community-operator.json --initialize-new-namespace
ratelimitctl --config /private/verifier-operator.json --initialize-new-namespace
```

初始化不能重复用于既有域。CLI不迁移SQL、不清Redis、不绕过恢复屏障。若SQL已初始化而Redis初始化失败，查明owner/ACL/noeviction等原因后走既有域恢复流程，不删除namespace重建。

6. 启动同policy的C/V API与原Worker/Outbox，核Gate/ready、C/V权限审计、30秒私有动作指标及正常读/ACK/上传/命令核对。当前验证只覆盖本地隔离，生产容量和校园真实共享IP阈值仍须观察。
7. observe先收正常流量/误伤/容量证据，再逐项enforce；模式变更也是policy变更，必须走下节。无原地热修改。

## 配置、密钥变更与故障恢复

1. 保存当前发布二进制/非秘密配置/迁移版本/policy及generation记录。确认Redis是支持的单primary/noeviction、持久DB元数据可用，Gate本身正常；不得通过放开Gate“恢复限流”。
2. 变更阈值、模式、容量、dedup/read或主体密钥时，生成新私有runtime/operator一致配置。显式运行：

```sh
ratelimitctl --config /private/community-operator.json --begin-recovery
ratelimitctl --config /private/verifier-operator.json --begin-recovery
```

按受影响域分别执行；只C变化不需无故推进V。此命令实际Reconfigure，generation++并写新policy/window，不是简单清缓存。只运行一个operator操作，不并发争抢generation。

3. 读取归属已知域的namespace状态与barrier（不输出凭据/主体记录），等RECOVERING结束。屏障至少max(old/new有效窗)并包含SW ReadSeconds、固定1秒最大在途deadline及dirty_until。默认dedup24h不意味着停24h；本observe样例C基准3631秒/V91秒，实际barrier可能更晚。
4. 更新所有实例为新policy。旧/off/observe实例最终SQL hash围栏会拒写，不能保留混合版本长期运行。恢复期verified-db写降级暂停，读/ACK有界保护继续；客户端保草稿/队列，不批量换键补发。
5. 到期由正常API恢复检查激活；确认READY、run_id/policy正确、指标无持续错误，再做一次同键重放、读/ACK及限定写验证。不要人工改barrier/state、FLUSHDB、删dedup/receipt或反复initialize。

普通timeout/OOM/断连不是429。仅post/comment/OTP经验证最终SQL可降级，并在最终事务原子dirty_until；它不保证新增阈值。DM/上传/昂贵登录fail closed。状态丢失/run_id变化由正常协议进入持久RECOVERING；同run_id但有dirty也不直接重开满桶。

## 回退

- 首选保留本次理解COMMAND_CLOSED和final policy围栏的新二进制，仅通过显式policy off/observe作配置回退；保留SQL迁移、永久回执及close锚。先停新增高成本写入，保留读取/ACK和持久回执核对，operator重新配置并等屏障。
- 如需禁用整个shared配置，先停齐相关实例、统一配置后再启动，禁止无shared与有shared实例混跑。此步骤未经本任务实际环境演练，不作为绕过policy围栏的捷径。
- 改回旧阈值/旧密钥同样generation++，等max(old/new窗+dirty)后再恢复。不能直接用不认识policy围栏/COMMAND_CLOSED的基线二进制接管写请求，否则旧迟到命令可能破坏新终态。
- C迁移27与V迁移7是前向修复边界；不要Goose Down或删除namespace/admissions/commands关闭锚。保留Worker/Outbox及永久回执，按账号锁/Gate正常收敛临时项。
- 未确认DM隐藏通过close回执收敛；SENT不能伪造撤回。帖/评429仍由用户手动同键重试，不能运维批量自动发表。
- 若无法满足兼容回退条件，保持高成本写fail closed，前向修复；本次未执行生产部署/恢复/回退演练。

## 隔离复验入口

仅在明确归属一次性环境运行 `sh services/api/authlab/run-shared-rate-limit-isolated.sh`，要求Go1.22.2、PG16工具、Redis7、Goosev3.22.1及锁定Pillow运行环境。runner创建自己的C/V两个cluster、Redis和private socket，退出只清自己资源。常规无DSN测试应SKIP真实SQL fixture，有ownedDSN但缺工具/图片fixture则FAIL，不默默降级为替身。远端workflow在6e50244已通过13workflow/23job；见[版本化CI证据](shared-rate-limit-remote-ci-verification.json)，后续文档head以PR检查为准。
