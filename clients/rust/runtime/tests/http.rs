use std::{
    collections::BTreeMap,
    io::{Read, Write},
    net::TcpListener,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use haveapi_runtime_tests::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

static API: ApiSpec = ApiSpec {
    api_version: "7.0",
    protocol_major: 2,
    schema_sha256: "fixture",
    basic_auth: true,
    token_header: Some("X-Fixture-Token"),
    oauth2_header: Some("X-Fixture-OAuth"),
};
static SPEC: ActionSpec = ActionSpec {
    name: "echo",
    method: Method::Post,
    path: "v7.0/echo",
    input: Some(InputSpec {
        layout: Layout::Hash,
        namespace: Some("item"),
        parameters: &[ParameterSpec {
            name: "number",
            kind: ParameterKind::Float,
            required: true,
            nullable: false,
            protected: false,
        }],
    }),
    output: Some(OutputSpec {
        layout: Layout::Hash,
        namespace: "item",
        allow_empty_response: false,
    }),
    meta_namespace: Some("_meta"),
    global_meta: &[],
    object_meta: &[],
    auth: RequestAuth::Configured,
};

const METHOD_SPEC: ActionSpec = ActionSpec {
    name: "method_input",
    method: Method::Delete,
    path: "v7.0/method_input",
    input: Some(InputSpec {
        layout: Layout::Hash,
        namespace: Some("item"),
        parameters: &[
            ParameterSpec {
                name: "number",
                kind: ParameterKind::Integer,
                required: false,
                nullable: true,
                protected: false,
            },
            ParameterSpec {
                name: "flag",
                kind: ParameterKind::Boolean,
                required: false,
                nullable: false,
                protected: false,
            },
            ParameterSpec {
                name: "zero",
                kind: ParameterKind::Integer,
                required: false,
                nullable: false,
                protected: false,
            },
            ParameterSpec {
                name: "text",
                kind: ParameterKind::String,
                required: false,
                nullable: false,
                protected: false,
            },
            ParameterSpec {
                name: "custom",
                kind: ParameterKind::Custom,
                required: false,
                nullable: false,
                protected: false,
            },
            ParameterSpec {
                name: "omitted",
                kind: ParameterKind::String,
                required: false,
                nullable: false,
                protected: false,
            },
        ],
    }),
    global_meta: &[ParameterSpec {
        name: "count",
        kind: ParameterKind::Boolean,
        required: false,
        nullable: false,
        protected: false,
    }],
    object_meta: &[ParameterSpec {
        name: "includes",
        kind: ParameterKind::String,
        required: false,
        nullable: false,
        protected: false,
    }],
    output: Some(OutputSpec {
        layout: Layout::Hash,
        namespace: "item",
        allow_empty_response: false,
    }),
    meta_namespace: Some("_meta"),
    auth: RequestAuth::Configured,
};
static DELETE_SPEC: ActionSpec = METHOD_SPEC;
static GET_SPEC: ActionSpec = ActionSpec {
    method: Method::Get,
    ..METHOD_SPEC
};

#[derive(Default, Serialize)]
struct MethodInput {
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    number: InputValue<i64>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    flag: InputValue<bool>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    zero: InputValue<i64>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    text: InputValue<String>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    custom: InputValue<Value>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    omitted: InputValue<String>,
}

impl Validate for MethodInput {
    fn validate(&self) -> Result<(), Error> {
        self.number.validate()?;
        self.flag.validate()?;
        self.zero.validate()?;
        self.text.validate()?;
        self.custom.validate()?;
        self.omitted.validate()
    }
}

fn method_request<'a, C: Mode>(
    client: &'a Client<C>,
    spec: &'static ActionSpec,
) -> Request<'a, C, MethodInput, Output, JsonMap> {
    let input = MethodInput {
        number: InputValue::Null,
        flag: InputValue::Value(false),
        zero: InputValue::Value(0),
        text: InputValue::Value(String::new()),
        custom: if spec.method == Method::Delete {
            InputValue::Value(json!({"nested":[0,false,null]}))
        } else {
            InputValue::Unset
        },
        ..Default::default()
    };
    Request::new(client, spec, BTreeMap::new(), input)
        .global_meta(json!({"count":true}).as_object().unwrap().clone())
        .object_meta(
            json!({"includes":"owner,node"})
                .as_object()
                .unwrap()
                .clone(),
        )
}

#[derive(Serialize)]
struct Input {
    number: InputValue<f64>,
}
impl Validate for Input {
    fn validate(&self) -> Result<(), Error> {
        self.number.validate()
    }
}
#[derive(Deserialize)]
struct Output {
    value: Option<i64>,
}

