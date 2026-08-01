///|
/// Clocks exposed by WASI Preview 1.
pub(all) enum Clock {
  Realtime
  Monotonic
  ProcessCpu
  ThreadCpu
} derive(Eq, Debug)

///|
fn Clock::to_wasi(self : Clock) -> @wasi.ClockId {
  match self {
    Realtime => @wasi.ClockId::RealTime
    Monotonic => @wasi.ClockId::Monotonic
    ProcessCpu => @wasi.ClockId::ProcessCPUTimeId
    ThreadCpu => @wasi.ClockId::ThreadCPUTimeId
  }
}

///|
/// Return the clock resolution in nanoseconds.
pub fn clock_resolution(clock : Clock) -> UInt64 raise @root.WasiError {
  let result = clock.to_wasi().clock_res_get() catch {
      errno => raise @root.wasi_error(@root.Operation::Clock, errno)
    }
  result.0
}

///|
/// Read a clock in nanoseconds.
pub fn clock_time(
  clock : Clock,
  precision_ns? : UInt64 = 1UL,
) -> UInt64 raise @root.WasiError {
  let result = clock.to_wasi().clock_time_get(@wasi.TimeStamp(precision_ns)) catch {
      errno => raise @root.wasi_error(@root.Operation::Clock, errno)
    }
  result.0
}

///|
/// Sleep for at least the requested number of nanoseconds.
pub fn sleep(nanoseconds : UInt64) -> Unit raise @root.WasiError {
  let subscription = @wasi.Subscription::{
    userdata: @wasi.Userdata(0UL),
    u: @wasi.Subscription_u::Clock(@wasi.Subscription_clock::{
      id: @wasi.ClockId::Monotonic,
      timeout: @wasi.TimeStamp(nanoseconds),
      precision: @wasi.TimeStamp(1UL),
      flags: @wasi.SubclockFlags::new(),
    }),
  }
  let events = @wasi.poll_oneoff([subscription]) catch {
    errno => raise @root.wasi_error(@root.Operation::Poll, errno)
  }
  guard !events.is_empty() else {
    raise @root.InvalidInput(
      @root.Operation::Poll,
      "host returned no timer event",
    )
  }
  guard events[0].error == @wasi.Success else {
    raise @root.wasi_error(@root.Operation::Poll, events[0].error)
  }
}
