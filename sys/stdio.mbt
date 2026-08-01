///|
fn write_descriptor(
  fd : @wasi.Fd,
  data : BytesView,
  operation : @root.Operation,
) -> Unit raise @root.WasiError {
  let mut offset = 0
  while offset < data.length() {
    let size = fd.fd_write([data[offset:]]) catch {
      errno => raise @root.wasi_error(operation, errno)
    }
    let size = size.0.reinterpret_as_int()
    guard size > 0 else {
      raise @root.InvalidInput(operation, "host reported a zero-byte write")
    }
    offset = offset + size
  }
}

///|
/// Write bytes to standard output without relying on `spectest.print_char`.
pub fn write_stdout(data : BytesView) -> Unit raise @root.WasiError {
  write_descriptor(@wasi.stdout, data, @root.Operation::Write)
}

///|
/// Write bytes to standard error without relying on `spectest.print_char`.
pub fn write_stderr(data : BytesView) -> Unit raise @root.WasiError {
  write_descriptor(@wasi.stderr, data, @root.Operation::Write)
}

///|
/// Encode UTF-8 text and write it to standard output.
pub fn print(text : StringView) -> Unit raise @root.WasiError {
  write_stdout(@utf8.encode(text))
}

///|
/// Encode UTF-8 text and write it to standard error.
pub fn eprint(text : StringView) -> Unit raise @root.WasiError {
  write_stderr(@utf8.encode(text))
}

///|
/// Read standard input until EOF.
pub fn read_stdin() -> Bytes raise @root.WasiError {
  let output : Array[Byte] = []
  let chunk_size = 8192
  while true {
    let chunk = FixedArray::make(chunk_size, b'\x00')
    let size = @wasi.stdin.fd_read([chunk]) catch {
      errno => raise @root.wasi_error(@root.Operation::Read, errno)
    }
    let size = size.0.reinterpret_as_int()
    for index in 0..<size {
      output.push(chunk[index])
    }
    if size == 0 {
      break
    }
  }
  Bytes::from_array(output)
}

///|
/// Read standard input as validated UTF-8.
pub fn read_stdin_text() -> String raise @root.WasiError {
  @utf8.decode(read_stdin()) catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::Read,
        "stdin is not valid UTF-8",
      )
  }
}
