# OpenAPI 契约

| 契约 | 范围与状态 |
| --- | --- |
| [channel-api.yaml](channel-api.yaml) | 当前通道目录切片的接口唯一来源；服务端和客户端据此实现目录 |
| [verifier-auth-api.yaml](verifier-auth-api.yaml) | 独立验证方 V，5 个操作：OTP申请／确认、原结果核对与内部资格释放；实施前评审稿 |
| [community-auth-api.yaml](community-auth-api.yaml) | 社区方 C，22 个操作：开户、用户名密码登录、会话／设备、独立恢复、凭据管理、注销与内部退役；实施前评审稿 |

三份文件采用 OpenAPI 3.0.3。认证架构和固定签名字节分别以[逻辑契约](../../docs/design/auth-privacy-data-api-contract.md)与[注册协议](../../docs/design/auth-privacy-registration-protocol.md)为准；表约束、事务、留存和升级顺序见[数据库迁移设计](../../docs/design/auth-privacy-database-migration-design.md)。认证接口尚未实现，迁移设计没有执行 SQL。

## 安全约束的表达

V/C 使用真实独立 HTTPS origin。`servers: /` 只是相对部署位置，不授权在同一网关／运维主体下共用身份、密钥或访问权限。固定二进制票据用规范无填充 base64url；解码重编码、实际字节长度、重复 JSON 键、跨字段关系、锁内截止和幂等状态等不能只靠生成器检查。

内部路由另设入口，`x-mtls-required: true` 与 `x-allowed-peer` 强制实际客户端证书和预期对端验证；OpenAPI 3.0.3 没有原生 mutualTLS 方案，`security: []` 只表示没有普通 HTTP 凭据，**不是公共匿名接口**。扩展不会自动生成 mTLS 部署；固定消息签名仍须验证。不得使用可伪造的证书请求头代替传输认证。[OpenAPI 3.0.3 规范](https://spec.openapis.org/oas/v3.0.3.html)

所有认证响应含 no-store 与各方独立请求编号；未知结果先核对，原码／令牌不重放。完整幂等结果到期原位收缩为无身份的 EXPIRED 键摘要锚点；注销申请 ID 同样防重执行。长期锚点和槽位终态有存储成本，生产前须完成独立审阅、容量与清理验证。

## 校验与生成

本次三份文件通过 `openapi-spec-validator 0.9.0` 完整规范检查；另检查 YAML 重复键、本地引用、操作 ID、严格对象与字节编码。校验工具仅装在临时目录，没有加入项目依赖。后续 CI 工具包应锁版本，并运行等价的验证步骤：

```python
from pathlib import Path
import yaml
from openapi_spec_validator import validate_spec

for spec in Path("packages/openapi").glob("*-api.yaml"):
    validate_spec(yaml.safe_load(spec.read_text()))
```

此片段校验规范结构；CI 还须启用重复键拒绝、域与字节负向向量和语义约束检查。工具链就绪后用 `oapi-codegen` 生成 Go 类型／接口并核对客户端；生成文件不提交，规则见 `.gitignore`。静态校验不等于实现测试或独立安全审计。
