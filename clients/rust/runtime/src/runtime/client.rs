use std::{collections::BTreeMap, fmt, marker::PhantomData, sync::Arc, time::Duration};

use reqwest::header::{ACCEPT, AUTHORIZATION, HeaderMap, HeaderName, HeaderValue, USER_AGENT};
use serde::{Serialize, de::DeserializeOwned};

#[cfg(feature = "blocking")]
use crate::runtime::BlockingTransport;
use crate::runtime::{
    ActionSpec, ApiSpec, AsyncTransport, Error, JsonMap, Mode, PreparedRequest, RequestAuth,
    RequestParts, Response, Validate, decode, prepare,
};

pub struct ClientConfig {
    pub(crate) base: url::Url,
    pub(crate) headers: HeaderMap,
    pub(crate) auth: Option<(HeaderName, HeaderValue)>,
    pub(crate) timeout: Duration,
    pub(crate) connect_timeout: Duration,
    pub(crate) max_response_bytes: usize,
}

#[derive(Clone)]
pub struct Client<C: Mode> {
    config: Arc<ClientConfig>,
    transport: C,
}

impl<C: Mode> Client<C> {
    pub fn config(&self) -> &ClientConfig {
        &self.config
    }
}

enum Credentials {
    Basic(String, String),
    Token(String),
    OAuth2(String),
}

pub struct ClientBuilder<C: Mode> {
    base: String,
    api: &'static ApiSpec,
    credentials: Option<Credentials>,
    auth_selections: usize,
    timeout: Duration,
    connect_timeout: Duration,
    max_response_bytes: usize,
    user_agent: String,
    mode: PhantomData<C>,
}

impl<C: Mode> ClientBuilder<C> {
    pub fn new(base: impl AsRef<str>, api: &'static ApiSpec) -> Self {
        Self {
            base: base.as_ref().to_owned(),
            api,
            credentials: None,
            auth_selections: 0,
            timeout: Duration::from_secs(30),
            connect_timeout: Duration::from_secs(10),
            max_response_bytes: 16 * 1024 * 1024,
            user_agent: "haveapi-rust-client".into(),
            mode: PhantomData,
        }
    }

    pub fn basic_auth(mut self, username: impl Into<String>, password: impl Into<String>) -> Self {
        self.credentials = Some(Credentials::Basic(username.into(), password.into()));
        self.auth_selections += 1;
        self
    }

    pub fn token(mut self, token: impl Into<String>) -> Self {
        self.credentials = Some(Credentials::Token(token.into()));
        self.auth_selections += 1;
        self
    }

    pub fn oauth2_token(mut self, token: impl Into<String>) -> Self {
        self.credentials = Some(Credentials::OAuth2(token.into()));
        self.auth_selections += 1;
        self
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }
    pub fn connect_timeout(mut self, timeout: Duration) -> Self {
        self.connect_timeout = timeout;
        self
    }
    pub fn max_response_bytes(mut self, bytes: usize) -> Self {
        self.max_response_bytes = bytes;
        self
    }
    pub fn user_agent(mut self, value: impl Into<String>) -> Self {
        self.user_agent = value.into();
        self
    }

    fn finish(self) -> Result<ClientConfig, Error> {
        if self.api.protocol_major != 2 {
            return Err(Error::configuration("unsupported HaveAPI protocol major"));
        }
        if self.api.api_version.is_empty() {
            return Err(Error::configuration("API version is required"));
        }
        if self.auth_selections > 1 {
            return Err(Error::configuration(
                "select only one authentication method",
            ));
        }
        if self.timeout.is_zero() || self.connect_timeout.is_zero() {
            return Err(Error::configuration("HTTP timeouts must be positive"));
        }
        if self.max_response_bytes == 0 {
            return Err(Error::configuration("response size limit must be positive"));
        }
        let base = crate::runtime::protocol::parse_base(&self.base)?;
        let mut headers = HeaderMap::new();
        headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
        headers.insert(
            USER_AGENT,
            HeaderValue::from_str(&self.user_agent)
                .map_err(|_| Error::configuration("invalid user agent"))?,
        );
        let auth = match self.credentials {
            None => None,
            Some(Credentials::Basic(username, password)) => {
                if !self.api.basic_auth {
                    return Err(Error::configuration(
                        "Basic authentication is not described",
                    ));
                }
                if username.contains(':') {
                    return Err(Error::configuration(
                        "Basic username cannot contain a colon",
                    ));
                }
                let encoded = base64(format!("{username}:{password}").as_bytes());
                let mut value = HeaderValue::from_str(&format!("Basic {encoded}"))
                    .map_err(|_| Error::configuration("invalid Basic authentication"))?;
                value.set_sensitive(true);
                Some((AUTHORIZATION, value))
            }
            Some(Credentials::Token(token)) => Some(token_header(self.api.token_header, token)?),
            Some(Credentials::OAuth2(token)) => Some(token_header(self.api.oauth2_header, token)?),
        };
        Ok(ClientConfig {
            base,
            headers,
            auth,
            timeout: self.timeout,
            connect_timeout: self.connect_timeout,
            max_response_bytes: self.max_response_bytes,
        })
    }
}

impl ClientBuilder<AsyncTransport> {
    pub fn build(self) -> Result<Client<AsyncTransport>, Error> {
        let config = self.finish()?;
        let transport = AsyncTransport::new(&config)?;
        Ok(Client {
            config: Arc::new(config),
            transport,
        })
    }
}

