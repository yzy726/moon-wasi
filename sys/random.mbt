///|
/// Fill a caller-owned buffer with host-provided secure random bytes.
pub fn fill_random(buffer : FixedArray[Byte]) -> Unit raise @root.WasiError {
  @wasi.random_get(buffer) catch {
    errno => raise @root.wasi_error(@root.Operation::Random, errno)
  }
}

///|
/// Allocate a secure random byte sequence.
pub fn random_bytes(length : Int) -> Bytes raise @root.WasiError {
  guard length >= 0 else {
    raise @root.InvalidInput(
      @root.Operation::Random,
      "length must not be negative",
    )
  }
  let buffer = FixedArray::make(length, b'\x00')
  fill_random(buffer)
  Bytes::from_array(buffer)
}

///|
/// Return a uniformly random 64-bit value.
pub fn random_u64() -> UInt64 raise @root.WasiError {
  let bytes = random_bytes(8)
  let mut value = 0UL
  for index in 0..<8 {
    value = value | (bytes[index].to_int().to_uint64() << (index * 8))
  }
  value
}

///|
/// Return an unbiased random value in `[0, upper_bound)`.
pub fn random_below(upper_bound : UInt64) -> UInt64 raise @root.WasiError {
  guard upper_bound > 0UL else {
    raise @root.InvalidInput(
      @root.Operation::Random,
      "upper_bound must be positive",
    )
  }
  let threshold = (0UL - upper_bound) % upper_bound
  while true {
    let value = random_u64()
    if value >= threshold {
      return value % upper_bound
    }
  }
  0UL
}
