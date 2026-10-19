//! Shared HaveAPI protocol and HTTP execution, copied into generated crates.

mod auth;
mod client;
mod error;
mod protocol;
mod transport;
mod types;
mod validation;

pub use auth::{SecretString, TokenStep};
pub use client::{Client, ClientBuilder, ClientConfig, Request};
pub use error::Error;
pub use protocol::{decode, prepare};
#[cfg(feature = "blocking")]
pub use transport::BlockingTransport;
pub use transport::{AsyncTransport, Mode};
pub use types::*;
pub use validation::Validate;
