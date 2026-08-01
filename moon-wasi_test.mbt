// Blackbox tests run against the package's public API. Use `@moon-wasi` to import.
// Prefer high-level behaviors over implementation details.

///|
test "operation names are stable" {
  assert_eq(@moon-wasi.Operation::ReadDirectory.name(), "read-directory")
  assert_eq(@moon-wasi.Operation::CreateDirectory.name(), "create-directory")
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
