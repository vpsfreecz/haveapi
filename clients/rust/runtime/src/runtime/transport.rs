use std::fmt;

use crate::runtime::{ClientConfig, Error, PreparedRequest, RawResponse};

mod private {
    pub trait Sealed {}
}

pub trait Mode: private::Sealed {}

#[derive(Clone)]
pub struct AsyncTransport {
    client: reqwest::Client,
    max_response_bytes: usize,
}

impl private::Sealed for AsyncTransport {}
impl Mode for AsyncTransport {}

impl AsyncTransport {
    pub fn new(config: &ClientConfig) -> Result<Self, Error> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .timeout(config.timeout)
            .connect_timeout(config.connect_timeout)
            .build()
            .map_err(|_| Error::configuration("could not construct the HTTP client"))?;
        Ok(Self {
            client,
            max_response_bytes: config.max_response_bytes,
        })
    }

    pub async fn execute(&self, request: PreparedRequest) -> Result<RawResponse, Error> {
        let mut builder = self
            .client
            .request(request.method.reqwest(), request.url)
            .headers(request.headers);
        if let Some(body) = request.body {
            builder = builder.body(body);
        }
        let mut response = builder.send().await.map_err(Error::transport)?;
        let status = response.status().as_u16();
        if response
            .content_length()
            .is_some_and(|length| length > self.max_response_bytes as u64)
        {
            return Err(Error::ResponseTooLarge {
                limit: self.max_response_bytes,
            });
        }
        let mut body = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(Error::transport)? {
            if chunk.len() > self.max_response_bytes.saturating_sub(body.len()) {
                return Err(Error::ResponseTooLarge {
                    limit: self.max_response_bytes,
                });
            }
            body.extend_from_slice(&chunk);
        }
        Ok(RawResponse { status, body })
    }
}

#[cfg(feature = "blocking")]
#[derive(Clone)]
pub struct BlockingTransport {
    client: reqwest::blocking::Client,
    max_response_bytes: usize,
}

#[cfg(feature = "blocking")]
impl private::Sealed for BlockingTransport {}
#[cfg(feature = "blocking")]
impl Mode for BlockingTransport {}

#[cfg(feature = "blocking")]
impl BlockingTransport {
    pub fn new(config: &ClientConfig) -> Result<Self, Error> {
        let client = reqwest::blocking::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .timeout(config.timeout)
            .connect_timeout(config.connect_timeout)
            .build()
            .map_err(|_| Error::configuration("could not construct the blocking HTTP client"))?;
        Ok(Self {
            client,
            max_response_bytes: config.max_response_bytes,
        })
    }

    pub fn execute(&self, request: PreparedRequest) -> Result<RawResponse, Error> {
        use std::io::Read;

        let mut builder = self
            .client
            .request(request.method.reqwest(), request.url)
            .headers(request.headers);
        if let Some(body) = request.body {
            builder = builder.body(body);
        }
        let mut response = builder.send().map_err(Error::transport)?;
        let status = response.status().as_u16();
        if response
            .content_length()
            .is_some_and(|length| length > self.max_response_bytes as u64)
        {
            return Err(Error::ResponseTooLarge {
                limit: self.max_response_bytes,
            });
        }
        let mut body = Vec::new();
        let mut buffer = [0; 8192];
        loop {
            let remaining = self.max_response_bytes.saturating_sub(body.len());
            let to_read = buffer.len().min(remaining.saturating_add(1));
            let length = response.read(&mut buffer[..to_read]).map_err(|error| {
                // reqwest wraps body failures in io::Error while preserving its source.
                let timeout = error.kind() == std::io::ErrorKind::TimedOut
                    || error
                        .get_ref()
                        .and_then(|source| source.downcast_ref::<reqwest::Error>())
                        .is_some_and(reqwest::Error::is_timeout);
                Error::Transport { timeout }
            })?;
            if length == 0 {
                break;
            }
            if length > remaining {
                return Err(Error::ResponseTooLarge {
                    limit: self.max_response_bytes,
                });
            }
            body.extend_from_slice(&buffer[..length]);
        }
        Ok(RawResponse { status, body })
    }
}

impl fmt::Debug for AsyncTransport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("AsyncTransport { [REDACTED] }")
    }
}
#[cfg(feature = "blocking")]
impl fmt::Debug for BlockingTransport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("BlockingTransport { [REDACTED] }")
    }
}
