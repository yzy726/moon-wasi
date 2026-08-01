///|
/// A named directory entry with its normalized guest path and kind.
pub(all) struct DirEntry {
  name : String
  path : @path.GuestPath
  kind : FileKind
} derive(Eq, Debug)

///|
/// Return metadata for a path.
pub fn metadata(
  path : @path.GuestPath,
  follow_symlink? : Bool = true,
) -> Metadata raise @root.WasiError {
  let (base, relative) = resolve(@root.Operation::Metadata, path)
  let flags = if follow_symlink {
    @wasi.LookupFlags::new()
    |> @wasi.LookupFlags::set(@wasi.LookupFlag::Symlink_follow)
  } else {
    @wasi.LookupFlags::new()
  }
  let stat = base.path_filestat_get(flags, relative) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Metadata,
        errno,
        path=path.as_string(),
      )
  }
  metadata_from_wasi(stat)
}

///|
/// Check for a path while preserving host failures other than `Noent`.
pub fn try_exists(path : @path.GuestPath) -> Bool raise @root.WasiError {
  try {
    ignore(metadata(path))
    true
  } catch {
    @root.WasiFailure(_, _, @wasi.Noent) => false
    error => raise error
  }
}

///|
/// Best-effort existence check.
///
/// This convenience function returns `false` for inaccessible paths as well as
/// missing paths. Use `try_exists` when the distinction matters.
pub fn exists(path : @path.GuestPath) -> Bool {
  try_exists(path) catch {
    _ => false
  }
}

///|
/// Read an entire file as bytes.
pub fn read_bytes(path : @path.GuestPath) -> Bytes raise @root.WasiError {
  let file = open(path, OpenOptions::read_only())
  defer file.close_silently()
  file.read_all()
}

///|
/// Read and validate a UTF-8 text file.
pub fn read_text(path : @path.GuestPath) -> String raise @root.WasiError {
  let data = read_bytes(path)
  @utf8.decode(data) catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::Read,
        "'\{path.as_string()}' is not valid UTF-8",
      )
  }
}

///|
/// Write a complete byte sequence, creating and truncating the destination.
pub fn write_bytes(
  path : @path.GuestPath,
  data : BytesView,
  sync? : SyncMode = None,
) -> Unit raise @root.WasiError {
  let options = OpenOptions::write_only().create().truncate()
  let file = open(path, options)
  defer file.close_silently()
  file.write_all(data)
  if sync != None {
    file.sync(data_only=sync == Data)
  }
}

///|
/// Encode and write UTF-8 text.
pub fn write_text(
  path : @path.GuestPath,
  text : StringView,
  sync? : SyncMode = None,
) -> Unit raise @root.WasiError {
  write_bytes(path, @utf8.encode(text), sync~)
}

///|
/// Append bytes to a file, creating it when necessary.
pub fn append_bytes(
  path : @path.GuestPath,
  data : BytesView,
  sync? : SyncMode = None,
) -> Unit raise @root.WasiError {
  let options = OpenOptions::write_only().create().append()
  let file = open(path, options)
  defer file.close_silently()
  file.write_all(data)
  if sync != None {
    file.sync(data_only=sync == Data)
  }
}

///|
/// Create one directory.
pub fn create_dir(path : @path.GuestPath) -> Unit raise @root.WasiError {
  guard !path.is_root() else {
    raise @root.InvalidInput(
      @root.Operation::CreateDirectory,
      "the preopen root already exists",
    )
  }
  let (base, relative) = resolve(@root.Operation::CreateDirectory, path)
  base.path_create_directory(relative) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::CreateDirectory,
        errno,
        path=path.as_string(),
      )
  }
}

///|
/// Create every missing directory component.
pub fn create_dir_all(path : @path.GuestPath) -> Unit raise @root.WasiError {
  if path.is_root() {
    return
  }
  let mut current = @path.GuestPath::new(".") catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::CreateDirectory,
        "failed to construct the capability root",
      )
  }
  for segment in path.segments() {
    current = current.join(segment) catch {
      _ =>
        raise @root.InvalidInput(
          @root.Operation::CreateDirectory,
          "invalid normalized directory component",
        )
    }
    create_dir(current) catch {
      @root.WasiFailure(_, _, @wasi.Exist) =>
        if metadata(current, follow_symlink=false).kind != Directory {
          raise @root.InvalidInput(
            @root.Operation::CreateDirectory,
            "'\{current.as_string()}' exists and is not a directory",
          )
        }
      error => raise error
    }
  }
}

