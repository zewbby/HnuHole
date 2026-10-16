# C/V 同机开发基础设施

Compose提供分离的PG16 C／V服务与Mailpit，只绑定literal loopback。C为 `127.0.0.1:55432/hnuhole_c`，V为 `127.0.0.1:55433/hnuhole_v`；SMTP1025／Mailpit UI8025。固定images `postgres:16.6-alpine`、`axllent/mailpit:v1.21.8`。PG16／Go1.22尚无本轮实测；本机Go、PG、Docker已清理，不能把配置静态检查报告为实际启动成功。

从 `services/api` 按 [API README](../services/api/README.md) 初始化新私有material目录，生成独立runtime／migration／恢复密码与开发PKI。`infra/.env.example`只有占位符；Compose要求显式提供各方独立密码，不含演示token／万能码。按README把私有password files加载进环境后启动：

```sh
docker compose -p "$DEV_AUTH_PROJECT" -f infra/docker-compose.yml up -d --pull never --wait
```

首次空卷运行 `postgres/init-auth.sh`：各侧NOLOGIN owner、LOGIN migrator／runtime，C额外单个恢复role与NOLOGIN业务目录角色；撤PUBLIC CONNECT／TEMP和schema CREATE。迁移由独立migrator经SET ROLE owner执行，runtime不持owner membership、不做DDL。应用后运行 `grant-community.sql`／`grant-verifier.sql`，仅授所需DML／identity sequence与C目录SELECT；迁移11身份及累计表SELECT/INSERT/UPDATE、回执SELECT/INSERT（不授DELETE和回执UPDATE）；禁止旧session访问及永久事实DELETE。新卷使用独立named volumes，标记 `hnuhole.resource=*-development-*`；现有卷不会因环境变化自动更新密码或角色。

WSL2的Go／密钥／锚点／runner放在Linux文件系统，通过Docker Desktop WSL集成或WSL内Docker运行Compose。先在WSL验证published loopback端口，宿主机Flutter／Android另跑；Go fixture调用Flutter必须使用WSL内Linux可执行文件。macOS/Linux沿用POSIX文件锁、0600材料和0700私有目录。Windows原生Go与设备/Xcode还未验收。

默认Go C/V公开8443／8444与内部mTLS9443／9444也在loopback。设备访问只开放明确且匹配SAN／origin的开发HTTPS入口；不开放PG／SMTP／Mailpit／内部监听。生成的开发根、签名证据和锚点属于同机开发信任，不证明双运营方独立或生产可信灾备。V暂直接用数据库时钟，独立Gate另片。

启动／停机／重启复用同一私有材料与卷，API启动不解冻；`authdev recover`是显式受限签名恢复，`authdev watch`单独每分钟续发最多五分钟证据。停证据后C Gate过期fail closed。Mailpit仅本机合成校邮，OTP不进服务日志；只读开发probe取码不构成公共能力。

从 `services/api` 执行 `sh authlab/run-runtime-isolated.sh`：仅使用现成工具、缓存images/modules，分配随机端口／唯一项目／0700目录，正式迁移、受限runtime、升级与实际HTTPS/Mailpit闭环后trap只清理本次资源。工具缺失即退出，不下载。

`DEV_AUTH_PROJECT` 随 API README 中的新私有目录唯一生成；保存它以便停机／重启。手工环境先 `stop` 保留重启数据。仅确认project归自己且不再需要时才 `docker compose -p "$DEV_AUTH_PROJECT" -f infra/docker-compose.yml down -v`，并删除自己初始化的私有目录。不执行全局prune或清未知项目／用户数据。旧 `infra/.data` 若存在，按其原归属保留；本轮不迁移或删除未知旧库。
