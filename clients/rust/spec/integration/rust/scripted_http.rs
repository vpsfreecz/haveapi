use haveapi_rust_fixture::{Client, Error};
use serde_json::{Value, json};
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc::{Receiver, channel};
use std::thread::{self, JoinHandle};
use std::time::Duration;

struct ScriptedServer {
    base: String,
    requests: Receiver<Vec<u8>>,
    worker: Option<JoinHandle<()>>,
}

impl ScriptedServer {
    fn new(status: u16, headers: &[(&str, &str)], body: &[u8]) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let base = format!("http://{}/", listener.local_addr().unwrap());
        let mut response = format!(
            "HTTP/1.1 {status} Fixture\r\nContent-Length: {}\r\nConnection: close\r\n",
            body.len()
        );
        for (name, value) in headers {
            response.push_str(&format!("{name}: {value}\r\n"));
        }
        response.push_str("\r\n");
        let mut response = response.into_bytes();
        response.extend_from_slice(body);
        let (sender, requests) = channel();
        let worker = thread::spawn(move || {
            let deadline = std::time::Instant::now() + Duration::from_secs(3);
            let mut stream = loop {
                match listener.accept() {
                    Ok((stream, _)) => break stream,
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        if std::time::Instant::now() >= deadline {
                            return;
                        }
                        thread::sleep(Duration::from_millis(5));
                    }
                    Err(e) => panic!("fixture accept failed: {e}"),
                }
            };
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            let mut request = Vec::new();
            let mut buffer = [0; 4096];
            loop {
                let count = stream.read(&mut buffer).unwrap();
                assert!(count > 0, "request must contain complete headers/body");
                request.extend_from_slice(&buffer[..count]);
                if let Some(end) = request.windows(4).position(|s| s == b"\r\n\r\n") {
                    let headers = String::from_utf8_lossy(&request[..end]);
                    let length = headers
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length: ")
                                .map(|length| length.parse::<usize>().unwrap())
                        })
                        .unwrap_or(0);
                    if request.len() >= end + 4 + length {
                        break;
                    }
                }
            }
            sender.send(request).unwrap();
            let _ = stream.write_all(&response);
        });
        Self {
            base,
            requests,
            worker: Some(worker),
        }
    }

    fn json(status: u16, body: Value) -> Self {
        Self::new(
            status,
            &[("Content-Type", "application/json")],
            &serde_json::to_vec(&body).unwrap(),
        )
    }

    fn request(&self) -> Vec<u8> {
        self.requests.recv_timeout(Duration::from_secs(4)).unwrap()
    }
}

impl Drop for ScriptedServer {
    fn drop(&mut self) {
        self.worker.take().unwrap().join().unwrap();
    }
}

fn success(output: Value) -> Value {
    json!({"status": true, "response": {"rust_fixture": output}})
}

macro_rules! async_response {
    ($request:expr) => {
        $request.send().await
    };
}
#[cfg(feature = "blocking")]
macro_rules! blocking_response {
    ($request:expr) => {
        $request.send()
    };
}

