///|
/// Portable file kinds exposed by the enhanced file-system API.
pub(all) enum FileKind {
  Unknown
  Regular
  Directory
  SymbolicLink
  Socket
  Pipe
  BlockDevice
  CharacterDevice
} derive(Eq, Debug)

///|
/// Metadata returned for a path or an open file.
///
/// Times are nanoseconds since the WASI clock epoch.
pub(all) struct Metadata {
  kind : FileKind
  size : UInt64
  accessed_ns : UInt64
  modified_ns : UInt64
  changed_ns : UInt64
  links : UInt64
} derive(Eq, Debug)

///|
/// Origin used by a seek operation.
pub(all) enum SeekFrom {
  Start
  Current
  End
} derive(Eq, Debug)

///|
/// Durability requested for writes.
pub(all) enum SyncMode {
  None
  Data
  Full
} derive(Eq, Debug)

///|
/// Validated options for opening a file.
pub struct OpenOptions {
  read : Bool
  write : Bool
  append : Bool
  create : Bool
  create_new : Bool
  truncate : Bool
  sync : SyncMode
} derive(Eq, Debug)

///|
/// Start building read-only open options.
pub fn OpenOptions::read_only() -> OpenOptions {
  {
    read: true,
    write: false,
    append: false,
    create: false,
    create_new: false,
    truncate: false,
    sync: None,
  }
}

///|
/// Start building write-only open options.
pub fn OpenOptions::write_only() -> OpenOptions {
  {
    read: false,
    write: true,
    append: false,
    create: false,
    create_new: false,
    truncate: false,
    sync: None,
  }
}

///|
/// Start building read-write open options.
pub fn OpenOptions::read_write() -> OpenOptions {
  { ..OpenOptions::read_only(), write: true }
}

///|
/// Enable or disable append mode.
pub fn OpenOptions::append(
  self : OpenOptions,
  enabled? : Bool = true,
) -> OpenOptions {
  { ..self, append: enabled }
}

///|
/// Create the file when it is missing.
pub fn OpenOptions::create(
  self : OpenOptions,
  enabled? : Bool = true,
) -> OpenOptions {
  { ..self, create: enabled }
}

///|
/// Require creation of a new file.
pub fn OpenOptions::create_new(
  self : OpenOptions,
  enabled? : Bool = true,
) -> OpenOptions {
  { ..self, create_new: enabled, create: enabled }
}

///|
/// Truncate an existing file when opening it.
pub fn OpenOptions::truncate(
  self : OpenOptions,
  enabled? : Bool = true,
) -> OpenOptions {
  { ..self, truncate: enabled }
}

///|
/// Select write durability.
pub fn OpenOptions::sync(self : OpenOptions, mode : SyncMode) -> OpenOptions {
  { ..self, sync: mode }
}

///|
fn OpenOptions::validate(self : OpenOptions) -> Unit raise @root.WasiError {
  guard self.read || self.write else {
    raise @root.InvalidInput(
      @root.Operation::Open,
      "read or write access is required",
    )
  }
  guard !self.append || self.write else {
    raise @root.InvalidInput(
      @root.Operation::Open,
      "append requires write access",
    )
  }
  guard !self.truncate || self.write else {
    raise @root.InvalidInput(
      @root.Operation::Open,
      "truncate requires write access",
    )
  }
  guard !self.create || self.write else {
    raise @root.InvalidInput(
      @root.Operation::Open,
      "create requires write access",
    )
  }
}

///|
fn file_kind(kind : @wasi.FileType) -> FileKind {
  match kind {
    @wasi.FileType::Unknown => Unknown
    @wasi.FileType::Regular_file => Regular
    @wasi.FileType::Directory => Directory
    @wasi.FileType::Symbolic_link => SymbolicLink
    @wasi.FileType::Socket_dgram | @wasi.FileType::Socket_stream => Socket
    @wasi.FileType::Block_device => BlockDevice
    @wasi.FileType::Character_device => CharacterDevice
  }
}

///|
fn metadata_from_wasi(stat : @wasi.FileStat) -> Metadata {
  {
    kind: file_kind(stat.filetype),
    size: stat.size.0,
    accessed_ns: stat.atim.0,
    modified_ns: stat.mtim.0,
    changed_ns: stat.ctim.0,
    links: stat.nlink.0,
  }
}

///|
fn resolve(
  operation : @root.Operation,
  path : @path.GuestPath,
) -> (@wasi.Fd, String) raise @root.WasiError {
  @base_fs.resolve_path(path.as_string()) catch {
    errno => raise @root.wasi_error(operation, errno, path=path.as_string())
  }
}
