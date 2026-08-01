///|
fn check(condition : Bool, message : String) -> Unit {
  guard condition else { abort(message) }
}

///|
fn log(message : StringView) -> Unit {
  @wasi_sys.eprint("\{message}\n") catch {
    _ => ()
  }
}

///|
fn run_process() -> Unit raise {
  let arguments = @wasi_sys.arguments()
  check(!arguments.is_empty(), "host returned no program argument")
  check(
    @wasi_sys.environment_variable("MOON_WASI_TEST") == Some("ready"),
    "environment lookup failed",
  )
  let preopens = @wasi_sys.preopens()
  check(!preopens.is_empty(), "host returned no preopened directories")
  check(preopens[0].fd >= 3, "invalid preopen descriptor")
}

///|
fn run_clock() -> Unit raise {
  check(
    @wasi_sys.clock_resolution(@wasi_sys.Clock::Monotonic) > 0UL,
    "invalid clock resolution",
  )
  let before = @wasi_sys.clock_time(@wasi_sys.Clock::Monotonic)
  @wasi_sys.sleep(2_000_000UL)
  let after = @wasi_sys.clock_time(@wasi_sys.Clock::Monotonic)
  check(after > before, "monotonic clock did not advance")
}

///|
fn run_random() -> Unit raise {
  let bytes = @wasi_sys.random_bytes(32)
  check(bytes.length() == 32, "random byte length differs")
  let mut any_nonzero = false
  for byte in bytes {
    if byte != b'\x00' {
      any_nonzero = true
    }
  }
  check(any_nonzero, "random buffer unexpectedly contained only zeroes")
  for _ in 0..<64 {
    check(@wasi_sys.random_below(17UL) < 17UL, "random_below escaped its range")
  }
  let mut rejected = false
  ignore(@wasi_sys.random_bytes(-1)) catch {
    @root.InvalidInput(@root.Operation::Random, _) => rejected = true
    _ => ()
  }
  check(rejected, "negative random length was accepted")
}

///|
fn run_poll() -> Unit raise {
  let result = @wasi_sys.wait_descriptor(
    1,
    @wasi_sys.Interest::Writable,
    timeout_ns=1_000_000_000UL,
  )
  check(result is @wasi_sys.Ready(_, _), "stdout did not become writable")
}

///|
fn main {
  try {
    log("running process capabilities")
    run_process()
    log("running clocks")
    run_clock()
    log("running secure random")
    run_random()
    log("running descriptor polling")
    run_poll()
    @wasi_sys.print("system integration passed\n")
  } catch {
    error => {
      log("system integration failed: \{@debug.to_string(error)}")
      abort("WASI system integration test failed")
    }
  }
}
