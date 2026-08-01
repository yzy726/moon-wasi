///|
/// One entry produced by a deterministic depth-first walk.
pub(all) struct WalkEntry {
  path : @path.GuestPath
  kind : FileKind
  depth : Int
} derive(Eq, Debug)

///|
fn walk_inner(
  directory : @path.GuestPath,
  depth : Int,
  max_depth : Int,
  output : Array[WalkEntry],
) -> Unit raise @root.WasiError {
  if max_depth >= 0 && depth >= max_depth {
    return
  }
  for entry in read_dir(directory) {
    let next_depth = depth + 1
    output.push({ path: entry.path, kind: entry.kind, depth: next_depth })
    if entry.kind == Directory {
      walk_inner(entry.path, next_depth, max_depth, output)
    }
  }
}

///|
/// Walk a directory tree in deterministic depth-first order.
///
/// Symbolic links are returned as entries and are never followed, preventing
/// cycles and capability surprises.
pub fn walk(
  root : @path.GuestPath,
  max_depth? : Int = -1,
) -> Array[WalkEntry] raise @root.WasiError {
  guard metadata(root, follow_symlink=false).kind == Directory else {
    raise @root.InvalidInput(
      @root.Operation::ReadDirectory,
      "'\{root.as_string()}' is not a directory",
    )
  }
  let output : Array[WalkEntry] = []
  walk_inner(root, 0, max_depth, output)
  output
}

///|
/// Recursively copy a directory tree.
///
/// The initial release copies regular files and directories. Symbolic links
/// and special files are rejected instead of being followed implicitly.
pub fn copy_tree(
  source : @path.GuestPath,
  destination : @path.GuestPath,
  overwrite? : Bool = false,
) -> Unit raise @root.WasiError {
  guard metadata(source, follow_symlink=false).kind == Directory else {
    raise @root.InvalidInput(
      @root.Operation::Copy,
      "source '\{source.as_string()}' is not a directory",
    )
  }
  if exists(destination) {
    guard overwrite else {
      raise @root.InvalidInput(
        @root.Operation::Copy,
        "destination '\{destination.as_string()}' already exists",
      )
    }
    guard metadata(destination, follow_symlink=false).kind == Directory else {
      raise @root.InvalidInput(
        @root.Operation::Copy,
        "destination '\{destination.as_string()}' is not a directory",
      )
    }
  } else {
    create_dir_all(destination)
  }
  for entry in read_dir(source) {
    let destination_entry = destination.join(entry.name) catch {
      _ =>
        raise @root.InvalidInput(
          @root.Operation::Copy,
          "host returned an invalid directory entry",
        )
    }
    match entry.kind {
      Directory => copy_tree(entry.path, destination_entry, overwrite~)
      Regular =>
        ignore(copy_file(entry.path, destination_entry, overwrite~, sync=Data))
      SymbolicLink =>
        raise @root.InvalidInput(
          @root.Operation::Copy,
          "copying symbolic links requires an explicit policy",
        )
      _ =>
        raise @root.InvalidInput(
          @root.Operation::Copy,
          "special files cannot be copied",
        )
    }
  }
}
