# Flutter F2协议向量快照

本目录的post-command-v1.json与后端已发布514a944560988e3d8d599e6f9fe9d5d99fe07f88的Git blob一致，含9组framing/SHA256和7组Unicode16字素输入期望；其旧scope字段是T1历史说明，本分支没有执行Dart/Go符合性测试。

本分支规范见[F2设计](../../docs/design/community-flutter-f2-design.md)、[版本锁](../../docs/design/community-flutter-f2-lock.json)及[OpenAPI](../openapi/post-api.yaml)。[上游API说明](https://github.com/zewbby/HnuHole/blob/514a944560988e3d8d599e6f9fe9d5d99fe07f88/docs/design/community-text-posting-api.md)和[T1历史报告](https://github.com/zewbby/HnuHole/blob/514a944560988e3d8d599e6f9fe9d5d99fe07f88/docs/design/community-text-posting-t1-report.md)属于固定来源，不需要另一工作树的未提交文件。

当前可执行静态入口：

    python tools/check-community-flutter-f2.py

Python环境需PyYAML。此命令检查Git blob、14操作与内部ref、发布依赖锁、v1设计DDL语法及F1资产保持；不验证Dart字素、原生命令摘要、真实网络/数据库或手机状态。

F3导入固定post_protocol.dart与对应post_protocol_test.dart后，在本分支Flutter环境运行共享向量和15/16、3000/3001、空白、非法Unicode及字节上限测试。原文组合/分解形式、LF/CRLF不得归一化为同一摘要。
