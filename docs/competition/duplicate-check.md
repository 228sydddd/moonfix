# MoonFIX 选题与语义查重

- 核验日期：2026-11-25（交付前反向复核）
- 候选：FIX 4.4 金融交易协议工具链
- 预留仓库/模块：228sydddd/moonfix / 228sydddd/moonfix

## 选题结论

本项目拟实现可嵌入 MoonBit 程序的 FIX TagValue 消息编解码、调用方提供字典的语义验证、确定性会话状态处理，以及可复用的离线 capture 审计 CLI。选题依据是已有成熟跨生态协议、长期维护的 FIX 引擎，以及 MoonBit 搜索/清单/注册表中未发现对应金融 FIX 消息与会话实现。该结论只限于本次记录的检索范围，不声称绝对唯一。

目前没有用户访谈或特定交易商采用承诺。三类使用者及工作流是基于已有 gateway、协议集成测试和 capture 运维任务作出的需求推断，必须由交付的示例和独立测试证明可用性，不能表述为已访谈的用户需求。

## 用户任务与闭环

| 使用者 | 输入与处理 | 可复用结果 |
| --- | --- | --- |
| MoonBit gateway/client 开发者 | 构造或接收 8=FIX.4.4 TagValue 字节；解析 framing、字段、header/trailer 与 repeating groups；按其对端字典检查字段类型、必选项、enum 与 group 顺序 | 可嵌入 API 的结构化消息、可定位错误、确定性重编码 |
| Broker/exchange 集成和 QA 工程师 | 提交一串 Logon、Heartbeat、TestRequest、ResendRequest、SequenceReset、Reject 事件 | 无网络对端的会话状态转移、序号/重发决策和可断言 transcript |
| 运营/开发工具作者 | 提供本地 FIX capture/行记录与配置字典，运行审计命令 | 消息切分、校验、序号缺口/重复诊断和稳定 JSONL 报告 |

三种工作流共用 parser、validator 和 session engine；CLI、示例和 MoonCakes 库消费走公开接口，不依赖单站点服务或私有字典。

## 最小完整核心与边界

包含：FIX 4.4 基础 framing（BodyLength、CheckSum、SOH 分隔与边界）、field/message model、重复字段保序、可由调用方构造的版本/消息/字段描述、字段和 repeating group 验证、主要会话管理消息的纯函数状态机、序号/缺口/重发审计、capture CLI 和稳定 JSONL 报告。

不包含：socket/TLS/认证、连接真实交易场所、完整 FIXT 或 FIX 5.x、多版本自动协商、Orchestra 全功能编译器、交易执行/风控、供应商字典、官方规范文本、生成或再发布第三方 dictionary XML。任何未覆盖字段类型、消息类型或会话动作都必须明确报告 unsupported，不能静默声称完整 FIX 4.4 兼容。

## 成熟基线与权利边界

