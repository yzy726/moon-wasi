///|
/// An owned WASI file descriptor.
///
/// Call `close` exactly once, or use high-level helpers which close descriptors
/// automatically.
pub struct File {
  fd : @wasi.Fd
  path : String
}

///|
fn rights_for(options : OpenOptions) -> @wasi.Rights {
  let mut rights = @wasi.Rights::new()
    |> @wasi.Rights::set(@wasi.Right::Fd_filestat_get)
    |> @wasi.Rights::set(@wasi.Right::Fd_seek)
    |> @wasi.Rights::set(@wasi.Right::Fd_tell)
  if options.read {
    rights = rights |> @wasi.Rights::set(@wasi.Right::Fd_read)
  }
  if options.write {
    rights = rights
      |> @wasi.Rights::set(@wasi.Right::Fd_write)
      |> @wasi.Rights::set(@wasi.Right::Fd_sync)
      |> @wasi.Rights::set(@wasi.Right::Fd_datasync)
      |> @wasi.Rights::set(@wasi.Right::Fd_filestat_set_size)
  }
  rights
}

///|
fn open_flags(options : OpenOptions) -> @wasi.OpenFlags {
  let mut flags = @wasi.OpenFlags::new()
  if options.create {
    flags = flags |> @wasi.OpenFlags::set(@wasi.OpenFlag::Create)
  }
  if options.create_new {
    flags = flags |> @wasi.OpenFlags::set(@wasi.OpenFlag::Excl)
  }
  if options.truncate {
    flags = flags |> @wasi.OpenFlags::set(@wasi.OpenFlag::Trunc)
  }
  flags
}

///|
fn descriptor_flags(options : OpenOptions) -> @wasi.FdFlags {
  let mut flags = @wasi.FdFlags::new()
  if options.append {
    flags = flags |> @wasi.FdFlags::set(@wasi.FdFlag::Append)
  }
  flags
}

///|
/// Open a validated guest path.
pub fn open(
  path : @path.GuestPath,
  options : OpenOptions,
) -> File raise @root.WasiError {
  options.validate()
  let (base, relative) = resolve(@root.Operation::Open, path)
  let rights = rights_for(options)
  let fd = base.path_open(
    @wasi.LookupFlags::new(),
    relative,
    open_flags(options),
    rights,
    @wasi.Rights::new(),
    descriptor_flags(options),
  ) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Open,
        errno,
        path=path.as_string(),
      )
  }
  { fd, path: path.as_string() }
}

///|
/// Close this file descriptor.
pub fn File::close(self : File) -> Unit raise @root.WasiError {
  self.fd.fd_close() catch {
    errno =>
      raise @root.wasi_error(@root.Operation::Close, errno, path=self.path)
  }
}

///|
/// Return the WASI descriptor number for polling and host integration.
pub fn File::raw_fd(self : File) -> Int {
  self.fd.0
}

///|
fn File::close_silently(self : File) -> Unit {
  self.fd.fd_close() catch {
    _ => ()
  }
}

///|
/// Read until EOF from the current cursor.
pub fn File::read_all(self : File) -> Bytes raise @root.WasiError {
  let output : Array[Byte] = []
  let chunk_size = 8192
  while true {
    let chunk = FixedArray::make(chunk_size, b'\x00')
    let count = self.fd.fd_read([chunk]) catch {
      errno =>
        raise @root.wasi_error(@root.Operation::Read, errno, path=self.path)
    }
    let count = count.0.reinterpret_as_int()
    for index in 0..<count {
      output.push(chunk[index])
    }
    if count == 0 {
      break
    }
  }
  Bytes::from_array(output)
}

///|
/// Write every byte, handling partial host writes.
pub fn File::write_all(
  self : File,
  data : BytesView,
) -> Unit raise @root.WasiError {
  let mut offset = 0
  while offset < data.length() {
    let count = self.fd.fd_write([data[offset:]]) catch {
      errno =>
        raise @root.wasi_error(@root.Operation::Write, errno, path=self.path)
    }
    let count = count.0.reinterpret_as_int()
    guard count > 0 else {
      raise @root.InvalidInput(
        @root.Operation::Write,
        "host reported a zero-byte write",
      )
    }
    offset = offset + count
  }
}

///|
/// Seek and return the new byte offset.
pub fn File::seek(
  self : File,
  offset : Int64,
  from : SeekFrom,
) -> UInt64 raise @root.WasiError {
  let whence = match from {
    Start => @wasi.Whence::Set
    Current => @wasi.Whence::Cur
    End => @wasi.Whence::End
  }
  let result = self.fd.fd_seek(@wasi.FileDelta(offset), whence) catch {
    errno =>
      raise @root.wasi_error(@root.Operation::Seek, errno, path=self.path)
  }
  result.0
}

///|
/// Return the current cursor position.
pub fn File::tell(self : File) -> UInt64 raise @root.WasiError {
  let result = self.fd.fd_tell() catch {
    errno =>
      raise @root.wasi_error(@root.Operation::Seek, errno, path=self.path)
  }
  result.0
}

///|
/// Flush buffered data and metadata to storage.
pub fn File::sync(
  self : File,
  data_only? : Bool = false,
) -> Unit raise @root.WasiError {
  if data_only {
    self.fd.fd_datasync() catch {
      errno =>
        raise @root.wasi_error(@root.Operation::Sync, errno, path=self.path)
    }
  } else {
    self.fd.fd_sync() catch {
      errno =>
        raise @root.wasi_error(@root.Operation::Sync, errno, path=self.path)
    }
  }
}

///|
/// Return metadata for this open descriptor.
pub fn File::metadata(self : File) -> Metadata raise @root.WasiError {
  let stat = self.fd.fd_filestat_get() catch {
    errno =>
      raise @root.wasi_error(@root.Operation::Metadata, errno, path=self.path)
  }
  metadata_from_wasi(stat)
}
