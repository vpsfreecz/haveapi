use std::collections::{BTreeMap, BTreeSet};

use reqwest::header::{CONTENT_TYPE, HeaderValue};
use serde::de::DeserializeOwned;
use serde_json::Value;
use url::Url;

use crate::runtime::validation::validate_map;
use crate::runtime::{
    ActionSpec, ClientConfig, Error, JsonMap, PreparedRequest, RawResponse, RequestParts, Response,
    ValidationErrors,
};

pub fn prepare(
    config: &ClientConfig,
    spec: &ActionSpec,
    parts: RequestParts,
) -> Result<PreparedRequest, Error> {
    let mut url = action_url(&config.base, spec.path, &parts.path_params)?;
    let has_global_meta = parts.global_meta.is_some();
    let has_object_meta = parts.object_meta.is_some();
    let mut root = JsonMap::new();
    match spec.input {
        None => {
            if parts.input.is_some() {
                return Err(Error::validation("input", "action has no described input"));
            }
            if parts.object_meta.is_some() {
                return Err(Error::validation(
                    "object_meta",
                    "requires a named object input",
                ));
            }
        }
        Some(input_spec) => {
            let mut input = parts.input.unwrap_or_else(|| {
                if input_spec.layout.list() {
                    Value::Array(Vec::new())
                } else {
                    Value::Object(JsonMap::new())
                }
            });
            if input_spec.layout.list() {
                if input_spec.namespace.is_none() {
                    return Err(Error::configuration("list input requires a namespace"));
                }
                if spec.method.query() {
                    return Err(Error::validation(
                        "input",
                        "list input is unsupported in query parameters",
                    ));
                }
                if parts.object_meta.is_some() {
                    return Err(Error::validation(
                        "object_meta",
                        "per-item input metadata is unsupported",
                    ));
                }
                let items = input
                    .as_array()
                    .ok_or_else(|| Error::validation("input", "expected an object list"))?;
                for (index, item) in items.iter().enumerate() {
                    let object = item.as_object().ok_or_else(|| {
                        Error::validation(format!("input[{index}]"), "expected an object")
                    })?;
                    validate_map(object, input_spec.parameters, &format!("input[{index}]."))?;
                }
            } else {
                let object = input
                    .as_object_mut()
                    .ok_or_else(|| Error::validation("input", "expected an object"))?;
                validate_map(object, input_spec.parameters, "")?;
                if let Some(object_meta) = parts.object_meta {
                    let namespace = spec.meta_namespace.ok_or_else(|| {
                        Error::validation("object_meta", "metadata namespace is not described")
                    })?;
                    if input_spec.namespace.is_none() {
                        return Err(Error::validation(
                            "object_meta",
                            "requires a named object input",
                        ));
                    }
                    validate_map(&object_meta, spec.object_meta, "object_meta.")?;
                    insert(object, namespace, Value::Object(object_meta))?;
                } else {
                    validate_map(&JsonMap::new(), spec.object_meta, "object_meta.")?;
                }
            }
            match input_spec.namespace {
                Some(namespace) => {
                    insert(&mut root, namespace, input)?;
                }
                None => {
                    root = input.as_object().expect("validated object input").clone();
                }
            }
        }
    }
    if let Some(global_meta) = parts.global_meta {
        let namespace = spec.meta_namespace.ok_or_else(|| {
            Error::validation("global_meta", "metadata namespace is not described")
        })?;
        validate_map(&global_meta, spec.global_meta, "global_meta.")?;
        insert(&mut root, namespace, Value::Object(global_meta))?;
    } else {
        validate_map(&JsonMap::new(), spec.global_meta, "global_meta.")?;
    }
    let mut headers = config.request_headers(spec.auth);
    let body = if spec.method.query() {
        let mut pairs = Vec::new();
        for (name, value) in &root {
            let input_namespace = spec.input.and_then(|input| input.namespace);
            if input_namespace == Some(name.as_str())
                || (has_global_meta && spec.meta_namespace == Some(name.as_str()))
            {
                let object = value
                    .as_object()
                    .ok_or_else(|| Error::validation(name, "expected an object"))?;
                for (field, value) in object {
                    if has_object_meta
                        && input_namespace == Some(name.as_str())
                        && spec.meta_namespace == Some(field.as_str())
                    {
                        let metadata = value.as_object().ok_or_else(|| {
                            Error::validation("object_meta", "expected an object")
                        })?;
                        for (key, value) in metadata {
                            query_value(&mut pairs, &format!("{name}[{field}][{key}]"), value)?;
                        }
                    } else {
                        query_value(&mut pairs, &format!("{name}[{field}]"), value)?;
                    }
                }
            } else {
                query_value(&mut pairs, name, value)?;
            }
        }
        if !pairs.is_empty() {
            url.query_pairs_mut().extend_pairs(pairs);
        }
        None
    } else {
        headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
        Some(serde_json::to_vec(&root).map_err(|_| Error::Encode)?)
    };
    Ok(PreparedRequest {
        method: spec.method,
        url,
        headers,
        body,
    })
}

