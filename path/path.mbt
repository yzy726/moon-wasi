///|
/// Errors detected while validating a WASI guest path.
pub(all) suberror PathError {
  EmptyPath
  AbsolutePath(String)
  ParentTraversal(String)
  Backslash(String)
  NulByte(String)
} derive(Eq, Debug)

///|
/// A normalized relative path inside a WASI preopened directory.
pub struct GuestPath {
  value : String
} derive(Eq, Debug)

///|
/// Validate and normalize an untrusted guest path.
pub fn GuestPath::new(raw : StringView) -> GuestPath raise PathError {
  let input = raw.to_owned()
  guard !input.is_empty() else { raise EmptyPath }
  guard !input.has_prefix("/") else { raise AbsolutePath(input) }
  guard !input.contains("\\") else { raise Backslash(input) }
  guard !input.contains("\u{0000}") else { raise NulByte(input) }
  let normalized : Array[String] = []
  for segment in input.split("/") {
    let segment = segment.to_owned()
    match segment {
      "" | "." => ()
      ".." =>
        match normalized.pop() {
          Some(_) => ()
          None => raise ParentTraversal(input)
        }
      segment => normalized.push(segment)
    }
  }
  { value: if normalized.is_empty() { "." } else { normalized.join("/") } }
}

///|
/// Return the canonical relative representation of this path.
pub fn GuestPath::as_string(self : GuestPath) -> String {
  self.value
}

///|
/// Return whether this path denotes its preopen root.
pub fn GuestPath::is_root(self : GuestPath) -> Bool {
  self.value == "."
}

///|
/// Return the normalized path segments. The root has no segments.
pub fn GuestPath::segments(self : GuestPath) -> Array[String] {
  if self.is_root() {
    []
  } else {
    self.value.split("/").map(segment => segment.to_owned()).to_array()
  }
}

///|
/// Join an untrusted relative suffix and validate the combined path.
pub fn GuestPath::join(
  self : GuestPath,
  suffix : StringView,
) -> GuestPath raise PathError {
  if self.is_root() {
    GuestPath::new(suffix)
  } else {
    GuestPath::new("\{self.value}/\{suffix}")
  }
}

///|
/// Return the parent path, or `None` for the capability root.
pub fn GuestPath::parent(self : GuestPath) -> GuestPath? {
  if self.is_root() {
    None
  } else {
    let segments = self.segments()
    ignore(segments.pop())
    Some({ value: if segments.is_empty() { "." } else { segments.join("/") } })
  }
}

///|
/// Return the final component, or `None` for the capability root.
pub fn GuestPath::file_name(self : GuestPath) -> String? {
  if self.is_root() {
    None
  } else {
    self.segments().pop()
  }
}

///|
/// Return whether `self` is equal to or nested below `base`.
pub fn GuestPath::is_within(self : GuestPath, base : GuestPath) -> Bool {
  if base.is_root() {
    true
  } else {
    self.value == base.value || self.value.has_prefix("\{base.value}/")
  }
}
