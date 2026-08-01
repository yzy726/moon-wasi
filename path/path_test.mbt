///|
test "normalizes guest paths" {
  let path = @path.GuestPath::new("./assets//images/../logo.png")
  assert_eq(path.as_string(), "assets/logo.png")
  assert_eq(path.file_name(), Some("logo.png"))
  assert_eq(path.parent().map(path => path.as_string()), Some("assets"))
}

///|
test "normalizes the capability root" {
  let root = @path.GuestPath::new("a/..")
  assert_true(root.is_root())
  assert_eq(root.segments(), [])
  assert_eq(root.parent(), None)
  assert_eq(root.file_name(), None)
}

///|
test "joins and checks containment" {
  let base = @path.GuestPath::new("workspace/cache")
  let child = base.join("artifacts/result.bin")
  let sibling = @path.GuestPath::new("workspace/config")
  assert_eq(child.as_string(), "workspace/cache/artifacts/result.bin")
  assert_true(child.is_within(base))
  assert_true(!sibling.is_within(base))
}

///|
test "rejects absolute paths" {
  try @path.GuestPath::new("/etc/passwd") catch {
    @path.AbsolutePath(_) => ()
    _ => fail("expected AbsolutePath")
  } noraise {
    _ => fail("expected validation to fail")
  }
}

///|
test "rejects parent traversal" {
  try @path.GuestPath::new("../../secret") catch {
    @path.ParentTraversal(_) => ()
    _ => fail("expected ParentTraversal")
  } noraise {
    _ => fail("expected validation to fail")
  }
}

///|
test "rejects platform-specific separators" {
  try @path.GuestPath::new("folder\\file.txt") catch {
    @path.Backslash(_) => ()
    _ => fail("expected Backslash")
  } noraise {
    _ => fail("expected validation to fail")
  }
}

///|
test "rejects empty and nul-containing paths" {
  try @path.GuestPath::new("") catch {
    @path.EmptyPath => ()
    _ => fail("expected EmptyPath")
  } noraise {
    _ => fail("expected validation to fail")
  }
  try @path.GuestPath::new("bad\u{0000}path") catch {
    @path.NulByte(_) => ()
    _ => fail("expected NulByte")
  } noraise {
    _ => fail("expected validation to fail")
  }
}

///|
test "normalization table" {
  let cases = [
    (".", "."),
    ("./a", "a"),
    ("a/", "a"),
    ("a//b", "a/b"),
    ("a/./b", "a/b"),
    ("a/b/..", "a"),
    ("a/b/../c", "a/c"),
  ]
  for item in cases {
    let (raw, expected) = item
    assert_eq(@path.GuestPath::new(raw).as_string(), expected)
  }
}

///|
test "containment respects component boundaries" {
  let base = @path.GuestPath::new("work/cache")
  assert_true(@path.GuestPath::new("work/cache").is_within(base))
  assert_true(@path.GuestPath::new("work/cache/item").is_within(base))
  assert_true(!@path.GuestPath::new("work/cache-old").is_within(base))
  assert_true(!@path.GuestPath::new("work").is_within(base))
}