#[cfg(feature = "blocking")]
impl ClientBuilder<BlockingTransport> {
    /// Build, use, and drop this client outside async runtime threads.
    pub fn build(self) -> Result<Client<BlockingTransport>, Error> {
        let config = self.finish()?;
        let transport = BlockingTransport::new(&config)?;
        Ok(Client {
            config: Arc::new(config),
            transport,
        })
    }
}

pub struct Request<'a, C: Mode, I, O, M> {
    client: &'a Client<C>,
    spec: &'static ActionSpec,
    path_params: BTreeMap<String, String>,
    input: I,
    global_meta: Option<JsonMap>,
    object_meta: Option<JsonMap>,
    output: PhantomData<(O, M)>,
}

impl<'a, C: Mode, I, O, M> Request<'a, C, I, O, M> {
    pub fn new(
        client: &'a Client<C>,
        spec: &'static ActionSpec,
        path_params: BTreeMap<String, String>,
        input: I,
    ) -> Self {
        Self {
            client,
            spec,
            path_params,
            input,
            global_meta: None,
            object_meta: None,
            output: PhantomData,
        }
    }
    pub fn input(mut self, input: I) -> Self {
        *self.input_mut() = input;
        self
    }
    pub fn global_meta(mut self, meta: JsonMap) -> Self {
        self.global_meta = Some(meta);
        self
    }
    pub fn object_meta(mut self, meta: JsonMap) -> Self {
        self.object_meta = Some(meta);
        self
    }
    pub(crate) fn input_mut(&mut self) -> &mut I {
        &mut self.input
    }
}

impl<C: Mode, I: Serialize + Validate, O, M> Request<'_, C, I, O, M> {
    fn prepared(self) -> Result<PreparedRequest, Error> {
        self.input.validate()?;
        let input = if self.spec.input.is_some() {
            Some(serde_json::to_value(self.input).map_err(|_| Error::Encode)?)
        } else {
            None
        };
        prepare(
            &self.client.config,
            self.spec,
            RequestParts {
                path_params: self.path_params,
                input,
                global_meta: self.global_meta,
                object_meta: self.object_meta,
            },
        )
    }
}

impl<I: Serialize + Validate, O: DeserializeOwned, M: DeserializeOwned>
    Request<'_, AsyncTransport, I, O, M>
{
    pub async fn send(self) -> Result<Response<O, M>, Error> {
        let client = self.client;
        let spec = self.spec;
        let request = self.prepared()?;
        decode(spec, client.transport.execute(request).await?)
    }
}

#[cfg(feature = "blocking")]
impl<I: Serialize + Validate, O: DeserializeOwned, M: DeserializeOwned>
    Request<'_, BlockingTransport, I, O, M>
{
    pub fn send(self) -> Result<Response<O, M>, Error> {
        let client = self.client;
        let spec = self.spec;
        let request = self.prepared()?;
        decode(spec, client.transport.execute(request)?)
    }
}

fn token_header(header: Option<&str>, token: String) -> Result<(HeaderName, HeaderValue), Error> {
    let name = HeaderName::from_bytes(
        header
            .ok_or_else(|| Error::configuration("requested token provider is not described"))?
            .as_bytes(),
    )
    .map_err(|_| Error::configuration("invalid authentication header name"))?;
    if matches!(
        name.as_str(),
        "host"
            | "content-length"
            | "content-type"
            | "accept"
            | "user-agent"
            | "connection"
            | "transfer-encoding"
            | "proxy-authorization"
            | "proxy-authenticate"
            | "te"
            | "trailer"
            | "upgrade"
            | "cookie"
            | "referer"
            | "location"
    ) {
        return Err(Error::configuration("reserved authentication header name"));
    }
    if token.trim().is_empty() {
        return Err(Error::configuration("token cannot be empty"));
    }
    let mut value = HeaderValue::from_str(&token)
        .map_err(|_| Error::configuration("invalid token header value"))?;
    value.set_sensitive(true);
    Ok((name, value))
}

fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let first = chunk[0];
        let second = chunk.get(1).copied().unwrap_or(0);
        let third = chunk.get(2).copied().unwrap_or(0);
        result.push(TABLE[usize::from(first >> 2)] as char);
        result.push(TABLE[usize::from((first & 3) << 4 | second >> 4)] as char);
        result.push(if chunk.len() > 1 {
            TABLE[usize::from((second & 15) << 2 | third >> 6)] as char
        } else {
            '='
        });
        result.push(if chunk.len() > 2 {
            TABLE[usize::from(third & 63)] as char
        } else {
            '='
        });
    }
    result
}

impl fmt::Debug for ClientConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ClientConfig { [REDACTED] }")
    }
}
impl<C: Mode> fmt::Debug for Client<C> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Client { [REDACTED] }")
    }
}
impl<C: Mode> fmt::Debug for ClientBuilder<C> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ClientBuilder { [REDACTED] }")
    }
}
impl<C: Mode, I, O, M> fmt::Debug for Request<'_, C, I, O, M> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Request { [REDACTED] }")
    }
}

impl ClientConfig {
    pub(crate) fn request_headers(&self, auth: RequestAuth) -> HeaderMap {
        let mut headers = self.headers.clone();
        if auth == RequestAuth::Configured
            && let Some((name, value)) = &self.auth
        {
            headers.insert(name.clone(), value.clone());
        }
        headers
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_encoding_matches_rfc7617() {
        assert_eq!(
            base64(b"Aladdin:open sesame"),
            "QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
        );
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"a"), "YQ==");
        assert_eq!(base64(b"ab"), "YWI=");
        assert_eq!(base64(b"abc"), "YWJj");
    }
}