macro_rules! synthetic_cases {
    ($client_type:ty, $send:ident) => {{
        for association in [
            json!({"id": 7, "name": "partial"}),
            json!({"id": 7, "name": "expanded", "extra": true, "_meta": {"resolved": true}}),
            json!({"_meta": {"resolved": false, "authorized": false}}),
        ] {
            let server = ScriptedServer::json(200, success(json!({"project": association})));
            let api = <$client_type>::builder(&server.base).build().unwrap();
            let response = $send!(api.rust_fixture().association()).unwrap();
            assert_eq!(response.output.project.unwrap().as_map(), association.as_object().unwrap());
        }
        // Valid optional fields cannot hide an invalid envelope or namespace.
        for (status, body) in [
            (200, json!({"response": {"rust_fixture": {}}})),
            (200, json!({"status": "true", "response": {"rust_fixture": {}}})),
            (200, json!({"status": true, "response": {}})),
            (200, json!({"status": true, "response": {"wrong": {}}})),
            (200, json!({"status": true, "response": null})),
            (200, json!({"status": true, "response": []})),
        ] {
            let server = ScriptedServer::json(status, body);
            let api = <$client_type>::builder(&server.base).build().unwrap();
            assert!(matches!($send!(api.rust_fixture().association()), Err(Error::Protocol { .. })));
        }
        let server = ScriptedServer::json(200, success(json!({"project": 5})));
        let api = <$client_type>::builder(&server.base).build().unwrap();
        assert!(matches!($send!(api.rust_fixture().association()), Err(Error::Decode { .. })));

        for status in [200, 422] {
            let secret = "body-and-message-secret";
            let server = ScriptedServer::json(status, json!({
                "status": false, "message": secret,
                "errors": {"value": [secret]}, "response": null
            }));
            let api = <$client_type>::builder(&server.base).build().unwrap();
            let error = $send!(api.rust_fixture().association()).err().unwrap();
            assert!(matches!(error, Error::Api { .. }));
            assert_eq!(error.http_status(), Some(status));
            assert!(!format!("{error:?} {error}").contains(secret));
        }
        for body in [b"".as_slice(), b"<html>upstream secret</html>", b"{malformed"] {
            let server = ScriptedServer::new(502, &[], body);
            let api = <$client_type>::builder(&server.base).build().unwrap();
            let error = $send!(api.rust_fixture().association()).err().unwrap();
            assert_eq!(error.http_status(), Some(502));
            assert!(!format!("{error:?} {error}").contains("upstream secret"));
        }
        for (status, body) in [(200, b"".as_slice()), (200, b"{broken"), (204, b"")] {
            let server = ScriptedServer::new(status, &[], body);
            let api = <$client_type>::builder(&server.base).build().unwrap();
            assert!($send!(api.rust_fixture().association()).is_err());
        }
        let server = ScriptedServer::json(503, success(json!({"project": {"id": 1}})));
        let api = <$client_type>::builder(&server.base).build().unwrap();
        assert_eq!($send!(api.rust_fixture().association()).err().unwrap().http_status(), Some(503));

        // Clarification 2: narrowly accept empty-object output, not arbitrary
        // missing namespaces, null/scalars, nonempty wrong keys, or lists.
        for response in [json!({}), json!({"token": {}})] {
            let server = ScriptedServer::json(200, json!({"status": true, "response": response}));
            let api = <$client_type>::builder(&server.base).token("fixture-secret").build().unwrap();
            $send!(api.authentication__token__token().revoke()).unwrap();
        }
        for response in [json!(null), json!([]), json!(1), json!({"wrong": {}})] {
            let server = ScriptedServer::json(200, json!({"status": true, "response": response}));
            let api = <$client_type>::builder(&server.base).token("fixture-secret").build().unwrap();
            assert!($send!(api.authentication__token__token().revoke()).is_err());
        }
        let server = ScriptedServer::json(200, json!({"status": true, "response": {}}));
        let api = <$client_type>::builder(&server.base).build().unwrap();
        assert!($send!(api.project().index()).is_err());

        // Check the actual bytes produced by a generated action, including
        // body namespaces, empty/false/zero values and absence of other fields.
        let server = ScriptedServer::json(200, success(json!({"received": {}})));
        let api = <$client_type>::builder(&server.base).basic_auth("admin", "pass").build().unwrap();
        $send!(api.rust_fixture().echo().number(0).flag(false).text("")).unwrap();
        let bytes = server.request();
        let split = bytes.windows(4).position(|s| s == b"\r\n\r\n").unwrap();
        let headers = String::from_utf8_lossy(&bytes[..split]).to_ascii_lowercase();
        assert!(headers.contains("accept: application/json"));
        // Case-insensitive header names; the credential value itself is tested
        // by the real Basic provider, not by a copied Base64 implementation.
        assert!(headers.contains("authorization: basic "));
        assert_eq!(serde_json::from_slice::<Value>(&bytes[split + 4..]).unwrap(),
            json!({"rust_fixture": {"number": 0, "flag": false, "text": ""}}));

        let server = ScriptedServer::json(200, success(json!({"project": {"id": 1}})));
        let api = <$client_type>::builder(&server.base).token("existing-token-secret").build().unwrap();
        assert!(!format!("{api:?}").contains("existing-token-secret"));
        $send!(api.rust_fixture().association()).unwrap();
        let bytes = server.request();
        let headers = String::from_utf8_lossy(&bytes).to_ascii_lowercase();
        assert!(headers.contains("x-haveapi-auth-token: existing-token-secret\r\n"));
        assert!(!headers.contains("bearer"));

        let server = ScriptedServer::json(200, success(json!({"project": {"id": 1}})));
        let api = <$client_type>::builder(&server.base).oauth2_token("existing-oauth-secret").build().unwrap();
        $send!(api.rust_fixture().association()).unwrap();
        let bytes = server.request();
        assert!(String::from_utf8_lossy(&bytes).to_ascii_lowercase()
            .contains("x-haveapi-oauth2-token: existing-oauth-secret\r\n"));

        let server = ScriptedServer::json(200, json!({"status": true, "response": {"token": {
            "token": "final-fixture-token", "complete": true
        }}}));
        let api = <$client_type>::builder(&server.base).token("configured-token-secret").build().unwrap();
        let request = api.authentication__token__token().request()
            .user("user").password("wire-password-secret").lifetime("fixed");
        assert!(!format!("{request:?}").contains("wire-password-secret"));
        $send!(request).unwrap();
        let bytes = server.request();
        let headers = String::from_utf8_lossy(&bytes).to_ascii_lowercase();
        assert!(!headers.contains("x-haveapi-auth-token:"));
        assert!(!headers.contains("configured-token-secret"));

        let server = ScriptedServer::json(200, success(json!({"received": {}})));
        let api = <$client_type>::builder(&server.base).build().unwrap();
        $send!(api.rust_fixture().query().number_null().flag(false)).unwrap();
        let bytes = server.request();
        let line = String::from_utf8_lossy(&bytes).lines().next().unwrap().to_owned();
        let target = line.split_whitespace().nth(1).unwrap();
        let url = url::Url::parse(&format!("{}{}", server.base.trim_end_matches('/'), target)).unwrap();
        let query: std::collections::BTreeMap<_, _> = url.query_pairs().into_owned().collect();
        assert_eq!(query.get("rust_fixture[number]").map(String::as_str), Some(""));
        assert_eq!(query.get("rust_fixture[flag]").map(String::as_str), Some("false"));
        assert!(!query.contains_key("rust_fixture[text]"));

        let server = ScriptedServer::json(200, json!({"status": true, "response": {"task": {}}}));
        let api = <$client_type>::builder(&server.base).build().unwrap();
        $send!(api.project__task("parent/with space").show("child?&")).unwrap();
        let bytes = server.request();
        let line = String::from_utf8_lossy(&bytes).lines().next().unwrap().to_owned();
        let target = line.split_whitespace().nth(1).unwrap();
        // '&' is legal path data; '?' and '/' must remain encoded within IDs.
        assert_eq!(target, "/v1.0/projects/parent%2Fwith%20space/tasks/child%3F&");
        let url = url::Url::parse(&format!("{}{}", server.base.trim_end_matches('/'), target)).unwrap();
        assert_eq!(url.path(), target);
        assert!(url.query().is_none());
        assert!(url.fragment().is_none());

        let sink = TcpListener::bind("127.0.0.1:0").unwrap();
        sink.set_nonblocking(true).unwrap();
        let location = format!("http://{}/credential-sink", sink.local_addr().unwrap());
        let server = ScriptedServer::new(302, &[("Location", &location)], b"");
        let api = <$client_type>::builder(&server.base).token("redirect-secret").build().unwrap();
        let error = $send!(api.rust_fixture().association()).err().unwrap();
        assert_eq!(error.http_status(), Some(302));
        assert!(matches!(sink.accept(), Err(e) if e.kind() == std::io::ErrorKind::WouldBlock));

        let server = ScriptedServer::new(200, &[], &vec![b'x'; 1024]);
        let api = <$client_type>::builder(&server.base).max_response_bytes(128).build().unwrap();
        assert!(matches!($send!(api.rust_fixture().association()), Err(Error::ResponseTooLarge { .. })));
    }};
}

#[tokio::test]
async fn generated_async_against_scripted_http() {
    synthetic_cases!(Client, async_response);
}

#[cfg(feature = "blocking")]
#[test]
fn generated_blocking_against_scripted_http() {
    synthetic_cases!(haveapi_rust_fixture::blocking::Client, blocking_response);
}
