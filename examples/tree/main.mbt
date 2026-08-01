///|
fn run() -> Unit raise {
  let arguments = @wasi_sys.arguments()
  let raw_path = if arguments.length() > 1 { arguments[1] } else { "." }
  let root = @path.GuestPath::new(raw_path)
  @wasi_sys.print("\{root.as_string()}\n")
  for entry in @wasi_fs.walk(root) {
    let indent = "  ".repeat(entry.depth)
    let marker = if entry.kind == @wasi_fs.FileKind::Directory {
      "/"
    } else {
      ""
    }
    @wasi_sys.print(
      "\{indent}\{entry.path.file_name().unwrap_or(".")}\{marker}\n",
    )
  }
}

///|
fn main {
  run() catch {
    error => {
      @wasi_sys.eprint("tree failed: \{@debug.to_string(error)}\n") catch {
        _ => ()
      }
      @wasi_sys.exit(1)
    }
  }
}
