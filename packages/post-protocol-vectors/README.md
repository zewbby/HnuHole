# 文字命令共享向量（T1）

[post-command-v1.json](post-command-v1.json)记录五种操作的9组二进制framing／SHA256设计向量，以及7组Unicode16字素计数期望。它不含账号、凭据或真实用户文字；固定UUID为测试样本。

规范见[API说明](../../docs/design/community-text-posting-api.md)与[OpenAPI](../openapi/post-api.yaml)。文本按严格UTF-8原文编码；组合／分解形式及LF／CRLF不可归一化为同一摘要，JSON字段顺序和等价转义不改变摘要。版本字段framing为unsigned64BE，API实际限制为1..2147483647。

T1的Python参考checker已验证9组frameHex和requestDigest，**没有执行Go／Dart字素计数**。7组字素计数是后续测试输入与期望，不是跨端PASS证据。T2与Flutter任务分别用锁定Unicode16实现读取同一向量，并补15／16、3000／3001边界、空白／不可见、非法编码与字节超限场景。

```sh
python -B tools/check-community-text-contract.py
```

本命令只检查设计不变量与摘要。实际执行记录见[T1报告](../../docs/design/community-text-posting-t1-report.md)；真实HTTP、SQL事务、设备与生产验收均另列。