///|
/// List one directory in deterministic name order.
pub fn read_dir(
  path : @path.GuestPath,
) -> Array[DirEntry] raise @root.WasiError {
  let (base, relative) = resolve(@root.Operation::ReadDirectory, path)
  let rights = @wasi.Rights::new() |> @wasi.Rights::set(@wasi.Right::Fd_readdir)
  let directory = base.path_open(
    @wasi.LookupFlags::new(),
    relative,
    @wasi.OpenFlags::new() |> @wasi.OpenFlags::set(@wasi.OpenFlag::Directory),
    rights,
    @wasi.Rights::new(),
    @wasi.FdFlags::new(),
  ) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::ReadDirectory,
        errno,
        path=path.as_string(),
      )
  }
  defer (directory.fd_close() catch { _ => () })
  let entries : Array[DirEntry] = []
  let mut cookie = @wasi.DirCookie(0UL)
  while true {
    let (batch, has_more) = directory.fd_readdir(cookie~) catch {
      errno =>
        raise @root.wasi_error(
          @root.Operation::ReadDirectory,
          errno,
          path=path.as_string(),
        )
    }
    for item in batch {
      let (name, dir_entry) = item
      cookie = dir_entry.d_next
      if name == "." || name == ".." {
        continue
      }
      let child = path.join(name) catch {
        _ =>
          raise @root.InvalidInput(
            @root.Operation::ReadDirectory,
            "host returned an invalid directory entry",
          )
      }
      entries.push({
        name,
        path: child,
        kind: metadata(child, follow_symlink=false).kind,
      })
    }
    if !has_more {
      break
    }
    guard !batch.is_empty() else {
      raise @root.InvalidInput(
        @root.Operation::ReadDirectory,
        "directory entry exceeds the host read buffer",
      )
    }
  }
  entries.sort_by((left, right) => left.name.lexical_compare(right.name))
  entries
}

///|
/// Remove a non-directory path.
pub fn remove_file(path : @path.GuestPath) -> Unit raise @root.WasiError {
  let (base, relative) = resolve(@root.Operation::Remove, path)
  base.path_unlink_file(relative) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Remove,
        errno,
        path=path.as_string(),
      )
  }
}

///|
/// Remove an empty directory.
pub fn remove_dir(path : @path.GuestPath) -> Unit raise @root.WasiError {
  guard !path.is_root() else {
    raise @root.InvalidInput(
      @root.Operation::Remove,
      "cannot remove a preopen root",
    )
  }
  let (base, relative) = resolve(@root.Operation::Remove, path)
  base.path_remove_directory(relative) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Remove,
        errno,
        path=path.as_string(),
      )
  }
}

///|
/// Remove a file, link, or directory tree without following symbolic links.
pub fn remove_tree(path : @path.GuestPath) -> Unit raise @root.WasiError {
  guard !path.is_root() else {
    raise @root.InvalidInput(
      @root.Operation::Remove,
      "cannot remove a preopen root",
    )
  }
  if metadata(path, follow_symlink=false).kind == Directory {
    for entry in read_dir(path) {
      remove_tree(entry.path)
    }
    remove_dir(path)
  } else {
    remove_file(path)
  }
}

///|
/// Rename or move a path, including across preopened directories when allowed.
pub fn rename(
  source : @path.GuestPath,
  destination : @path.GuestPath,
) -> Unit raise @root.WasiError {
  let (source_base, source_relative) = resolve(@root.Operation::Rename, source)
  let (destination_base, destination_relative) = resolve(
    @root.Operation::Rename,
    destination,
  )
  source_base.path_rename(
    source_relative, destination_base, destination_relative,
  ) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Rename,
        errno,
        path="\{source.as_string()} -> \{destination.as_string()}",
      )
  }
}

///|
/// Create a hard link.
pub fn hard_link(
  source : @path.GuestPath,
  destination : @path.GuestPath,
) -> Unit raise @root.WasiError {
  let (source_base, source_relative) = resolve(@root.Operation::Link, source)
  let (destination_base, destination_relative) = resolve(
    @root.Operation::Link,
    destination,
  )
  source_base.path_link(
    @wasi.LookupFlags::new(),
    source_relative,
    destination_base,
    destination_relative,
  ) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Link,
        errno,
        path="\{source.as_string()} -> \{destination.as_string()}",
      )
  }
}

