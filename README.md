# MoonFIX

[简体中文](README.zh-CN.md)

MoonFIX is a MoonBit library and offline capture auditor for the classic FIX 4.4 TagValue protocol. It parses SOH-delimited frames, checks `BodyLength` and `CheckSum`, and exposes caller-owned dictionary validation, flat repeating-group parsing, deterministic session transitions, and JSON Lines capture reports.

## Workflows

- Gateway and client developers parse inbound frames into ordered fields and encode outbound messages with calculated framing fields.
- Integration QA engineers feed messages into the pure session reducer to inspect supported Logon, heartbeat, sequence-gap, resend, and GapFill behavior without a counterparty connection.
- Operations and tooling authors audit saved text captures and consume stable JSONL messages and findings in scripts. Findings produce exit status 1.

These workflows are derived from established FIX integration practices; they are not claims of user interviews or production-trading validation.

## Implemented scope

- Ordered TagValue parsing and encoding with ASCII, field-count, size, `BodyLength`, terminator, and checksum checks.
- Caller-supplied dictionary validation for message types, required/repeated tags, enumerations, value types, and Length/Data pairing.
- Flat repeating-group parsing with delimiter, order, and entry-limit checks.
- Pure state transitions for the implemented Logon/Logout, heartbeat/TestRequest, sequence-gap, ResendRequest, and SequenceReset branches. Logon requires `EncryptMethod=0`; `ResetSeqNumFlag=Y` resets both sequence directions. GapFill and Reset have distinct sequence handling.
- Capture resynchronization, CR/LF separators between messages, sequence gap/duplicate/out-of-order findings, and deterministic JSONL output.
- A Node.js file CLI: clean audit exits 0, findings exit 1, and usage errors exit 2.

## Boundaries

MoonFIX does not implement sockets/TLS, venue connectivity, order execution, FIXT or FIX 5.x, a complete Orchestra compiler, distributed dictionaries, nested repeating groups, full timers/session lifecycle, or binary SBE. The parser handles text fields and does not support SOH embedded in binary Length/Data payloads. The CLI reads one file up to 64 MiB. Callers supply business dictionaries; none are bundled. QuickFIX automated differential tests and full FIX 4.4 certification have not been run. Do not use this implementation in an unvalidated live trading path. See [protocol behavior](docs/protocol-behavior.md) for observable details.

## Install

```sh
moon add 228sydddd/moonfix@0.1.0
```

The library is checked on `wasm`, `wasm-gc`, and `js`. The file CLI requires Node.js and the MoonBit JavaScript target. The library has no external MoonBit runtime dependency.

## Library example

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

The caller constructs `Dictionary` and `MessageDefinition` values for its peer. The session reducer returns a new state and ordered actions; it does not perform network I/O:

```moonbit
let transition = match @moonfix.apply_inbound(state, decoded) {
  Ok(value) => value
  Err(error) => abort("session transition rejected: " + error.detail)
}
let next_state = transition.state
```

Active sessions can also produce sequence-managed protocol traffic:

```moonbit
let heartbeat = @moonfix.send_heartbeat(next_state, test_request_id=Some("probe-1"))
let resend = @moonfix.send_resend_request(next_state, 4, 0)
```

Exported signatures are in [`pkg.generated.mbti`](pkg.generated.mbti).

## Capture CLI

From the project root:

```sh
moon run cmd/main --target js -- examples/heartbeat.fix
cat examples/heartbeat.fix | moon run cmd/main --target js -- -
```

Each output line is a `message` or `finding` JSON object suitable for tools such as `jq`. Input is a text capture with SOH-delimited messages and optional CR/LF between messages, not a space-delimited dump. Node.js `node:fs` provides file access. Other targets can use the library API but are not supported by this file CLI.

## Verify

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

Tests cover framing boundaries, checksum failures, dictionary errors, repeating groups, session transitions, capture resynchronization, and sequence auditing. The examples are project-authored vectors; no third-party fixtures are included.

## References and license

FIX Trading Community FIX 4.4 materials inform TagValue, field, and session behavior. QuickFIX is a behavioral reference concept, not a code dependency. This repository does not redistribute the standard text, third-party dictionaries, upstream source, or upstream fixtures.

MoonSBE is adjacent but targets FIX SBE XML schemas and binary codecs/code generation. MoonFIX targets classic FIX 4.4 TagValue, caller-owned dictionaries, session processing, and text captures. MoonFIX does not implement SBE and does not use or copy MoonSBE source or fixtures. See the [bounded duplication review](docs/competition/duplicate-check.md).

Apache-2.0; see [LICENSE](LICENSE). AI tools assisted with implementation, tests, and documentation. Contributors should review protocol behavior, edge cases, and reference compliance.
