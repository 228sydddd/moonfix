# MoonFIX 协议行为说明

本文界定当前实现的可观察行为，避免把 FIX 4.4 子集误认为完整引擎。公共类型和函数签名以 `pkg.generated.mbti` 为准；验证命令见 `../README.md`。

## 消息 framing

`parse_message` 读取 SOH 分隔的 ASCII TagValue 消息，保留字段顺序与重复 tag。解析器验证 BeginString、BodyLength、结尾 CheckSum 形式和校验值，并受 ParseLimits 的消息字节数和字段数限制。错误带稳定分类与偏移量。

`encode_message` 根据消息内容生成 BodyLength 和三位 CheckSum。字段值含 SOH、非 ASCII 内容、保留 framing tag 或超过限制时返回结构化错误。Length/Data 负载中嵌入 SOH 的二进制语义不在支持范围内。

## 字典与重复组

Dictionary 由调用方构造，MoonFIX 不随包分发交易场所字典。validate_dictionary 检查定义自身的一致性；validate_message 对消息类型、允许/必需字段、字段重复、枚举和值类型及 Length/Data 配对生成 ValidationIssue。

parse_group 使用调用方提供的 count tag、delimiter、成员顺序和最大条目数，要求 count 唯一、成员定义无歧义且实际成员范围与声明条目数一致，返回各条目字段及组后首个字段下标。当前组模型不支持嵌套递归组。

## 会话 reducer

apply_inbound 是确定性状态转换：输入旧 SessionState 与一条消息，结果是新状态及有序 SessionAction。它不执行 socket I/O、等待或定时器。Logon 要求唯一的 `EncryptMethod(98)=0` 和有效 `HeartBtInt(108)`；其他加密方式不受支持。Logon 的 `ResetSeqNumFlag(141)` 只能出现一次且值为 `Y` 或 `N`；`Y` 要求入站序号为 1，在接收端回复中确认该标志，并将双方下一序号重置为 1。SequenceReset 的 GapFill 模式（`123=Y`）遵守普通入站序号顺序；Reset 模式（`123=N` 或省略）忽略 `MsgSeqNum` 的会话顺序判定，但要求 `NewSeqNo` 大于当前期望序号并推进状态。该 reducer 不实现完整交易生命周期。

## Capture 审计与 CLI

`audit_capture` 从文本 capture 中恢复消息边界；允许消息间 CR/LF，遇损坏数据尝试向后重同步，并报告 framing 错误及可识别的序号缺口、重复和乱序。JSONL 的每行是 message 或 finding 对象。

Node.js CLI 读取一个文件，最大 64 MiB；无 finding 返回 0，有审计 finding 返回 1，用法错误返回 2。文件访问失败由 Node.js 报告。CLI 只处理文本 capture，不是网络客户端。

## 验证边界

测试由本项目构造的消息和边界样例组成，覆盖三个 MoonBit target（wasm、wasm-gc、js）。当前未运行 QuickFIX 自动差分，也未通过 FIX Trading Community 一致性认证；不能据此推断完整 FIX 4.4 互操作性。
