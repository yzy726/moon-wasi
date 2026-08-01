///|
fn random_suffix() -> String raise @root.WasiError {
  let bytes = FixedArray::make(8, b'\x00')
  @wasi.random_get(bytes) catch {
    errno => raise @root.wasi_error(@root.Operation::AtomicWrite, errno)
  }
  let parts : Array[String] = []
  for byte in bytes {
    let encoded = byte.to_int().to_string(radix=16)
    parts.push(if encoded.length() == 1 { "0\{encoded}" } else { encoded })
  }
  parts.join("")
}

///|
fn temporary_sibling(
  path : @path.GuestPath,
) -> @path.GuestPath raise @root.WasiError {
  let parent = path.parent().unwrap_or(path)
  parent.join(".moon-wasi-\{random_suffix()}.tmp") catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::AtomicWrite,
        "failed to construct a temporary sibling path",
      )
  }
}

///|
fn create_temporary_file(
  path : @path.GuestPath,
) -> (@path.GuestPath, File) raise @root.WasiError {
  for _ in 0..<8 {
    let temporary = temporary_sibling(path)
    try open(temporary, OpenOptions::write_only().create_new()) catch {
      @root.WasiFailure(_, _, @wasi.Exist) => ()
      error => raise error
    } noraise {
      file => return (temporary, file)
    }
  }
  raise @root.InvalidInput(
    @root.Operation::AtomicWrite,
    "could not allocate a unique temporary file",
  )
}

///|
/// Atomically publish a file after fully writing and syncing a sibling.
///
/// Replacement uses WASI `path_rename` within the same preopened file system.
/// Creation with `replace=false` uses a hard link for atomic no-overwrite
/// semantics. Failures trigger best-effort temporary cleanup.
pub fn atomic_write(
  path : @path.GuestPath,
  data : BytesView,
  replace? : Bool = true,
) -> Unit raise @root.WasiError {
  guard !path.is_root() else {
    raise @root.InvalidInput(
      @root.Operation::AtomicWrite,
      "the capability root cannot be replaced by a file",
    )
  }
  let (temporary, file) = create_temporary_file(path)
  try {
    file.write_all(data)
    file.sync()
    file.close()
    if replace {
      rename(temporary, path)
    } else {
      hard_link(temporary, path) catch {
        @root.WasiFailure(_, _, @wasi.Exist) =>
          raise @root.InvalidInput(
            @root.Operation::AtomicWrite,
            "destination '\{path.as_string()}' already exists",
          )
        error => raise error
      }
      remove_file(temporary) catch {
        _ => ()
      }
    }
  } catch {
    error => {
      file.close_silently()
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