fn insert(map: &mut JsonMap, name: &str, value: Value) -> Result<(), Error> {
    if map.insert(name.to_owned(), value).is_some() {
        return Err(Error::configuration(
            "input and metadata namespaces collide",
        ));
    }
    Ok(())
}

fn query_value(pairs: &mut Vec<(String, String)>, name: &str, value: &Value) -> Result<(), Error> {
    let text = match value {
        Value::Null => String::new(),
        Value::String(value) => value.clone(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::Array(_) | Value::Object(_) => {
            return Err(Error::validation(
                name,
                "nested query values are unsupported",
            ));
        }
    };
    pairs.push((name.to_owned(), text));
    Ok(())
}

pub fn decode<T: DeserializeOwned, M: DeserializeOwned>(
    spec: &ActionSpec,
    response: RawResponse,
) -> Result<Response<T, M>, Error> {
    let status = response.status;
    let successful_http = (200..300).contains(&status);
    let envelope = serde_json::from_slice::<Value>(&response.body).ok();
    let object = envelope.as_ref().and_then(Value::as_object);
    if !successful_http {
        if let Some(object) = object
            && object.get("status") == Some(&Value::Bool(false))
            && let Some(error) = api_error(status, object)
        {
            return Err(error);
        }
        return Err(Error::Http { status });
    }
    let object =
        object.ok_or_else(|| Error::protocol(Some(status), "expected a JSON envelope object"))?;
    match object.get("status").and_then(Value::as_bool) {
        Some(false) => {
            return Err(api_error(status, object)
                .unwrap_or_else(|| Error::protocol(Some(status), "invalid failure envelope")));
        }
        Some(true) => (),
        None => {
            return Err(Error::protocol(
                Some(status),
                "missing boolean envelope status",
            ));
        }
    }
    let response = object
        .get("response")
        .and_then(Value::as_object)
        .ok_or_else(|| Error::protocol(Some(status), "missing response object"))?;
    let output = if let Some(output) = spec.output {
        let value = match response.get(output.namespace) {
            Some(value) => value.clone(),
            None if output.allow_empty_response && !output.layout.list() && response.is_empty() => {
                Value::Object(JsonMap::new())
            }
            None => {
                return Err(Error::protocol(
                    Some(status),
                    "missing declared output namespace",
                ));
            }
        };
        if output.layout.list() {
            if !value
                .as_array()
                .is_some_and(|items| items.iter().all(Value::is_object))
            {
                return Err(Error::Decode { status });
            }
        } else if !value.is_object() {
            return Err(Error::Decode { status });
        }
        value
    } else {
        if !response.is_empty() {
            return Err(Error::protocol(
                Some(status),
                "unexpected output for no-output action",
            ));
        }
        Value::Null
    };
    let metadata = match spec
        .meta_namespace
        .and_then(|namespace| response.get(namespace))
    {
        Some(Value::Object(map)) => Value::Object(map.clone()),
        Some(_) => return Err(Error::Decode { status }),
        None => Value::Object(JsonMap::new()),
    };
    Ok(Response {
        output: serde_json::from_value(output).map_err(|_| Error::Decode { status })?,
        meta: serde_json::from_value(metadata).map_err(|_| Error::Decode { status })?,
        http_status: status,
    })
}

fn api_error(status: u16, object: &JsonMap) -> Option<Error> {
    let message = match object.get("message") {
        None | Some(Value::Null) => None,
        Some(Value::String(message)) => Some(message.clone()),
        _ => return None,
    };
    let errors = match object.get("errors") {
        None | Some(Value::Null) => ValidationErrors::new(),
        Some(value) => serde_json::from_value::<ValidationErrors>(value.clone()).ok()?,
    };
    Some(Error::Api {
        status,
        message,
        errors,
    })
}

pub(crate) fn parse_base(base: &str) -> Result<Url, Error> {
    if base
        .bytes()
        .any(|byte| byte.is_ascii_control() || byte.is_ascii_whitespace() || byte == b'\\')
    {
        return Err(Error::configuration("invalid server mount URL"));
    }
    let mut parsed =
        Url::parse(base).map_err(|_| Error::configuration("invalid server mount URL"))?;
    if !matches!(parsed.scheme(), "https" | "http")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return Err(Error::configuration(
            "server mount must be an HTTP URL without credentials, query or fragment",
        ));
    }
    // Inspect the original string before Url can normalize dot segments away.
    let after_scheme = base
        .split_once("://")
        .ok_or_else(|| Error::configuration("invalid server mount URL"))?
        .1;
    let authority = after_scheme.split('/').next().unwrap_or_default();
    if authority.is_empty() || authority.contains('@') {
        return Err(Error::configuration("invalid server mount authority"));
    }
    if let Some(start) = after_scheme.find('/') {
        for segment in after_scheme[start..]
            .split('/')
            .filter(|segment| !segment.is_empty())
        {
            safe_literal_segment(segment)?;
        }
    }
    if !parsed.path().ends_with('/') {
        let path = format!("{}/", parsed.path());
        parsed.set_path(&path);
    }
    Ok(parsed)
}

