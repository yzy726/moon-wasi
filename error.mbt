///|
/// A high-level operation that can fail at a WASI boundary.
pub(all) enum Operation {
  Arguments
  Environment
  Clock
  Random
  Poll
  Open
  Close
  Read
  Write
  Seek
  Sync
  Metadata
  ReadDirectory
  CreateDirectory
  Remove
  Rename
  Link
} derive(Eq, Debug)

///|
/// Return the stable, human-readable name of an operation.
pub fn Operation::name(self : Operation) -> String {
  match self {
    Arguments => "arguments"
    Environment => "environment"
    Clock => "clock"
    Random => "random"
    Poll => "poll"
    Open => "open"
    Close => "close"
    Read => "read"
    Write => "write"
    Seek => "seek"
    Sync => "sync"
    Metadata => "metadata"
    ReadDirectory => "read-directory"
    CreateDirectory => "create-directory"
    Remove => "remove"
    Rename => "rename"
    Link => "link"
  }
}

///|
/// A contextual error raised by the high-level API.
pub(all) suberror WasiError {
  WasiFailure(Operation, String?, @wasi.Errno)
  InvalidInput(Operation, String)
} derive(Eq, Debug)

///|
/// Construct an error while retaining the original WASI errno.
pub fn wasi_error(
  operation : Operation,
  errno : @wasi.Errno,
  path? : String,
) -> WasiError {
  WasiFailure(operation, path, errno)
}

///|
/// Return the operation that failed.
pub fn WasiError::operation(self : WasiError) -> Operation {
  match self {
    WasiFailure(operation, _, _) => operation
    InvalidInput(operation, _) => operation
  }
}

///|
/// Return the path associated with an error, when one exists.
pub fn WasiError::path(self : WasiError) -> String? {
  match self {
    WasiFailure(_, path, _) => path
    InvalidInput(_, _) => None
  }
}

///|
/// Return the original WASI errno, when the failure came from the host.
pub fn WasiError::errno(self : WasiError) -> @wasi.Errno? {
  match self {
    WasiFailure(_, _, errno) => Some(errno)
    InvalidInput(_, _) => None
  }
}

///|
/// Format a concise error message suitable for logs and command-line tools.
pub fn WasiError::message(self : WasiError) -> String {
  match self {
    WasiFailure(operation, Some(path), errno) =>
      "\{operation.name()} '\{path}' failed with WASI errno \{errno.value()}"
    WasiFailure(operation, None, errno) =>
      "\{operation.name()} failed with WASI errno \{errno.value()}"
    InvalidInput(operation, reason) =>
      "invalid input for \{operation.name()}: \{reason}"
  }
}
