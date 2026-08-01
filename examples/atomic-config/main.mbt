///|
fn run() -> Unit raise {
  let arguments = @wasi_sys.arguments()
  let raw_path = if arguments.length() > 1 {
    arguments[1]
  } else {
    "target/moon-wasi-example/config.txt"
  }
  let content = if arguments.length() > 2 {
    arguments[2]
  } else {
    "enabled=true\n"
  }
  let path = @path.GuestPath::new(raw_path)
  match path.parent() {
    Some(parent) => @wasi_fs.create_dir_all(parent)
    None => ()
  }
  @wasi_fs.atomic_write_text(path, content)
  @wasi_sys.print("wrote \{path.as_string()}: \{@wasi_fs.read_text(path)}")
}

///|
fn main {
  run() catch {
    error => {
      @wasi_sys.eprint("atomic-config failed: \{@debug.to_string(error)}\n") catch {
        _ => ()
      }
      @wasi_sys.exit(1)
    }
  }
}
