///|
/// Command line entry point for auditing one local FIX capture.
#cfg(target="js")
fn main {
  let args = command_line_arguments()
  if args.length() != 1 {
    eprintln("usage: moon run cmd/main --target js -- <capture.fix>")
    exit_process(2)
  } else {
    let path = args[0]
    let wire = if path == "-" {
      read_capture_stdin()
    } else {
      read_capture(path)
    }
    let audit = @moonfix.audit_capture(wire)
    print_stdout(@moonfix.capture_audit_jsonl(audit))
    if audit.findings.length() > 0 {
      exit_process(1)
    }
  }
}

///|
#cfg(target="js")
extern "js" fn command_line_arguments() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
#cfg(target="js")
extern "js" fn read_capture(path : String) -> String =
  #| (path) => { const fs = require("node:fs"); const size = fs.statSync(path).size; if (size > 67108864) throw new Error("capture file exceeds 64 MiB limit"); return fs.readFileSync(path, "utf8"); }

///|
#cfg(target="js")
extern "js" fn read_capture_stdin() -> String =
  #| () => { const fs = require("node:fs"); const data = fs.readFileSync(0); if (data.length > 67108864) throw new Error("capture input exceeds 64 MiB limit"); return data.toString("utf8"); }

///|
#cfg(target="js")
extern "js" fn print_stdout(text : String) -> Unit =
  #| (text) => process.stdout.write(text)

///|
#cfg(target="js")
extern "js" fn eprintln(text : String) -> Unit =
  #| (text) => process.stderr.write(text + "\n")

///|
#cfg(target="js")
extern "js" fn exit_process(code : Int) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
#cfg(not(target="js"))
fn main {
  ignore(@moonfix.default_parse_limits())
  println("MoonFIX capture file CLI requires the JavaScript target and Node.js")
}