struct Server {
    base: String,
    requests: Arc<Mutex<Vec<Vec<u8>>>>,
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}

impl Server {
    fn new(response: Vec<u8>, delay: Duration) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let base = format!("http://{}/mount", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let worker_stop = stop.clone();
        let worker_requests = requests.clone();
        let worker = thread::spawn(move || {
            while !worker_stop.load(Ordering::SeqCst) {
                let (mut stream, _) = match listener.accept() {
                    Ok(connection) => connection,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(2));
                        continue;
                    }
                    Err(error) => panic!("fixture listener: {error}"),
                };
                stream
                    .set_read_timeout(Some(Duration::from_secs(2)))
                    .unwrap();
                let mut request = Vec::new();
                let mut buffer = [0; 4096];
                loop {
                    let length = stream.read(&mut buffer).unwrap_or(0);
                    if length == 0 {
                        break;
                    }
                    request.extend_from_slice(&buffer[..length]);
                    if let Some(boundary) =
                        request.windows(4).position(|bytes| bytes == b"\r\n\r\n")
                    {
                        let headers = String::from_utf8_lossy(&request[..boundary]);
                        let content_length = headers
                            .lines()
                            .filter_map(|line| line.split_once(':'))
                            .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
                            .map(|(_, length)| length.trim().parse::<usize>().unwrap())
                            .unwrap_or(0);
                        if request.len() >= boundary + 4 + content_length {
                            break;
                        }
                    }
                }
                worker_requests.lock().unwrap().push(request);
                let until = Instant::now() + delay;
                while Instant::now() < until && !worker_stop.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_millis(2));
                }
                let _ = stream.write_all(&response);
            }
        });
        Self {
            base,
            requests,
            stop,
            worker: Some(worker),
        }
    }

    fn json(body: Value) -> Self {
        Self::new(
            http(200, &[], &serde_json::to_vec(&body).unwrap()),
            Duration::ZERO,
        )
    }
    fn count(&self) -> usize {
        self.requests.lock().unwrap().len()
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        self.worker.take().unwrap().join().unwrap();
    }
}

fn http(status: u16, headers: &[(&str, &str)], body: &[u8]) -> Vec<u8> {
    let mut response = format!(
        "HTTP/1.1 {status} Fixture\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    for (name, value) in headers {
        response.push_str(&format!("{name}: {value}\r\n"));
    }
    response.push_str("\r\n");
    [response.into_bytes(), body.to_vec()].concat()
}

fn success() -> Value {
    json!({"status":true,"response":{"item":{"value":42},"_meta":{"count":1}}})
}

fn assert_request(bytes: &[u8]) {
    let request = String::from_utf8_lossy(bytes);
    assert!(request.starts_with("POST /mount/v7.0/echo HTTP/1.1\r\n"));
    assert!(
        request
            .to_lowercase()
            .contains("x-fixture-token: token-secret\r\n")
    );
    let (_, body) = request.split_once("\r\n\r\n").unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(body).unwrap(),
        json!({"item":{"number":0.0}})
    );
}

fn assert_delete_and_get_requests(requests: &[Vec<u8>]) {
    assert_eq!(requests.len(), 2);
    let delete = String::from_utf8_lossy(&requests[0]);
    assert!(delete.starts_with("DELETE /mount/v7.0/method_input HTTP/1.1\r\n"));
    assert!(
        delete
            .to_ascii_lowercase()
            .contains("content-type: application/json\r\n")
    );
    let (_, body) = delete.split_once("\r\n\r\n").unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(body).unwrap(),
        json!({
            "item":{"number":null,"flag":false,"zero":0,"text":"","custom":{"nested":[0,false,null]},"_meta":{"includes":"owner,node"}},
            "_meta":{"count":true}
        })
    );

    let get = String::from_utf8_lossy(&requests[1]);
    let target = get
        .lines()
        .next()
        .unwrap()
        .strip_prefix("GET ")
        .unwrap()
        .strip_suffix(" HTTP/1.1")
        .unwrap();
    let url = url::Url::parse(&format!("http://fixture.test{target}")).unwrap();
    assert_eq!(url.path(), "/mount/v7.0/method_input");
    let query: BTreeMap<_, _> = url.query_pairs().into_owned().collect();
    assert_eq!(
        query,
        BTreeMap::from([
            ("item[number]".into(), "".into()),
            ("item[flag]".into(), "false".into()),
            ("item[zero]".into(), "0".into()),
            ("item[text]".into(), "".into()),
            ("item[_meta][includes]".into(), "owner,node".into()),
            ("_meta[count]".into(), "true".into()),
        ])
    );
    assert_eq!(get.split_once("\r\n\r\n").unwrap().1, "");
}

