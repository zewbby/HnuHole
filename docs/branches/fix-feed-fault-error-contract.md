# 隔离GET错误注入的严格响应契约

工作项 FEED-FAULT-ERROR-CONTRACT-01，2026-10-20。基于已合并#32 main `f950caa60ecb4bea93e23778bfa9f51c6f11591d`，独立worktree/分支 `codex/fix/feed-fault-error-contract`。状态：分支实现及聚焦回归PASS，尚未合并、尚未更新在线入口；正式环境未部署。

复查发现#32辅助GET inject_401/503只生成error正文，没有与X-Request-ID相同的body.requestId。生产客户端HttpPostApi严格要求两字段及关联ID相等，因此旧注入会进入FormatException的401/503分类回退，不能当作规范错误解析通过。真实200/202后drop和hold旧请求412使用真实上游响应，不受影响，旧设备证据保持原来源和范围。

修复只在隔离Python入口生成一次随机16字节、22字符canonical base64urlNoPad requestId，同时用于header和正文，并以syntheticRequestId记录；没有续期元数据，不触达上游，没有改产品、Dart、数据库、Gate、TLS guard或规则范围。客户端严格契约保留。

先给真实TLS用例补严格顶层字段、code、body/header ID相等和canonical编码、message上限、无续期头、no-store，以及上游GET/PUT均不增加的断言；旧实现12项中1项实际FAIL（缺requestId）。修复后同命令12项全PASS、0FAIL/0SKIP：`python3 -m unittest discover -s tools/feed_staging -p 'test_*.py' -v`。CI沿用Feed staging tools及Collaboration，最终head结果以PR回执为准；Go/Flutter/SQL未改，不额外宣称其回归。

独立同事已确认根因和客户端契约，最终提交仍需独立review。手机GET注入保持NOT_RUN，修复合并/交付前不向设备提供；已有赞藏drop/迟到412和评论202配合可继续使用原入口。正式环境不触碰，不把状态码回退提升为规范错误体覆盖。

相关记录：[部署与恢复](../release/feed-staging-20261020.md)、[隔离故障控制](../release/feed-isolated-faults-20261020.md)、[源码](../../tools/feed_staging/fault_proxy.py)、[严格TLS回归](../../tools/feed_staging/test_fault_tls.py)。
