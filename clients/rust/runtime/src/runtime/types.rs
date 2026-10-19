use std::{collections::BTreeMap, fmt};

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

pub type JsonMap = serde_json::Map<String, Value>;
pub type ValidationErrors = BTreeMap<String, Vec<String>>;

/// An omitted input, an explicit null, or an explicitly supplied value.
#[derive(Clone, Default, PartialEq, Eq)]
pub enum InputValue<T> {
    #[default]
    Unset,
    Null,
    Value(T),
}

pub type Input<T> = InputValue<T>;

impl<T> InputValue<T> {
    pub fn is_unset(&self) -> bool {
        matches!(self, Self::Unset)
    }
}

impl<T> fmt::Debug for InputValue<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unset => "Unset",
            Self::Null => "Null",
            Self::Value(_) => "Value([REDACTED])",
        })
    }
}

impl<T: Serialize> Serialize for InputValue<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Unset | Self::Null => serializer.serialize_none(),
            Self::Value(value) => value.serialize(serializer),
        }
    }
}

impl<'de, T: Deserialize<'de>> Deserialize<'de> for InputValue<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(match Option::<T>::deserialize(deserializer)? {
            None => Self::Null,
            Some(value) => Self::Value(value),
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
    Get,
    Delete,
    Post,
    Put,
    Patch,
}

impl Method {
    pub(crate) fn reqwest(self) -> reqwest::Method {
        match self {
            Self::Get => reqwest::Method::GET,
            Self::Delete => reqwest::Method::DELETE,
            Self::Post => reqwest::Method::POST,
            Self::Put => reqwest::Method::PUT,
            Self::Patch => reqwest::Method::PATCH,
        }
    }

    pub(crate) fn query(self) -> bool {
        // The HaveAPI server reads DELETE action input from its JSON body.
        matches!(self, Self::Get)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layout {
    Object,
    ObjectList,
    Hash,
    HashList,
}

impl Layout {
    pub(crate) fn list(self) -> bool {
        matches!(self, Self::ObjectList | Self::HashList)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParameterKind {
    String,
    Text,
    Integer,
    Float,
    Boolean,
    Datetime,
    Resource,
    Custom,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RequestAuth {
    Configured,
    None,
}

#[derive(Clone, Copy, Debug)]
pub struct ParameterSpec {
    pub name: &'static str,
    pub kind: ParameterKind,
    pub required: bool,
    pub nullable: bool,
    pub protected: bool,
}

#[derive(Clone, Copy, Debug)]
pub struct InputSpec {
    pub layout: Layout,
    pub namespace: Option<&'static str>,
    pub parameters: &'static [ParameterSpec],
}

#[derive(Clone, Copy, Debug)]
pub struct OutputSpec {
    pub layout: Layout,
    pub namespace: &'static str,
    pub allow_empty_response: bool,
}

#[derive(Clone, Copy, Debug)]
pub struct ActionSpec {
    pub name: &'static str,
    pub method: Method,
    pub path: &'static str,
    pub input: Option<InputSpec>,
    pub output: Option<OutputSpec>,
    pub meta_namespace: Option<&'static str>,
    pub global_meta: &'static [ParameterSpec],
    pub object_meta: &'static [ParameterSpec],
    pub auth: RequestAuth,
}

#[derive(Clone, Copy, Debug)]
pub struct ApiSpec {
    pub api_version: &'static str,
    pub protocol_major: u16,
    pub schema_sha256: &'static str,
    pub basic_auth: bool,
    pub token_header: Option<&'static str>,
    pub oauth2_header: Option<&'static str>,
}

#[derive(Default)]
pub struct RequestParts {
    pub path_params: BTreeMap<String, String>,
    pub input: Option<Value>,
    pub global_meta: Option<JsonMap>,
    pub object_meta: Option<JsonMap>,
}

pub struct PreparedRequest {
    pub method: Method,
    pub url: url::Url,
    pub headers: reqwest::header::HeaderMap,
    pub body: Option<Vec<u8>>,
}

pub struct RawResponse {
    pub status: u16,
    pub body: Vec<u8>,
}
pub struct Response<T, M> {
    pub output: T,
    pub meta: M,
    pub http_status: u16,
}

macro_rules! redacted_debug {
    ($name:ty, $label:literal) => {
        impl fmt::Debug for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(concat!($label, " { [REDACTED] }"))
            }
        }
    };
}
redacted_debug!(RequestParts, "RequestParts");
redacted_debug!(PreparedRequest, "PreparedRequest");
redacted_debug!(RawResponse, "RawResponse");

impl<T, M> fmt::Debug for Response<T, M> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Response")
            .field("http_status", &self.http_status)
            .finish_non_exhaustive()
    }
}

/// A partial or expanded resource association, without implied network access.
#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Association(JsonMap);

impl Association {
    pub fn as_map(&self) -> &JsonMap {
        &self.0
    }
}

impl From<JsonMap> for Association {
    fn from(value: JsonMap) -> Self {
        Self(value)
    }
}
redacted_debug!(Association, "Association");
