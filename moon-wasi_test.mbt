// Blackbox tests run against the package's public API. Use `@moon-wasi` to import.
// Prefer high-level behaviors over implementation details.

///|
test "operation names are stable" {
  let cases = [
    (@moon-wasi.Operation::Arguments, "arguments"),
    (@moon-wasi.Operation::Environment, "environment"),
    (@moon-wasi.Operation::Clock, "clock"),
    (@moon-wasi.Operation::Random, "random"),
    (@moon-wasi.Operation::Poll, "poll"),
    (@moon-wasi.Operation::Open, "open"),
    (@moon-wasi.Operation::Close, "close"),
    (@moon-wasi.Operation::Read, "read"),
    (@moon-wasi.Operation::Write, "write"),
    (@moon-wasi.Operation::Seek, "seek"),
    (@moon-wasi.Operation::Sync, "sync"),
    (@moon-wasi.Operation::Metadata, "metadata"),
    (@moon-wasi.Operation::ReadDirectory, "read-directory"),
    (@moon-wasi.Operation::CreateDirectory, "create-directory"),
    (@moon-wasi.Operation::Remove, "remove"),
    (@moon-wasi.Operation::Rename, "rename"),
    (@moon-wasi.Operation::Link, "link"),
    (@moon-wasi.Operation::Copy, "copy"),
    (@moon-wasi.Operation::AtomicWrite, "atomic-write"),
  ]
  for item in cases {
    let (operation, expected) = item
    assert_eq(operation.name(), expected)
  }
}

///|
test "host errors can omit path context" {
  let error = @moon-wasi.wasi_error(
    @moon-wasi.Operation::Arguments,
    @wasi.Errno::IO,
  )
  assert_eq(error.path(), None)
  assert_eq(
    error.message(),
    "arguments failed with WASI errno \{@wasi.Errno::IO.value()}",
  )
}

///|
test "contextual errors preserve their source" {
  let error = @moon-wasi.wasi_error(
    @moon-wasi.Operation::Open,
    @wasi.Errno::Noent,
    path="fixtures/missing.txt",
  )
  assert_eq(error.operation(), @moon-wasi.Operation::Open)
  assert_eq(error.path(), Some("fixtures/missing.txt"))
  assert_eq(error.errno(), Some(@wasi.Errno::Noent))
  assert_eq(
    error.message(),
    "open 'fixtures/missing.txt' failed with WASI errno 44",
  )
}

///|
test "invalid input has no fabricated host context" {
  let error : @moon-wasi.WasiError = @moon-wasi.InvalidInput(
    @moon-wasi.Operation::Copy,
    "source and destination overlap",
  )
  assert_eq(error.operation(), @moon-wasi.Operation::Copy)
  assert_eq(error.path(), None)
  assert_eq(error.errno(), None)
  assert_eq(
    error.message(),
    "invalid input for copy: source and destination overlap",
  )
}