fn action_url(base: &Url, path: &str, params: &BTreeMap<String, String>) -> Result<Url, Error> {
    if path.is_empty()
        || path.starts_with('/')
        || path.contains(['?', '#', '\\'])
        || path
            .bytes()
            .any(|byte| byte.is_ascii_control() || byte.is_ascii_whitespace())
    {
        return Err(Error::configuration(
            "action path must be a safe mount-relative template",
        ));
    }
    let mut used = BTreeSet::new();
    let mut url = base.clone();
    {
        let mut segments = url
            .path_segments_mut()
            .map_err(|_| Error::configuration("server URL cannot hold path segments"))?;
        segments.pop_if_empty();
        for segment in path.split('/') {
            if segment.is_empty() {
                return Err(Error::configuration(
                    "action path contains an empty segment",
                ));
            }
            if let Some(name) = segment
                .strip_prefix('{')
                .and_then(|value| value.strip_suffix('}'))
            {
                if name.is_empty() || name.contains(['{', '}']) {
                    return Err(Error::configuration("invalid path placeholder"));
                }
                let value = params
                    .get(name)
                    .ok_or_else(|| Error::validation(name, "path parameter is required"))?;
                if value.is_empty()
                    || value == "."
                    || value == ".."
                    || value.chars().any(char::is_control)
                {
                    return Err(Error::validation(name, "invalid path segment"));
                }
                used.insert(name);
                segments.push(value);
            } else {
                if segment.contains(['{', '}', ':']) {
                    return Err(Error::configuration("invalid action path template"));
                }
                segments.push(&safe_literal_segment(segment)?);
            }
        }
    }
    if params.keys().any(|name| !used.contains(name.as_str())) {
        return Err(Error::validation("path", "unexpected path parameter"));
    }
    // Constructing individual segments never changes the origin or mount.
    if url.origin() != base.origin() || !url.path().starts_with(base.path()) {
        return Err(Error::configuration("action path escapes the server mount"));
    }
    Ok(url)
}

fn safe_literal_segment(segment: &str) -> Result<String, Error> {
    let mut decoded = Vec::new();
    let mut bytes = segment.bytes();
    while let Some(byte) = bytes.next() {
        if byte == b'%' {
            let high = bytes.next().and_then(hex);
            let low = bytes.next().and_then(hex);
            match (high, low) {
                (Some(high), Some(low)) => decoded.push(high * 16 + low),
                _ => return Err(Error::configuration("invalid encoded path segment")),
            }
        } else {
            decoded.push(byte);
        }
    }
    let decoded = String::from_utf8(decoded)
        .map_err(|_| Error::configuration("invalid UTF-8 path segment"))?;
    if decoded == "."
        || decoded == ".."
        || decoded.contains(['/', '\\', '?', '#'])
        || decoded.chars().any(char::is_control)
    {
        return Err(Error::configuration("unsafe path segment"));
    }
    Ok(decoded)
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}
