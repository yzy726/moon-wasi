///|
/// Descriptor readiness to wait for.
pub(all) enum Interest {
  Readable
  Writable
} derive(Eq, Debug)

///|
/// Result of waiting for one descriptor.
pub(all) enum PollResult {
  Ready(UInt64, Bool)
  TimedOut
} derive(Eq, Debug)

///|
fn descriptor_subscription(fd : Int, interest : Interest) -> @wasi.Subscription {
  let descriptor = @wasi.Subscription_fd_readwrite::{
    file_descriptor: @wasi.Fd(fd),
  }
  let payload = match interest {
    Readable => @wasi.Subscription_u::Fd_read(descriptor)
    Writable => @wasi.Subscription_u::Fd_write(descriptor)
  }
  { userdata: @wasi.Userdata(1UL), u: payload }
}

///|
fn timeout_subscription(nanoseconds : UInt64) -> @wasi.Subscription {
  {
    userdata: @wasi.Userdata(0UL),
    u: @wasi.Subscription_u::Clock(@wasi.Subscription_clock::{
      id: @wasi.ClockId::Monotonic,
      timeout: @wasi.TimeStamp(nanoseconds),
      precision: @wasi.TimeStamp(1UL),
      flags: @wasi.SubclockFlags::new(),
    }),
  }
}

///|
/// Wait for one raw WASI descriptor, optionally with a relative timeout.
///
/// The boolean carried by `Ready` reports a hangup condition.
pub fn wait_descriptor(
  fd : Int,
  interest : Interest,
  timeout_ns? : UInt64,
) -> PollResult raise @root.WasiError {
  guard fd >= 0 else {
    raise @root.InvalidInput(
      @root.Operation::Poll,
      "descriptor must be non-negative",
    )
  }
  let subscriptions = [descriptor_subscription(fd, interest)]
  match timeout_ns {
    Some(timeout) => subscriptions.push(timeout_subscription(timeout))
    None => ()
  }
  let events = @wasi.poll_oneoff(subscriptions) catch {
    errno => raise @root.wasi_error(@root.Operation::Poll, errno)
  }
  for event in events {
    guard event.error == @wasi.Success else {
      raise @root.wasi_error(
        @root.Operation::Poll,
        event.error,
        path="fd:\{fd}",
      )
    }
    if event.type_ == @wasi.EventType::Clock {
      return TimedOut
    }
    let hangup = event.fd_readwrite.flags.is_set(
      @wasi.EventRWFlag::Fd_readwrite_hangup,
    )
    return Ready(event.fd_readwrite.nbytes.0, hangup)
  }
  raise @root.InvalidInput(@root.Operation::Poll, "host returned no events")
}
