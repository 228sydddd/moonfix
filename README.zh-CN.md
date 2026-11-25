# MoonFIX

[English](README.md)

MoonFIX 是使用 MoonBit 编写的经典 FIX 4.4 TagValue 协议库和离线 capture 审计工具。它解析 SOH 分隔的帧，检查 `BodyLength` 和 `CheckSum`，并提供调用方自备字典验证、扁平重复组解析、确定性会话状态转换与 JSON Lines capture 报告。

## 使用场景

- 网关和客户端开发者：将入站帧解析为保序字段，并编码带正确 framing 字段的出站消息。
- 集成 QA 工程师：把消息交给纯函数会话 reducer，在不连接交易对手时检查当前支持的 Logon、心跳、序号缺口、重发和 GapFill 行为。
- 运维与工具作者：审计保存的文本 capture，并在脚本中消费稳定的 JSONL 消息与 finding；存在 finding 时退出状态为 1。

这些场景来自既有 FIX 集成工作流，不代表用户访谈或生产交易验证。

## 已实现范围

- 保留字段顺序的 TagValue 解析与编码；检查 ASCII、字段数、大小、`BodyLength`、终止字段和校验和。
- 调用方提供字典后，可验证消息类型、必填/重复标签、枚举、值类型及 Length/Data 配对。
- 扁平重复组解析，检查 delimiter、成员顺序和条目上限。
- 对当前实现的 Logon/Logout、心跳/TestRequest、序号缺口、ResendRequest 和 SequenceReset 分支执行纯状态转换。Logon 要求 `EncryptMethod=0`；`ResetSeqNumFlag=Y` 会重置双向序号，并区分 GapFill 与 Reset 的序号处理。
- capture 重同步、消息间 CR/LF、序号缺口/重复/乱序诊断及确定性 JSONL 输出。
- Node.js 文件 CLI：审计干净退出 0，有 finding 退出 1，用法错误退出 2。

## 边界与限制

MoonFIX 不实现 Socket/TLS、交易场所连接、订单执行、FIXT 或 FIX 5.x、完整 Orchestra 编译器、分发字典、嵌套重复组、完整定时器/会话生命周期或二进制 SBE。解析器面向文本字段，不支持二进制 Length/Data 负载内部含 SOH。CLI 单次读取一个不超过 64 MiB 的文件。业务字典由调用方提供，项目不捆绑字典。尚未运行 QuickFIX 自动差分测试，也未通过 FIX 4.4 全量认证；未经独立验证，不应接入真实交易链路。可观察行为见[协议行为说明](docs/protocol-behavior.md)。

## 安装与环境

```sh
moon add 228sydddd/moonfix@0.1.0
```

库在 `wasm`、`wasm-gc` 和 `js` 目标上检查。文件 CLI 需要 Node.js 和 MoonBit JavaScript 目标；库无外部 MoonBit 运行时依赖。

## 库 API 示例

```moonbit
let decoded = match @moonfix.parse_message(wire) {
  Ok(message) => message
  Err(error) => abort("invalid FIX frame: " + error.detail)
}
let normalized = match @moonfix.encode_message(decoded) {
  Ok(encoded) => encoded
  Err(error) => abort("cannot encode message: " + error.detail)
}
```

集成方按对端配置构造 `Dictionary` 和 `MessageDefinition`。会话 reducer 返回新状态及有序动作，不执行网络 I/O：

```moonbit
let transition = match @moonfix.apply_inbound(state, decoded) {
  Ok(value) => value
  Err(error) => abort("session transition rejected: " + error.detail)
}
let next_state = transition.state
```

?????????????????

```moonbit
let heartbeat = @moonfix.send_heartbeat(next_state, test_request_id=Some("probe-1"))
let resend = @moonfix.send_resend_request(next_state, 4, 0)
```

导出签名见 [`pkg.generated.mbti`](pkg.generated.mbti)。

## Capture CLI

在项目根目录运行：

```sh
moon run cmd/main --target js -- examples/heartbeat.fix
cat examples/heartbeat.fix | moon run cmd/main --target js -- -
```

每行输出一个 `message` 或 `finding` JSON 对象，可交给 `jq` 等工具处理。输入是 SOH 分隔的文本 capture，消息间可有 CR/LF，不是以空格分隔的 dump。文件访问由 Node.js `node:fs` 提供。其他目标可使用库 API，但该文件 CLI 不支持它们。

## 验证

```sh
moon fmt
moon info
moon check --target wasm
moon check --target wasm-gc
moon check --target js
moon test --target wasm-gc
moon build --target wasm-gc
moon check cmd/main --target js --deny-warn
moon build cmd/main --target js
moon run cmd/main --target js -- examples/heartbeat.fix
```

测试覆盖 framing 边界、校验和错误、字典错误、重复组、会话转换、capture 重同步和序号审计。示例由项目编写，不包含第三方 fixture。

## 参考与许可

TagValue、字段和会话行为参考 FIX Trading Community 的 FIX 4.4 资料。QuickFIX 是行为参考概念，不是代码依赖。本仓库不再分发标准全文、第三方字典、上游源码或上游 fixture。

MoonSBE 是相邻项目，处理 FIX SBE XML schema、二进制 codec 和代码生成；MoonFIX 处理经典 FIX 4.4 TagValue、调用方字典、会话处理及文本 capture。MoonFIX 不实现 SBE，也不使用或复制 MoonSBE 源码和 fixture。边界查重记录见[此处](docs/competition/duplicate-check.md)。

Apache-2.0，见 [LICENSE](LICENSE)。实现、测试和文档由 AI 工具辅助生成；贡献者应审阅协议行为、边界和参考合规性。
