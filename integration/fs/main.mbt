///|
fn check(condition : Bool, message : String) -> Unit {
  guard condition else { abort(message) }
}

///|
fn log(message : StringView) -> Unit {
  let data = @utf8.encode("\{message}\n")
  ignore(@wasi.stderr.fd_write([data]) catch { _ => @wasi.Size(0) })
}

///|
fn integration_path(name : StringView) -> @path.GuestPath {
  @path.GuestPath::new("target/moon-wasi-integration/\{name}") catch {
    _ => abort("invalid integration-test path")
  }
}

///|
fn clean(path : @path.GuestPath) -> Unit {
  if @wasi_fs.exists(path) {
    @wasi_fs.remove_tree(path) catch {
      _ => ()
    }
  }
}

///|
fn run_basic_io(root : @path.GuestPath) -> Unit raise {
  let nested = root.join("nested")
  @wasi_fs.create_dir_all(nested)
  let file = nested.join("hello.txt")
  @wasi_fs.write_text(file, "hello", sync=Data)
  @wasi_fs.append_bytes(file, b" world")
  check(@wasi_fs.read_text(file) == "hello world", "text roundtrip failed")
  let metadata = @wasi_fs.metadata(file)
  check(metadata.kind == @wasi_fs.FileKind::Regular, "unexpected file kind")
  check(metadata.size == 11UL, "unexpected file size")
  check(metadata.links >= 1UL, "unexpected link count")
  let opened = @wasi_fs.open(file, @wasi_fs.OpenOptions::read_only())
  check(opened.seek(6L, @wasi_fs.SeekFrom::Start) == 6UL, "seek failed")
  check(opened.tell() == 6UL, "tell failed")
  check(opened.read_all() == b"world", "read after seek failed")
  opened.close()
}

///|
fn run_tree_operations(root : @path.GuestPath) -> Unit raise {
  let source = root.join("source")
  let nested = source.join("sub")
  @wasi_fs.create_dir_all(nested)
  @wasi_fs.write_text(source.join("a.txt"), "A")
  @wasi_fs.write_text(nested.join("b.txt"), "B")
  let walked = @wasi_fs.walk(source)
  log("walked entries: \{@debug.to_string(walked)}")
  check(walked.length() == 3, "walk returned the wrong entry count")
  check(
    walked[1].kind == @wasi_fs.FileKind::Directory,
    "walk order is unstable",
  )
  check(walked[2].depth == 2, "walk depth is incorrect")
  let destination = root.join("copy")
  log("copying tree")
  @wasi_fs.copy_tree(source, destination)
  log("checking copied tree")
  check(@wasi_fs.read_text(destination.join("sub/b.txt")) == "B", "copy failed")
  @wasi_fs.rename(destination.join("a.txt"), destination.join("renamed.txt"))
  log("checking renamed file")
  check(!@wasi_fs.exists(destination.join("a.txt")), "rename left the source")
  check(
    @wasi_fs.read_text(destination.join("renamed.txt")) == "A",
    "rename failed",
  )
}

///|
fn run_atomic_write(root : @path.GuestPath) -> Unit raise {
  let path = root.join("state.txt")
  @wasi_fs.atomic_write_text(path, "version-one")
  @wasi_fs.atomic_write_text(path, "version-two")
  check(@wasi_fs.read_text(path) == "version-two", "atomic replace failed")
  let mut rejected = false
  @wasi_fs.atomic_write_text(path, "unexpected", replace=false) catch {
    @root.InvalidInput(@root.Operation::AtomicWrite, _) => rejected = true
    _ => ()
  }
  check(rejected, "replace=false accepted an existing path")
  check(
    @wasi_fs.read_text(path) == "version-two",
    "failed write changed content",
  )
}

///|
fn run_links(root : @path.GuestPath) -> Unit raise {
  let directory = root.join("links")
  @wasi_fs.create_dir_all(directory)
  let original = directory.join("original.txt")
  let hard = directory.join("hard.txt")
  @wasi_fs.write_text(original, "linked")
  @wasi_fs.hard_link(original, hard)
  check(@wasi_fs.read_text(hard) == "linked", "hard link content differs")
  check(
    @wasi_fs.metadata(original).links >= 2UL,
    "hard link count was not updated",
  )
  let symbolic = directory.join("symbolic.txt")
  log("creating symbolic link")
  let mut symbolic_created = false
  try @wasi_fs.symbolic_link(original, symbolic) catch {
    @root.WasiFailure(@root.Operation::Link, _, @wasi.Perm) =>
      log("symbolic link skipped: host permission denied")
    @root.WasiFailure(@root.Operation::Link, _, @wasi.Notsup) =>
      log("symbolic link skipped: host does not support it")
    error => raise error
  } noraise {
    _ => symbolic_created = true
  }
  if symbolic_created {
    log("reading symbolic link")
    check(
      @wasi_fs.read_link(symbolic) == original.as_string(),
      "read_link returned bad data",
    )
  }
}

///|
fn main {
  try {
    let root = integration_path("fs")
    clean(root)
    defer clean(root)
    @wasi_fs.create_dir_all(root)
    log("running basic I/O")
    run_basic_io(root)
    log("running tree operations")
    run_tree_operations(root)
    log("running link operations")
    run_links(root)
    log("running atomic write")
    run_atomic_write(root)
    log("filesystem integration passed")
  } catch {
    error => {
      log("filesystem integration failed: \{@debug.to_string(error)}")
      abort("WASI file-system integration test failed")
    }
  }
}