#[tokio::test]
async fn async_delete_uses_json_body_and_get_keeps_query_input() {
    let server = Server::json(success());
    let client = ClientBuilder::<AsyncTransport>::new(&server.base, &API)
        .build()
        .unwrap();
    for spec in [&DELETE_SPEC, &GET_SPEC] {
        assert_eq!(
            method_request(&client, spec)
                .send()
                .await
                .unwrap()
                .output
                .value,
            Some(42)
        );
    }
    assert_delete_and_get_requests(&server.requests.lock().unwrap());
}

#[cfg(feature = "blocking")]
#[test]
fn blocking_delete_uses_json_body_and_get_keeps_query_input() {
    let server = Server::json(success());
    let client = ClientBuilder::<BlockingTransport>::new(&server.base, &API)
        .build()
        .unwrap();
    for spec in [&DELETE_SPEC, &GET_SPEC] {
        assert_eq!(
            method_request(&client, spec).send().unwrap().output.value,
            Some(42)
        );
    }
    drop(client);
    assert_delete_and_get_requests(&server.requests.lock().unwrap());
}

#[tokio::test]
async fn async_adapter_reuses_client_and_validates_before_serialization() {
    let server = Server::json(success());
    let client = ClientBuilder::<AsyncTransport>::new(&server.base, &API)
        .token("token-secret")
        .build()
        .unwrap();
    for _ in 0..2 {
        let response = Request::<_, _, Output, JsonMap>::new(
            &client,
            &SPEC,
            BTreeMap::new(),
            Input {
                number: InputValue::Value(0.0),
            },
        )
        .send()
        .await
        .unwrap();
        assert_eq!(response.output.value, Some(42));
        assert_eq!(response.meta["count"], 1);
    }
    for number in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let error = Request::<_, _, Output, JsonMap>::new(
            &client,
            &SPEC,
            BTreeMap::new(),
            Input {
                number: InputValue::Value(number),
            },
        )
        .send()
        .await
        .unwrap_err();
        assert!(matches!(error, Error::Validation { .. }));
    }
    assert_eq!(server.count(), 2);
    for request in server.requests.lock().unwrap().iter() {
        assert_request(request);
    }
}

#[tokio::test]
async fn redirects_are_not_followed_and_errors_do_not_expose_bodies() {
    let target = Server::json(success());
    let source = Server::new(
        http(302, &[("Location", &target.base)], b"secret-redirect-body"),
        Duration::ZERO,
    );
    let client = ClientBuilder::<AsyncTransport>::new(&source.base, &API)
        .token("token-secret")
        .build()
        .unwrap();
    let error = Request::<_, _, Output, JsonMap>::new(
        &client,
        &SPEC,
        BTreeMap::new(),
        Input {
            number: InputValue::Value(0.0),
        },
    )
    .send()
    .await
    .unwrap_err();
    assert!(matches!(error, Error::Http { status: 302 }));
    assert!(!format!("{error} {error:?}").contains("secret"));
    assert_eq!(source.count(), 1);
    assert_eq!(target.count(), 0);
}

#[tokio::test]
async fn async_size_limits_cover_declared_and_chunked_bodies() {
    for response in [http(200, &[], b"123456789"), b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n9\r\n123456789\r\n0\r\n\r\n".to_vec()] {
        let server = Server::new(response, Duration::ZERO);
        let client = ClientBuilder::<AsyncTransport>::new(&server.base, &API).max_response_bytes(8).build().unwrap();
        let error = Request::<_, _, Output, JsonMap>::new(&client, &SPEC, BTreeMap::new(), Input { number: InputValue::Value(0.0) }).send().await.unwrap_err();
        assert!(matches!(error, Error::ResponseTooLarge { limit:8 }));
        assert_eq!(server.count(), 1);
    }
}

#[tokio::test]
async fn async_deadline_is_typed_and_does_not_retry() {
    let server = Server::new(
        http(200, &[], &serde_json::to_vec(&success()).unwrap()),
        Duration::from_millis(200),
    );
    let client = ClientBuilder::<AsyncTransport>::new(&server.base, &API)
        .timeout(Duration::from_millis(50))
        .build()
        .unwrap();
    let error = Request::<_, _, Output, JsonMap>::new(
        &client,
        &SPEC,
        BTreeMap::new(),
        Input {
            number: InputValue::Value(0.0),
        },
    )
    .send()
    .await
    .unwrap_err();
    assert!(error.is_timeout());
    assert_eq!(server.count(), 1);
    assert!(!format!("{error:?}").contains(&server.base));
}

