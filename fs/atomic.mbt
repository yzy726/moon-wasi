///|
fn random_suffix() -> String raise @root.WasiError {
  let bytes = FixedArray::make(8, b'\x00')
  @wasi.random_get(bytes) catch {
    errno => raise @root.wasi_error(@root.Operation::AtomicWrite, errno)
  }
  let parts : Array[String] = []
  for byte in bytes {
    parts.push(byte.to_int().to_string(radix=16))
  }
  parts.join("")
}

///|
fn temporary_sibling(
  path : @path.GuestPath,
) -> @path.GuestPath raise @root.WasiError {
  let parent = path.parent().unwrap_or(path)
  let name = path.file_name().unwrap_or("root")
  parent.join(".\{name}.moon-wasi-\{random_suffix()}.tmp") catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::AtomicWrite,
        "failed to construct a temporary sibling path",
      )
  }
}

///|
/// Atomically replace a file after fully writing and syncing a sibling.
///
/// Atomicity is provided by WASI `path_rename` within the same preopened file
/// system. A failed write or rename triggers best-effort temporary cleanup.
pub fn atomic_write(
  path : @path.GuestPath,
  data : BytesView,
  replace? : Bool = true,
) -> Unit raise @root.WasiError {
  if !replace && exists(path) {
    raise @root.InvalidInput(
      @root.Operation::AtomicWrite,
      "destination '\{path.as_string()}' already exists",
    )
  }
  let temporary = temporary_sibling(path)
  try {
    write_bytes(temporary, data, sync=Full)
    rename(temporary, path)
  } catch {
    error => {
      remove_file(temporary) catch {
        _ => ()
      }
      raise error
    }
  }
}

///|
/// UTF-8 variant of `atomic_write`.
pub fn atomic_write_text(
  path : @path.GuestPath,
  text : StringView,
  replace? : Bool = true,
) -> Unit raise @root.WasiError {
  atomic_write(path, @utf8.encode(text), replace~)
}
