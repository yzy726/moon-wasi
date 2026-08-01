///|
fn run() -> Unit raise {
  let arguments = @wasi_sys.arguments()
  let environment = @wasi_sys.environment()
  let preopens = @wasi_sys.preopens()
  let monotonic = @wasi_sys.clock_time(@wasi_sys.Clock::Monotonic)
  let random = @wasi_sys.random_bytes(8)
  @wasi_sys.print("MoonBit WASI diagnostics\n")
  @wasi_sys.print("arguments: \{@debug.to_string(arguments)}\n")
  @wasi_sys.print("environment entries: \{environment.length()}\n")
  @wasi_sys.print("preopens: \{@debug.to_string(preopens)}\n")
  @wasi_sys.print("monotonic nanoseconds: \{monotonic}\n")
  @wasi_sys.print("random sample: \{@debug.to_string(random)}\n")
}

///|
fn main {
  run() catch {
    error => {
      @wasi_sys.eprint("diagnostics failed: \{@debug.to_string(error)}\n") catch {
        _ => ()
      }
      @wasi_sys.exit(1)
    }
  }
}