///|
/// Create a relative symbolic link.
///
/// The target is interpreted from the link's parent directory, matching WASI
/// and POSIX semantics. Targets which would lexically escape the capability
/// root are rejected before calling the host.
pub fn symbolic_link(
  target : StringView,
  link_path : @path.GuestPath,
) -> Unit raise @root.WasiError {
  let target = target.to_owned()
  guard !link_path.is_root() else {
    raise @root.InvalidInput(
      @root.Operation::Link,
      "the capability root cannot be replaced by a symbolic link",
    )
  }
  guard !target.is_empty() else {
    raise @root.InvalidInput(
      @root.Operation::Link,
      "symbolic-link target must not be empty",
    )
  }
  guard !target.has_prefix("/") else {
    raise @root.InvalidInput(
      @root.Operation::Link,
      "symbolic-link target must be relative",
    )
  }
  guard !target.contains("\\") && !target.contains("\u{0000}") else {
    raise @root.InvalidInput(
      @root.Operation::Link,
      "symbolic-link target is not a valid guest path",
    )
  }
  let parent = link_path.parent().unwrap_or(link_path)
  ignore(parent.join(target)) catch {
    _ =>
      raise @root.InvalidInput(
        @root.Operation::Link,
        "symbolic-link target escapes the capability root",
      )
  }
  let (base, relative) = resolve(@root.Operation::Link, link_path)
  @wasi.path_symlink(target, base, relative) catch {
    errno =>
      raise @root.wasi_error(
        @root.Operation::Link,
        errno,
        path=link_path.as_string(),
      )
  }
}

///|
/// Read a symbolic-link target as validated UTF-8.
pub fn read_link(path : @path.GuestPath) -> String raise @root.WasiError {
  let (base, relative) = resolve(@root.Operation::Link, path)
  let mut capacity = 256
  while capacity <= 1024 * 1024 {
    let buffer = FixedArray::make(capacity, b'\x00')
    let size = base.path_readlink(relative, buffer~) catch {
      errno =>
        raise @root.wasi_error(
          @root.Operation::Link,
          errno,
          path=path.as_string(),
        )
    }
    let size = size.0.reinterpret_as_int()
    if size < capacity {
      let bytes : Array[Byte] = []
      for index in 0..<size {
        bytes.push(buffer[index])
      }
      return @utf8.decode(Bytes::from_array(bytes)) catch {
        _ =>
          raise @root.InvalidInput(
            @root.Operation::Link,
            "symbolic-link target is not valid UTF-8",
          )
      }
    }
    capacity = capacity * 2
  }
  raise @root.InvalidInput(
    @root.Operation::Link,
    "symbolic-link target exceeds one MiB",
  )
}

///|
/// Copy a regular file using a bounded buffer.
pub fn copy_file(
  source : @path.GuestPath,
  destination : @path.GuestPath,
  overwrite? : Bool = false,
  sync? : SyncMode = None,
) -> UInt64 raise @root.WasiError {
  if source == destination {
    raise @root.InvalidInput(
      @root.Operation::Copy,
      "source and destination must be different paths",
    )
  }
  let input = open(source, OpenOptions::read_only())
  defer input.close_silently()
  let input_metadata = input.metadata()
  guard input_metadata.kind == Regular else {
    raise @root.InvalidInput(
      @root.Operation::Copy,
      "source '\{source.as_string()}' is not a regular file",
    )
  }
  let output_options = if overwrite {
    OpenOptions::write_only().create()
  } else {
    OpenOptions::write_only().create_new()
  }
  let output = open(destination, output_options)
  defer output.close_silently()
  if overwrite {
    let output_metadata = output.metadata()
    guard input_metadata.device != output_metadata.device ||
      input_metadata.inode != output_metadata.inode else {
      raise @root.InvalidInput(
        @root.Operation::Copy,
        "source and destination refer to the same file",
      )
    }
    output.fd.fd_filestat_set_size(@wasi.FileSize(0UL)) catch {
      errno =>
        raise @root.wasi_error(
          @root.Operation::Copy,
          errno,
          path=destination.as_string(),
        )
    }
  }
  let chunk_size = 64 * 1024
  let mut total = 0UL
  while true {
    let chunk = FixedArray::make(chunk_size, b'\x00')
    let count = input.fd.fd_read([chunk]) catch {
      errno =>
        raise @root.wasi_error(
          @root.Operation::Copy,
          errno,
          path=source.as_string(),
        )
    }
    let count = count.0.reinterpret_as_int()
    if count == 0 {
      break
    }
    let bytes : Array[Byte] = []
    for index in 0..<count {
      bytes.push(chunk[index])
    }
    output.write_all(Bytes::from_array(bytes))
    total = total + count.to_uint64()
  }
  if sync != None {
    output.sync(data_only=sync == Data)
  }
  total
}
