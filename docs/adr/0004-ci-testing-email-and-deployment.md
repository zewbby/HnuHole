# CI、测试、开发验证与部署基线

状态：accepted（2026-09-23）。项目先使用本地 Git 与 GitHub Actions；服务端测试采用 Go 单元测试加真实 Docker PostgreSQL 集成测试；开发邮箱使用 Mailpit 与开发验证适配器；生产部署采用容器化无状态 API、托管 PostgreSQL 和 S3 兼容对象存储，首期单区域部署，不从第一天引入 Kubernetes。用户对 Git/GitHub 不熟悉，提交、分支、推送和 Actions 检查必须提供逐步操作说明，不假定其已掌握 Git 工作流。

## 工程边界

- 本地 Git 是当前提交历史的基础（已于 2026-09-23 初始化 `main`，首个提交为 `bd6f109`）；当前远程 `origin` 已绑定 `https://github.com/zhubaozhenshuai666-lang/HnuHole.git`，开发分支 `feature/engineering-baseline` 已跟踪对应远程分支。GitHub Actions 负责后续格式检查、静态分析、单元测试、迁移检查和集成测试；默认分支保护与发布凭据仍待配置。
- 领域逻辑使用 Go 单元测试；Repository/API 使用从空库执行迁移的真实 PostgreSQL 集成测试，不用 SQLite 或内存数据库替代服务端 PostgreSQL。
- Mailpit 接收开发邮件；验证码规则仍按产品规则执行，自动化测试通过开发验证适配器读取验证码，不在客户端内置万能验证码。生产环境再替换真实投递服务。
- API 以容器运行且不依赖本机磁盘保存业务状态；数据库和图片分别由托管 PostgreSQL 与 S3 兼容对象存储承担。首期单区域，后续按负载增加 API 实例、负载均衡、缓存或队列。
