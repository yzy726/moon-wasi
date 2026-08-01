///|
/// One environment variable, split only at its first `=` by the ABI layer.
pub(all) struct EnvVar {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// One directory capability provided by the WASI host.
pub(all) struct Preopen {
  guest_path : String
  fd : Int
} derive(Eq, Debug)

///|
/// Return the process arguments supplied by the host.
pub fn arguments() -> Array[String] raise @root.WasiError {
  @wasi.args_get() catch {
    errno => raise @root.wasi_error(@root.Operation::Arguments, errno)
  }
}

///|
/// Return all environment variables supplied by the host.
pub fn environment() -> Array[EnvVar] raise @root.WasiError {
  let values = @wasi.environ_get() catch {
    errno => raise @root.wasi_error(@root.Operation::Environment, errno)
  }
  values.map(pair => { name: pair.0, value: pair.1 })
}

///|
/// Find an environment variable by exact, case-sensitive name.
pub fn environment_variable(name : StringView) -> String? raise @root.WasiError {
  let name = name.to_owned()
  for variable in environment() {
    if variable.name == name {
      return Some(variable.value)
    }
  }
  None
}

///|
/// Enumerate directory capabilities preopened by the host.
pub fn preopens() -> Array[Preopen] raise @root.WasiError {
  let result : Array[Preopen] = []
  let mut descriptor = 3
  while true {
    let fd = @wasi.Fd(descriptor)
    let present = try {
      ignore(fd.fd_prestat_get())
      true
    } catch {
      @wasi.Badf => false
      errno =>
        raise @root.wasi_error(
          @root.Operation::Environment,
          errno,
          path="fd:\{descriptor}",
        )
    }
    if !present {
      break
    }
    let guest_path = fd.fd_prestat_dir_name() catch {
      errno =>
        raise @root.wasi_error(
          @root.Operation::Environment,
          errno,
          path="fd:\{descriptor}",
        )
    }
    result.push({ guest_path, fd: descriptor })
    descriptor = descriptor + 1
  }
  result
}

///|
/// Exit the WASI process immediately.
pub fn[A] exit(code : UInt) -> A {
  @wasi.proc_exit(code)
}
