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
  let file_as_directory = root.join("file-as-directory")
  @wasi_fs.write_text(file_as_directory, "not a directory")
  let mut rejected_file_directory = false
  @wasi_fs.create_dir_all(file_as_directory) catch {
    @root.InvalidInput(@root.Operation::CreateDirectory, _) =>
      rejected_file_directory = true
    _ => ()
  }
  check(rejected_file_directory, "create_dir_all accepted a regular file")
  let many = root.join("many")
  @wasi_fs.create_dir(many)
  for index in 0..<180 {
    @wasi_fs.write_text(many.join("entry-\{index}.txt"), "")
  }
  let many_entries = @wasi_fs.read_dir(many)
  check(many_entries.length() == 180, "paginated read_dir lost entries")
  check(many_entries[0].name == "entry-0.txt", "read_dir is not sorted")
  check(many_entries[179].name == "entry-99.txt", "read_dir sort is unstable")
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
  let mut rejected_nested_copy = false
  @wasi_fs.copy_tree(source, source.join("recursive-copy")) catch {
    @root.InvalidInput(@root.Operation::Copy, _) => rejected_nested_copy = true
    _ => ()
  }
  check(rejected_nested_copy, "copy_tree accepted a nested destination")
  let existing = root.join("existing.txt")
  @wasi_fs.write_text(existing, "keep")
  let mut rejected_overwrite = false
  ignore(@wasi_fs.copy_file(source.join("a.txt"), existing)) catch {
    @root.WasiFailure(_, _, @wasi.Exist) => rejected_overwrite = true
    _ => ()
  }
  check(rejected_overwrite, "copy_file overwrote an existing destination")
  check(@wasi_fs.read_text(existing) == "keep", "failed copy changed content")
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
  let create_only = root.join("create-only.txt")
  @wasi_fs.atomic_write_text(create_only, "created", replace=false)
  check(
    @wasi_fs.read_text(create_only) == "created",
    "replace=false failed to create a missing file",
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
  let original_metadata = @wasi_fs.metadata(original)
  let hard_metadata = @wasi_fs.metadata(hard)
  check(original_metadata.links >= 2UL, "hard link count was not updated")
  check(
    original_metadata.device == hard_metadata.device &&
    original_metadata.inode == hard_metadata.inode,
    "hard links did not report the same file identity",
  )
  let mut rejected_alias_copy = false
  ignore(@wasi_fs.copy_file(original, hard, overwrite=true)) catch {
    @root.InvalidInput(@root.Operation::Copy, _) => rejected_alias_copy = true
    _ => ()
  }
  check(rejected_alias_copy, "copy_file accepted a hard-link alias")
  check(@wasi_fs.read_text(original) == "linked", "alias copy truncated source")
  let symbolic = directory.join("symbolic.txt")
  let mut rejected_escape = false
  @wasi_fs.symbolic_link("../escape", @path.GuestPath::new("escape-link")) catch {
    @root.InvalidInput(@root.Operation::Link, _) => rejected_escape = true
    _ => ()
  }
  check(rejected_escape, "symbolic link escaped the capability root")
  log("creating symbolic link")
  let mut symbolic_created = false
  try @wasi_fs.symbolic_link("original.txt", symbolic) catch {
    @root.WasiFailure(@root.Operation::Link, _, @wasi.Perm) =>
      log("symbolic link skipped: host permission denied")
    @root.WasiFailure(@root.Operation::Link, _, @wasi.Notsup) =>
      log("symbolic link skipped: host does not support it")
    @root.WasiFailure(@root.Operation::Link, _, @wasi.Noent) =>
      log("symbolic link skipped: host could not resolve the relative target")
    error => raise error
  } noraise {
    _ => symbolic_created = true
  }
  if symbolic_created {
    log("reading symbolic link")
    check(
      @wasi_fs.read_link(symbolic) == "original.txt",
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
