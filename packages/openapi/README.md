# OpenAPI 契约

| 契约 | 范围与状态 |
| --- | --- |
| [channel-api.yaml](channel-api.yaml) | 当前通道目录切片的接口唯一来源；服务端和客户端据此实现目录 |
| [identity-api.yaml](identity-api.yaml) | B02本人身份列表／创建／改名／删除与账号归属幂等结果核对；业务联动随对应模块实现 |
| [verifier-auth-api.yaml](verifier-auth-api.yaml) | 独立验证方 V，6 个操作：OTP申请／确认、原结果核对、内部正式释放与退役收据持久确认；实施前评审稿 |
| [community-auth-api.yaml](community-auth-api.yaml) | 社区方 C，22 个操作：开户、用户名密码登录、会话／设备、独立恢复、凭据管理、注销与内部退役；实施前评审稿 |
| [post-api.yaml](post-api.yaml) | T1文字发布设计契约，14个操作：发布／核对／封印、默认身份、本人任务维护、feed／详情／本人帖子与作者删除；尚无handler或可执行迁移 |

五份文件采用OpenAPI 3.0.3。认证架构和固定签名字节分别以[逻辑契约](../../docs/design/auth-privacy-data-api-contract.md)与[注册协议](../../docs/design/auth-privacy-registration-protocol.md)为准；表约束、事务、留存和升级顺序见[数据库迁移设计](../../docs/design/auth-privacy-database-migration-design.md)。认证隔离实现和本次运行时实施范围见[实施计划](../../docs/design/auth-privacy-runtime-business-integration-plan.md)。文字业务的事务／停止代次见[后端设计](../../docs/design/community-text-posting-backend-design.md)，操作字节与跨端要求见[API说明](../../docs/design/community-text-posting-api.md)。

目录 `200` body 仍为 `{channels:[…]}`、七记录与五字段。增加必需 `Session-Expires-At`、`X-Request-ID`、`Cache-Control: no-store`，错误统一为 `error:{code,message,details?}`＋顶层 `requestId`；公共边界的 400／403／429 与会话 401／服务或目录 503 均列入契约。只有最终授权事务提交成功后才能发送截止和目录；客户端持久写截止后发布节点。缺失或非法截止不能当作目录成功。

## 安全约束的表达

V/C 使用真实独立 HTTPS origin。`servers: /` 只是相对部署位置，不授权在同一网关／运维主体下共用身份、密钥或访问权限。固定二进制票据用规范无填充 base64url；解码重编码、实际字节长度、重复 JSON 键、跨字段关系、锁内截止和幂等状态等不能只靠生成器检查。

内部路由另设入口，`x-mtls-required: true` 与 `x-allowed-peer` 强制实际客户端证书和预期对端验证；OpenAPI 3.0.3 没有原生 mutualTLS 方案，`security: []` 只表示没有普通 HTTP 凭据，**不是公共匿名接口**。扩展不会自动生成 mTLS 部署；固定消息签名仍须验证。不得使用可伪造的证书请求头代替传输认证。[OpenAPI 3.0.3 规范](https://spec.openapis.org/oas/v3.0.3.html)

所有认证响应含 no-store 与各方独立请求编号；未知结果先核对，原码／令牌不重放。完整幂等结果到期原位收缩为无身份的 EXPIRED 键摘要锚点；注销申请 ID 同样防重执行。长期锚点和槽位终态有存储成本，生产前须完成独立审阅、容量与清理验证。

## 校验与生成

历史三份文件曾通过 `openapi-spec-validator 0.9.0` 完整规范检查；本次改动的实际验证状态应以运行时交付报告为准。锁定 Python 校验依赖见 `requirements-check.txt`；脚本拒绝重复 YAML 键和缺失本地引用，并核对目录五字段、七记录以及各响应必需 header。用已有工具环境执行：

```sh
python packages/openapi/check-specs.py
# 只有 PyYAML 6.0.1 时可先检查结构；此项不能代替 OpenAPI 完整校验
python packages/openapi/check-specs.py --yaml-only
```

文字契约另有专项静态检查，验证严格公共DTO、UNKNOWN／封印及固定身份重试边界、必需header、字数元数据和9组摘要向量。需要已有PyYAML；不下载库，不代表Go／Dart字素算法或实际业务通过。本轮实际结果及环境命令见[T1报告](../../docs/design/community-text-posting-t1-report.md)。

```sh
python -B tools/check-community-text-contract.py
```

目录生成固定使用 `oapi-codegen v2.4.1`，由已有安装或 `OAPI_CODEGEN` 指定可执行文件；脚本不下载工具。只生成目录类型与 chi-server 接口到被忽略的 `packages/openapi/generated/channel-api.gen.go`。本地生成后保存该文件，后续 `--check` 重生成到私有临时目录并逐字比较，可发现本地契约与生成物漂移；此文件不提交，CI 每次从契约重新生成并做 HTTP 契约回归。

```sh
sh packages/openapi/generate-channel.sh
sh packages/openapi/generate-channel.sh --check
```

原始日期、规范能力字节、最终授权事务和 Dart 持久 fence 由实现测试验证。生成／静态校验不等于实现测试或独立安全审计；工具缺失时须明确列为未执行，不使用未锁定 latest。