- FIX Trading Community 是协议及 Orchestra 的上游组织；FIX 4.4 资料和机器可读 Orchestra 资源用于确认协议概念与版本边界。上游入口：[Standards](https://www.fixtrading.org/standards/)、[FIX Orchestra](https://github.com/FIXTradingCommunity/fix-orchestra)。
- QuickFIX 是跨语言成熟参考引擎，用来选择独立行为对照场景：[QuickFIX](https://github.com/quickfix/quickfix)。本项目不复制其源代码、XML 字典、测试向量或 fixtures；只自行构造小型合成消息并比较公开可观察的协议行为。
- Orchestra 生态已有编辑/转换工具，因此本项目不以“缺少 FIX 编辑器”作为需求主张，也不重新分发 Orchestra schema 或官方字典。
- FIX Trading Community 规范/数据的具体再分发许可未作为开源许可证假定。本实现独立编写；公开物料只引用链接和必要术语。若后续需导入上游资料，须重新审查逐文件许可和归属。

## MoonBit 生态比较矩阵

| 候选/近邻 | 检查证据 | 结论 |
| --- | --- | --- |
| FIX 4.4 TagValue 交易会话 | Moon 搜索 FIX、FIX44、FIX 4.4、FIXT、TagValue FIX、FIX message codec、FIX session layer、Orchestra、Financial Information Exchange 与 IPFIX；GitHub API 查询 `FIX protocol MoonBit` 返回 0 个仓库；永久注册表能力扫描命中 MoonIPFIX 与 MoonISO8583，均非 FIX TagValue。新增源码级核验发现 `liyun6666/moonsbe@0.2.1`，见下文 | 仍可作为候选，但需明确同属 FIX 协议的相邻实现边界；检索受索引/结果上限限制，不作全网唯一性声明 |
| IPFIX flow telemetry | MoonCakes 命中 oyjh0381/moonipfix@0.1.0；实际检查 decoder/framing.mbt、stateful.mbt、stream.mbt、frame/lifecycle tests 与 README。实现 RFC 7011 IPFIX 16 字节消息头、Set/Template/Data Record、Observation Domain 和 exporter sequence，不是 FIX 交易 TagValue 或 session protocol。其 Apache-2.0 许可不构成将代码纳入本项目的理由 | 语义邻近词但不同协议、输入与状态模型；不复制、不依赖、不重新命名它 |
| SBE binary codecs/code generator for FIX SBE | `liyun6666/moonsbe@0.2.1`, Apache-2.0, [MoonCakes](https://mooncakes.io/docs/liyun6666/moonsbe), [source](https://github.com/liyun6666/moonsbe). MoonCakes metadata: latest 0.2.1, build success, repository updated 2026-11-11. README and public source tree inspected; actual core files include `schema.mbt`, `xml.mbt`, `encode.mbt`, `decode.mbt`, `generate.mbt`, and compatibility docs. It parses SBE XML schema and generates typed codecs for the binary FIX SBE encoding; project README describes FIX SBE 1.0. This is highly adjacent because it targets a FIX-family standard, but its wire encoding, input model, output and user workflow differ: schema-to-code/binary SBE interoperability versus FIX 4.4 TagValue messages, caller-owned field dictionaries, session sequence/recovery and text capture audit. Extending moonsbe cannot supply TagValue or classic FIX session semantics without changing its central contracts. MoonFIX will not parse SBE XML, implement SBE binary encoding, or copy/use moonsbe code or fixtures. |
| SCIM | 永久注册表记录 MoonSCIM/moonscim@0.1.2 对 SCIM 核心资源、PATCH/filter 协议实现的覆盖 | 不选。直接协议实现已有，虽与 FIX 不同域 |
| ISO 20022 | MoonCakes 检索发现 cstoooo/moonpay_flow 与 cstoooo/mooniso_lite | 不选。已有金融消息标准工具，避免转向重叠候选 |
| BPMN | MoonCakes 曾命中候选，但对应源码仓库不可见，无法进行要求的源/测试级语义核验 | 不选。无法满足严格核验，不把不可验证项目算作“没有重复” |

候选之间的比较依据是不同真实工作任务与核心数据/状态语义，而不是名称。查重不把“协议 parser”作为单一宽泛标签，因此通用 framing、IPFIX、ISO 8583、ISO 20022 和账务工具不会自动视为相同项目；反过来，新发现的 FIX 交易编解码或 session 代码需重新评估并记录。

## 候选比较与评分

三个不同问题域按 1–5 分记录（生态广度、用户多样性、复用、低重合、深度、验证、工期可行性、维护性；低重合项 5 表示风险低）：

| 候选 | 需求/成熟基线 | 查重门禁 | 评分（广/用户/复用/低重合/深度/验证/工期/维护） | 结论 |
| --- | --- | --- | --- | --- |
| FIX 4.4 TagValue + session audit | FIX Trading Community 标准、QuickFIX 行为基线；消息引擎与捕获审计是既有交易系统常见工作流；未声称用户访谈需求 | 对 moonsbe 属高度相邻，但 encoding/输入输出/状态语义清楚分离；其余候选不同域 | 4/4/4/3/5/5/3/4 | 通过有界范围，选中；发布前反向复查 |
| ISO 20022 支付消息校验与对账 | ISO 20022 标准及现有解析/业务校验工作流 | 注册表和 MoonCakes 已有 `cstoooo/moonpay_flow`、`cstoooo/mooniso_lite`，直接/高度相邻 | 4/4/4/1/4/5/2/3 | 淘汰：成熟近邻已覆盖支付报文验证/对账 |
| SCIM 身份资源协议工具 | SCIM 标准及身份目录集成 | 注册表已有 `MoonSCIM/moonscim@0.1.2` 覆盖核心资源、PATCH/filter | 3/3/4/1/4/5/4/4 | 淘汰：直接重合，宜扩展现有项目 |

需求依据区分：FIX 及其维护的参考引擎证明协议与跨生态工具的存在，不证明 MoonBit 用户访谈需求。三个用户群及具体工作流是基于 gateway 开发、集成 QA 与离线运营审计任务的可检验推断。最小完整核心和客观完成条件见上文与下节；如果端到端审计/独立语义向量无法完成，则不能仅靠代码规模保留选题。

## 交付前反向复核（2026-11-25）

- Moon search：FIX 4.4、FIX TagValue、FIX session、Financial Information Exchange。结果包含模糊命中、金融计算包及相邻 oyjh0381/moonipfix@0.1.0（IPFIX telemetry）；未见精确 FIX TagValue/session 实现。搜索索引和模糊匹配存在限制。
- GitHub authenticated repository search：FIX protocol MoonBit 和 FIX 4.4 MoonBit 均返回空结果；已确认精确目标仓库 228sydddd/moonfix 当前不存在。
- 高度相邻项仍为 liyun6666/moonsbe@0.2.1：FIX SBE XML schema 编译、typed codec 生成和二进制 SBE 消息；不处理 classic FIX 4.4 SOH TagValue 的调用方字典验证、会话状态或文本 capture。IPFIX 使用 RFC 7011 template/data record 与 exporter 序号语义，不是交易 FIX。
- 记录范围不构成全网唯一性证明；若发现经典 FIX TagValue 或 session 实现，须比较实际源码、接口、测试和维护状态并重新决定。

## 验收证据

发布门禁至少包括 framing 长度/checksum/终止分隔符边界，未知/重复/格式错误字段，必选字段和 enum，repeating group count/order，会话 Logon、heartbeat、序号缺口、ResendRequest 范围和 SequenceReset-GapFill，真实 capture 到 JSONL 输出，以及自行构造并逐字段解释的 FIX 4.4 语义向量。当前未声称已完成 QuickFIX 差分运行；若未实际运行独立参考引擎，只能称协议边界测试，不能称差分兼容。跨目标测试和干净消费者测试分别验证实现与发布包。代码行数/测试数不是本门禁的替代证据。