#[cfg(feature = "blocking")]
#[test]
fn blocking_adapter_runs_without_an_application_runtime() {
    let server = Server::json(success());
    let client = ClientBuilder::<BlockingTransport>::new(&server.base, &API)
        .token("token-secret")
        .build()
        .unwrap();
    for _ in 0..2 {
        let response = Request::<_, _, Output, JsonMap>::new(
            &client,
            &SPEC,
            BTreeMap::new(),
            Input {
                number: InputValue::Value(0.0),
            },
        )
        .send()
        .unwrap();
        assert_eq!(response.output.value, Some(42));
        assert_eq!(response.meta["count"], 1);
    }
    drop(client);
    assert_eq!(server.count(), 2);
    for request in server.requests.lock().unwrap().iter() {
        assert_request(request);
    }
}

#[cfg(feature = "blocking")]
#[test]
fn blocking_adapter_has_matching_redirect_size_and_timeout_policy() {
    let target = Server::json(success());
    let server = Server::new(
        http(307, &[("Location", &target.base)], b"secret-body"),
        Duration::ZERO,
    );
    let client = ClientBuilder::<BlockingTransport>::new(&server.base, &API)
        .token("secret-token")
        .build()
        .unwrap();
    let error = Request::<_, _, Output, JsonMap>::new(
        &client,
        &SPEC,
        BTreeMap::new(),
        Input {
            number: InputValue::Value(0.0),
        },
    )
    .send()
    .unwrap_err();
    assert!(matches!(error, Error::Http { status: 307 }));
    assert_eq!(server.count(), 1);
    assert_eq!(target.count(), 0);
    drop(client);

    for response in [http(200, &[], b"123456789"), b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n9\r\n123456789\r\n0\r\n\r\n".to_vec()] {
        let server = Server::new(response, Duration::ZERO);
        let client = ClientBuilder::<BlockingTransport>::new(&server.base, &API).max_response_bytes(8).build().unwrap();
        assert!(matches!(Request::<_, _, Output, JsonMap>::new(&client, &SPEC, BTreeMap::new(), Input { number: InputValue::Value(0.0) }).send(), Err(Error::ResponseTooLarge { limit:8 })));
    }
    let server = Server::new(
        http(200, &[], &serde_json::to_vec(&success()).unwrap()),
        Duration::from_millis(200),
    );
    let client = ClientBuilder::<BlockingTransport>::new(&server.base, &API)
        .timeout(Duration::from_millis(50))
        .build()
        .unwrap();
    let error = Request::<_, _, Output, JsonMap>::new(
        &client,
        &SPEC,
        BTreeMap::new(),
        Input {
            number: InputValue::Value(0.0),
        },
    )
    .send()
    .unwrap_err();
    assert!(error.is_timeout());
    assert_eq!(server.count(), 1);
}

#[cfg(feature = "blocking")]
async fn complete_blocking_lifecycle() {
    let server = Server::json(success());
    let base = server.base.clone();
    let value = tokio::task::spawn_blocking(move || {
        let client = ClientBuilder::<BlockingTransport>::new(base, &API)
            .build()
            .unwrap();
        Request::<_, _, Output, JsonMap>::new(
            &client,
            &SPEC,
            BTreeMap::new(),
            Input {
                number: InputValue::Value(0.0),
            },
        )
        .send()
        .unwrap()
        .output
        .value
    })
    .await
    .unwrap();
    assert_eq!(value, Some(42));
    assert_eq!(server.count(), 1);
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "current_thread")]
async fn spawn_blocking_owns_lifecycle_on_current_thread_runtime() {
    complete_blocking_lifecycle().await;
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn spawn_blocking_owns_lifecycle_on_multi_thread_runtime() {
    complete_blocking_lifecycle().await;
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "current_thread")]
async fn aborting_started_blocking_work_does_not_cancel_the_request() {
    let server = Server::new(
        http(200, &[], &serde_json::to_vec(&success()).unwrap()),
        Duration::from_millis(100),
    );
    let base = server.base.clone();
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let (finished_tx, finished_rx) = tokio::sync::oneshot::channel();
    let task = tokio::task::spawn_blocking(move || {
        let client = ClientBuilder::<BlockingTransport>::new(base, &API)
            .timeout(Duration::from_secs(2))
            .build()
            .unwrap();
        started_tx.send(()).unwrap();
        let value = Request::<_, _, Output, JsonMap>::new(
            &client,
            &SPEC,
            BTreeMap::new(),
            Input {
                number: InputValue::Value(0.0),
            },
        )
        .send()
        .unwrap()
        .output
        .value;
        drop(client);
        finished_tx.send(value).unwrap();
    });
    started_rx.await.unwrap();
    task.abort();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(3), finished_rx)
            .await
            .unwrap()
            .unwrap(),
        Some(42)
    );
    assert_eq!(server.count(), 1);
}
