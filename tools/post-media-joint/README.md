# 帖子图片真实进程联合联调

仅运行一次性宿主环境。脚本构建并启动实际 `cmd/api`、`cmd/verifier`，用正式 Goose 创建空 C/V 库并核对13→14的通道种子保留及重复迁移无操作；C/V使用非owner运行角色、独立Gate/签名/证据/恢复材料。SMTP捕获、控制接口和透明TLS断网代理是测试夹具；它们不代替业务处理、图片验证或数据库。

前置工具：Linux非root用户 `hnuhole`，已有 Go1.22.2、PostgreSQL16、Goose3.22.1、Python3.12与独立固定 Pillow12.3.0环境，Flutter3.47.5/Dart3.13.4独立副本及匹配的锁定Pub依赖。脚本不下载SDK/启动Docker，不允许外部DSN。现有Goose路径 `/mnt/e/Hnuhole-env/linux/bin` 仅执行现成二进制，不写该目录；其余缓存、临时目录、数据库、文件vault、SMTP及全部密钥只在指定root。

准备一个新建、规范、非符号链接且仅本用户可访问的 `/home/hnuhole/post-media-joint-*`。`.owner` 内容以 `post-image-integration-20261015|` 开头并记录本任务源码目录。root下放置本轮固定源码镜像 `source/`、独立SDK `flutter/`、锁定Pub缓存 `pub/`，并建 `home/tmp/go-build/go-mod/go-path/bin/fixtures/logs`；shell文件转换LF。不得把SDK/cache链接回其他会话，工具的package_config也须指向本任务路径。保留锁文件，用 `pub get --offline --enforce-lockfile`；缺少依赖先报告具体缺口。

```sh
python3 -B source/tools/post-media-joint/run.py \
  --root /home/hnuhole/post-media-joint-20261015
```

每次新建随机 `run-*` 私有目录和对应日志子目录，路径写入 `logs/latest-run.json`。客户端分 `write/read/edges` 三个真实 Flutter 进程：

- 真实注册/SMTP/身份/通道、生产写帖与确认、九图空正文、持久意图与丢CREATE响应。
- 新进程恢复、部分上传/丢PUT收据、缺失项补传、独立SQL与原字节散列、完整公开、生产主入口到查看器。
- 删帖/能力隔离/取消保留原图、真实发布停止后的编辑RETRY、验证器漂移503恢复、Gate冻结与恢复后重新登录、真实60秒租约、退出后的迟到响应。

`services/api/authlab/post-media-control` 只供此lab调用已有 `ApplyAccountMute` 与真实Gate，短时限制本库中给定合成任务的账号；要求规范owner标记、私有配置、受限运行角色、同一run的socket/application_name。不接受任意账号、外部数据库或直接改状态来伪造业务成功。它不是公开管理接口。

成功必须有19个客户端检查点、独立SQL/请求计数、三个子进程退出0，且运行前后232项当前输入摘要相同；若以后增加源码，文件数按当次实际登记。`joint-summary.json`保留命令/时间/退出码/日志散列/源码指纹。finally只停止本次创建的PID和本次PG数据目录，不重启/停止任何现成服务。失败时私有材料暂留供定位；交付前提取小型脱敏证据，再按owner和绝对路径精确清理，不提交配置/账号/密钥/数据库/大制品。

选图、vault和相册writer在宿主用合成文件/文件替身；保存resolver实际重新取受保护原图并核对临时文件原字节，但这不代表Android/iOS的系统选图器、原生安全存储、Gal相册、动画播放或真机手势通过。脚本没有ADB/手机/发布/部署操作。
