pub mod exec;
pub mod file;
pub mod http;
pub mod process;
pub mod tcp;
pub mod udp;

use crate::executor::context::Context;
use crate::executor::error::ExecutionError;
use crate::transpiler::ir::{Probe, ProbeResult};
use std::time::Duration;

/// execute a probe and return the result
pub async fn execute_probe(
    probe: &Probe,
    ctx: &Context,
    timeout: Option<Duration>,
) -> Result<ProbeResult, ExecutionError> {
    match probe {
        Probe::Tcp(p) => tcp::execute(p, ctx).await,
        Probe::Udp(p) => udp::execute(p, ctx).await,
        Probe::Http(p) => http::execute(p, ctx).await,
        Probe::Exec(p) => exec::execute_with_timeout(p, ctx, timeout).await,
        Probe::File(p) => file::execute(p, ctx).await,
        Probe::Process(p) => process::execute(p, ctx).await,
    }
}
