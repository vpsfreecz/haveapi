use std::collections::BTreeMap;

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
const BASE: ActionSpec = ActionSpec {
    name: "fixture",
    method: Method::Post,
    path: "v7.0/items",
    input: None,
    output: None,
    meta_namespace: Some("_meta"),
    global_meta: &[],
    object_meta: &[],
    auth: RequestAuth::Configured,
};
const INPUT: &[ParameterSpec] = &[
    ParameterSpec {
        name: "name",
        kind: ParameterKind::String,
        required: true,
        nullable: false,
        protected: false,
    },
    ParameterSpec {
        name: "count",
        kind: ParameterKind::Integer,
        required: false,
        nullable: false,
        protected: false,
    },
    ParameterSpec {
        name: "enabled",
        kind: ParameterKind::Boolean,
        required: false,
        nullable: false,
        protected: false,
    },
    ParameterSpec {
        name: "clear",
        kind: ParameterKind::Integer,
        required: false,
        nullable: true,
        protected: false,
    },
    ParameterSpec {
        name: "custom",
        kind: ParameterKind::Custom,
        required: false,
        nullable: true,
        protected: false,
    },
    ParameterSpec {
        name: "when",
        kind: ParameterKind::Datetime,
        required: false,
        nullable: false,
        protected: false,
    },
    ParameterSpec {
        name: "resource",
        kind: ParameterKind::Resource,
        required: false,
        nullable: false,
        protected: false,
    },
];
const META: &[ParameterSpec] = &[ParameterSpec {
    name: "count",
    kind: ParameterKind::Boolean,
    required: false,
    nullable: false,
    protected: false,
}];
const OBJECT_META: &[ParameterSpec] = &[ParameterSpec {
    name: "includes",
    kind: ParameterKind::String,
    required: false,
    nullable: false,
    protected: false,
}];

fn client() -> Client<AsyncTransport> {
    ClientBuilder::<AsyncTransport>::new("https://example.test/mount", &API)
        .build()
        .unwrap()
}

fn spec() -> ActionSpec {
    ActionSpec {
        input: Some(InputSpec {
            layout: Layout::Hash,
            namespace: Some("item"),
            parameters: INPUT,
        }),
        ..BASE
    }
}

fn parts(input: Value) -> RequestParts {
    RequestParts {
        input: Some(input),
        ..Default::default()
    }
}
fn map(value: Value) -> JsonMap {
    value.as_object().unwrap().clone()
}
fn raw(status: u16, body: Value) -> RawResponse {
    RawResponse {
        status,
        body: serde_json::to_vec(&body).unwrap(),
    }
}

#[derive(Default, Serialize)]
struct TriState {
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    name: InputValue<String>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    count: InputValue<i64>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    enabled: InputValue<bool>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    clear: InputValue<i64>,
    #[serde(skip_serializing_if = "InputValue::is_unset")]
    custom: InputValue<Value>,
}

#[test]
fn omission_null_and_falsy_values_stay_distinct() {
    let input = TriState {
        name: InputValue::Value(String::new()),
        count: InputValue::Value(0),
        enabled: InputValue::Value(false),
        clear: InputValue::Null,
        ..Default::default()
    };
    let serialized = serde_json::to_value(input).unwrap();
    assert_eq!(
        serialized,
        json!({"name":"", "count":0, "enabled":false, "clear":null})
    );
    let request = prepare(client().config(), &spec(), parts(serialized)).unwrap();
    assert_eq!(
        serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
        json!({"item":{"name":"", "count":0, "enabled":false, "clear":null}})
    );
    assert_eq!(request.headers["accept"], "application/json");
    assert_eq!(request.headers["content-type"], "application/json");
}

#[test]
fn validation_rejects_missing_null_wrong_types_and_limits() {
    for invalid in [
        json!({}),
        json!({"name":null}),
        json!({"name":false}),
        json!({"name":"ok", "count":1.5}),
        json!({"name":"ok", "count":9223372036854775808u64}),
        json!({"name":"ok", "enabled":0}),
        json!({"name":"ok", "resource":-1}),
        json!({"name":"ok", "when":"2020-02-30"}),
        json!({"name":"ok", "count":null}),
        json!({"name":"ok", "unknown":1}),
    ] {
        let error = prepare(client().config(), &spec(), parts(invalid)).unwrap_err();
        assert!(matches!(error, Error::Validation { .. }));
        assert!(!error.validation_errors().unwrap().is_empty());
    }
    for valid in [
        json!({"name":"ok", "count":i64::MIN}),
        json!({"name":"ok", "count":i64::MAX}),
        json!({"name":"ok", "resource":0}),
        json!({"name":"ok", "resource":i64::MAX}),
        json!({"name":"ok", "custom":null}),
        json!({"name":"ok", "custom":{"nested":[1,false,null]}}),
    ] {
        prepare(client().config(), &spec(), parts(valid)).unwrap();
    }
}

#[test]
fn explicit_metadata_and_query_encoding_share_namespaces() {
    let spec = ActionSpec {
        method: Method::Get,
        global_meta: META,
        object_meta: OBJECT_META,
        ..spec()
    };
    let mut parts = parts(json!({"name":"", "count":0, "enabled":false, "clear":null}));
    parts.global_meta = Some(map(json!({"count":true})));
    parts.object_meta = Some(map(json!({"includes":"owner,node"})));
    let request = prepare(client().config(), &spec, parts).unwrap();
    assert!(request.body.is_none());
    let query: BTreeMap<_, _> = request.url.query_pairs().into_owned().collect();
    assert_eq!(query["item[name]"], "");
    assert_eq!(query["item[clear]"], "");
    assert_eq!(query["item[count]"], "0");
    assert_eq!(query["item[enabled]"], "false");
    assert_eq!(query["_meta[count]"], "true");
    assert_eq!(query["item[_meta][includes]"], "owner,node");
}

#[test]
fn body_methods_preserve_input_and_metadata_without_query_parameters() {
    let client = client();
    for method in [Method::Delete, Method::Post, Method::Put, Method::Patch] {
        let spec = ActionSpec {
            method,
            global_meta: META,
            object_meta: OBJECT_META,
            ..spec()
        };
        for custom in [
            InputValue::Unset,
            InputValue::Value(json!({"nested":[1,false,null]})),
            InputValue::Value(json!([1, 2])),
        ] {
            let input = TriState {
                name: InputValue::Value(String::new()),
                count: InputValue::Value(0),
                enabled: InputValue::Value(false),
                clear: InputValue::Null,
                custom,
            };
            let mut expected_input = serde_json::to_value(input).unwrap();
            let mut parts = parts(expected_input.clone());
            parts.global_meta = Some(map(json!({"count":true})));
            parts.object_meta = Some(map(json!({"includes":"owner,node"})));
            expected_input
                .as_object_mut()
                .unwrap()
                .insert("_meta".into(), json!({"includes":"owner,node"}));
            let request = prepare(client.config(), &spec, parts).unwrap();
            assert_eq!(request.method, method);
            assert!(request.url.query().is_none(), "{method:?}");
            assert_eq!(request.headers["content-type"], "application/json");
            assert_eq!(
                serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
                json!({"item":expected_input,"_meta":{"count":true}})
            );
        }
        let empty = ActionSpec { method, ..BASE };
        let request = prepare(client.config(), &empty, RequestParts::default()).unwrap();
        assert!(request.url.query().is_none());
        assert_eq!(request.headers["content-type"], "application/json");
        assert_eq!(request.body.unwrap(), b"{}");
    }
}

#[test]
fn delete_supports_unnamespaced_objects_and_named_lists_in_json() {
    let client = client();
    let mut spec = ActionSpec {
        method: Method::Delete,
        global_meta: META,
        ..spec()
    };
    spec.input.as_mut().unwrap().namespace = None;
    let mut parts = parts(json!({"name":"", "clear":null, "custom":{"nested":[false,0,null]}}));
    parts.global_meta = Some(map(json!({"count":false})));
    let request = prepare(client.config(), &spec, parts).unwrap();
    assert!(request.url.query().is_none());
    assert_eq!(request.headers["content-type"], "application/json");
    assert_eq!(
        serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
        json!({"name":"", "clear":null, "custom":{"nested":[false,0,null]}, "_meta":{"count":false}})
    );

    spec.input.as_mut().unwrap().layout = Layout::HashList;
    spec.input.as_mut().unwrap().namespace = Some("item");
    let list = json!([{"name":"one","clear":null,"enabled":false,"custom":[0,null]}, {"name":"two","count":0}]);
    let mut parts = RequestParts {
        input: Some(list.clone()),
        global_meta: Some(map(json!({"count":true}))),
        ..Default::default()
    };
    let request = prepare(client.config(), &spec, parts).unwrap();
    assert!(request.url.query().is_none());
    assert_eq!(request.headers["content-type"], "application/json");
    assert_eq!(
        serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
        json!({"item":list,"_meta":{"count":true}})
    );
    spec.input.as_mut().unwrap().namespace = None;
    parts = RequestParts {
        input: Some(json!([])),
        ..Default::default()
    };
    assert!(prepare(client.config(), &spec, parts).is_err());
}

#[test]
fn query_rejects_nested_custom_but_json_lists_are_supported() {
    let client = client();
    for namespace in [None, Some("item")] {
        let mut spec = spec();
        spec.method = Method::Get;
        spec.input.as_mut().unwrap().namespace = namespace;
        for custom in [json!({"nested":true}), json!([1, 2])] {
            assert!(matches!(
                prepare(
                    client.config(),
                    &spec,
                    parts(json!({"name":"ok", "custom":custom}))
                ),
                Err(Error::Validation { .. })
            ));
        }
        let request = prepare(client.config(), &spec, parts(json!({"name":"ok"}))).unwrap();
        assert_eq!(
            request.url.query_pairs().next().unwrap().0,
            if namespace.is_some() {
                "item[name]"
            } else {
                "name"
            }
        );
    }
    let mut spec = spec();
    spec.input.as_mut().unwrap().layout = Layout::HashList;
    let request = prepare(
        client.config(),
        &spec,
        parts(json!([{"name":"one"}, {"name":"two"}])),
    )
    .unwrap();
    assert_eq!(
        serde_json::from_slice::<Value>(request.body.as_ref().unwrap()).unwrap(),
        json!({"item":[{"name":"one"},{"name":"two"}]})
    );
    spec.method = Method::Get;
    assert!(prepare(client.config(), &spec, parts(json!([]))).is_err());
    spec.method = Method::Post;
    spec.input.as_mut().unwrap().namespace = None;
    assert!(prepare(client.config(), &spec, parts(json!([]))).is_err());
}

#[test]
fn no_input_and_metadata_disabled_are_explicit() {
    let client = client();
    let request = prepare(client.config(), &BASE, RequestParts::default()).unwrap();
    assert_eq!(request.body.unwrap(), b"{}");
    assert!(prepare(client.config(), &BASE, parts(json!({}))).is_err());
    let spec = ActionSpec {
        meta_namespace: None,
        ..BASE
    };
    let parts = RequestParts {
        global_meta: Some(JsonMap::new()),
        ..Default::default()
    };
    assert!(prepare(client.config(), &spec, parts).is_err());
}

#[test]
fn custom_query_fields_named_like_metadata_do_not_gain_nesting() {
    const PARAMS: &[ParameterSpec] = &[ParameterSpec {
        name: "_meta",
        kind: ParameterKind::Custom,
        required: false,
        nullable: false,
        protected: false,
    }];
    let client = client();
    for namespace in [None, Some("item")] {
        let spec = ActionSpec {
            method: Method::Get,
            input: Some(InputSpec {
                layout: Layout::Hash,
                namespace,
                parameters: PARAMS,
            }),
            ..BASE
        };
        assert!(matches!(
            prepare(
                client.config(),
                &spec,
                parts(json!({"_meta":{"count":true}}))
            ),
            Err(Error::Validation { .. })
        ));
    }
}

#[test]
fn path_segments_preserve_mount_repeated_placeholders_and_global_auth() {
    let client = client();
    let spec = ActionSpec {
        path: "v7.0/items/{id}/child/{id}",
        ..BASE
    };
    let mut parts = RequestParts::default();
    parts.path_params.insert("id".into(), "a/b ?#% ü".into());
    let request = prepare(client.config(), &spec, parts).unwrap();
    assert_eq!(
        request.url.as_str(),
        "https://example.test/mount/v7.0/items/a%2Fb%20%3F%23%25%20%C3%BC/child/a%2Fb%20%3F%23%25%20%C3%BC"
    );
    let spec = ActionSpec {
        path: "_auth/token/request",
        ..BASE
    };
    assert_eq!(
        prepare(client.config(), &spec, RequestParts::default())
            .unwrap()
            .url
            .path(),
        "/mount/_auth/token/request"
    );
}

#[test]
fn unsafe_paths_and_bases_fail_before_dispatch() {
    let client = client();
    for path in [
        "",
        "/v7.0/items",
        "//evil.test/path",
        "https://evil.test/path",
        "../path",
        "v7.0/%2e%2e/path",
        "v7.0/%2fpath",
        "v7.0/%5cpath",
        "v7.0/path?secret=yes",
        "v7.0/path#fragment",
        "v7.0/path\\x",
        "v7.0/{missing}",
        "v7.0//path",
        "v7.0/%00",
    ] {
        assert!(
            prepare(
                client.config(),
                &ActionSpec { path, ..BASE },
                RequestParts::default()
            )
            .is_err(),
            "{path}"
        );
    }
    for base in [
        "file:///tmp",
        "https://user:pass@example.test",
        "https://@example.test",
        "https://example.test?secret",
        "https://example.test/#fragment",
        "https://example.test/a/../mount",
        "https://example.test/a/%2e%2e/mount",
        "https://example.test/a\\b",
        "https://example.test/a/%2fb",
        " https://example.test",
    ] {
        assert!(
            ClientBuilder::<AsyncTransport>::new(base, &API)
                .build()
                .is_err(),
            "{base}"
        );
    }
    let spec = ActionSpec {
        path: "v7.0/{id}",
        ..BASE
    };
    for id in ["", ".", "..", "line\nbreak"] {
        let mut parts = RequestParts::default();
        parts.path_params.insert("id".into(), id.into());
        assert!(prepare(client.config(), &spec, parts).is_err());
    }
}

#[derive(Deserialize)]
struct Output {
    name: Option<String>,
    owner: Option<Association>,
    #[serde(default)]
    _meta: Option<JsonMap>,
}
#[derive(Deserialize)]
struct Meta {
    count: Option<i64>,
    #[serde(flatten)]
    extra: JsonMap,
}

fn output_spec() -> ActionSpec {
    ActionSpec {
        output: Some(OutputSpec {
            layout: Layout::Object,
            namespace: "item",
            allow_empty_response: false,
        }),
        ..BASE
    }
}

#[test]
fn output_fields_and_partial_associations_remain_optional() {
    let response = decode::<Output, Meta>(&output_spec(), raw(200, json!({"status":true,"response":{"item":{"owner":{"_meta":{"resolved":false,"authorized":false}},"extra":1},"_meta":{"count":1,"action_state_id":99}}}))).unwrap();
    assert!(response.output.name.is_none());
    assert_eq!(
        response.output.owner.unwrap().as_map()["_meta"]["authorized"],
        false
    );
    assert_eq!(response.meta.count, Some(1));
    assert_eq!(response.meta.extra["action_state_id"], 99);
    let response = decode::<Output, Meta>(
        &output_spec(),
        raw(
            200,
            json!({"status":true,"response":{"item":{"name":null,"owner":null}}}),
        ),
    )
    .unwrap();
    assert!(response.output.name.is_none());
    assert!(response.output.owner.is_none());
    assert!(response.meta.count.is_none());
}

#[test]
fn lists_preserve_item_metadata() {
    let spec = ActionSpec {
        output: Some(OutputSpec {
            layout: Layout::ObjectList,
            namespace: "items",
            allow_empty_response: false,
        }),
        ..BASE
    };
    let response = decode::<Vec<Output>, Meta>(&spec, raw(200, json!({"status":true,"response":{"items":[{"name":"one","_meta":{"path_params":[1]}}]}}))).unwrap();
    assert_eq!(
        response.output[0]._meta.as_ref().unwrap()["path_params"],
        json!([1])
    );
}

#[test]
fn decode_distinguishes_api_http_protocol_and_type_failures() {
    for status in [200, 400, 403, 500] {
        let error = decode::<Output, Meta>(&output_spec(), raw(status, json!({"status":false,"message":"secret-server-message","errors":{"name":["secret-value"]}}))).unwrap_err();
        assert!(matches!(error, Error::Api { .. }));
        assert_eq!(error.http_status(), Some(status));
        assert_eq!(error.server_message(), Some("secret-server-message"));
        assert_eq!(error.validation_errors().unwrap()["name"], ["secret-value"]);
        assert!(!format!("{error:?} {error}").contains("secret"));
    }
    for status in [302, 400, 500] {
        assert!(matches!(
            decode::<Output, Meta>(
                &output_spec(),
                raw(status, json!({"status":true,"response":{"item":{}}}))
            ),
            Err(Error::Http { .. })
        ));
        assert!(matches!(
            decode::<Output, Meta>(
                &output_spec(),
                RawResponse {
                    status,
                    body: b"<html>secret</html>".to_vec()
                }
            ),
            Err(Error::Http { .. })
        ));
    }
    for body in [
        json!(null),
        json!([]),
        json!({}),
        json!({"status":"true"}),
        json!({"status":true}),
        json!({"status":true,"response":null}),
        json!({"status":true,"response":{}}),
        json!({"status":true,"response":{"wrong":{}}}),
    ] {
        assert!(matches!(
            decode::<Output, Meta>(&output_spec(), raw(200, body)),
            Err(Error::Protocol { .. })
        ));
    }
    for body in [
        json!({"status":true,"response":{"item":null}}),
        json!({"status":true,"response":{"item":{"name":123}}}),
        json!({"status":true,"response":{"item":{ },"_meta":false}}),
    ] {
        assert!(matches!(
            decode::<Output, Meta>(&output_spec(), raw(200, body)),
            Err(Error::Decode { .. })
        ));
    }
    assert!(matches!(
        decode::<Output, Meta>(
            &output_spec(),
            RawResponse {
                status: 204,
                body: Vec::new()
            }
        ),
        Err(Error::Protocol { .. })
    ));
}

#[test]
fn empty_named_and_explicit_no_output_do_not_relax_envelopes() {
    let spec = ActionSpec {
        output: Some(OutputSpec {
            layout: Layout::Hash,
            namespace: "empty",
            allow_empty_response: true,
        }),
        ..BASE
    };
    for body in [
        json!({"status":true,"response":{}}),
        json!({"status":true,"response":{"empty":{}}}),
    ] {
        assert_eq!(
            decode::<JsonMap, JsonMap>(&spec, raw(200, body))
                .unwrap()
                .output,
            JsonMap::new()
        );
    }
    for response in [
        json!(null),
        json!([]),
        json!(""),
        json!({"wrong":{}}),
        json!({"_meta":{}}),
    ] {
        assert!(
            decode::<JsonMap, JsonMap>(&spec, raw(200, json!({"status":true,"response":response})))
                .is_err()
        );
    }
    let list = ActionSpec {
        output: Some(OutputSpec {
            layout: Layout::HashList,
            namespace: "empty",
            allow_empty_response: true,
        }),
        ..BASE
    };
    assert!(
        decode::<Vec<JsonMap>, JsonMap>(&list, raw(200, json!({"status":true,"response":{}})))
            .is_err()
    );
    decode::<(), JsonMap>(&BASE, raw(200, json!({"status":true,"response":{}}))).unwrap();
    assert!(
        decode::<(), JsonMap>(
            &BASE,
            raw(200, json!({"status":true,"response":{"unexpected":{}}}))
        )
        .is_err()
    );
}

#[test]
fn auth_is_explicit_and_tokens_use_only_the_described_header() {
    let client = ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
        .token("credential-secret")
        .build()
        .unwrap();
    let request = prepare(client.config(), &BASE, RequestParts::default()).unwrap();
    assert_eq!(request.headers["x-fixture-token"], "credential-secret");
    assert!(request.headers["x-fixture-token"].is_sensitive());
    let request = prepare(
        client.config(),
        &ActionSpec {
            auth: RequestAuth::None,
            ..BASE
        },
        RequestParts::default(),
    )
    .unwrap();
    assert!(!request.headers.contains_key("x-fixture-token"));
    let client = ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
        .oauth2_token("oauth-secret")
        .build()
        .unwrap();
    let request = prepare(client.config(), &BASE, RequestParts::default()).unwrap();
    assert_eq!(request.headers["x-fixture-oauth"], "oauth-secret");
    let client = ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
        .basic_auth("Aladdin", "open sesame")
        .build()
        .unwrap();
    assert_eq!(
        prepare(client.config(), &BASE, RequestParts::default())
            .unwrap()
            .headers["authorization"],
        "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
    );
    assert!(
        ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
            .token("one")
            .oauth2_token("two")
            .build()
            .is_err()
    );
    assert!(
        ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
            .token("bad\r\nheader")
            .build()
            .is_err()
    );
    let no_auth = Box::leak(Box::new(ApiSpec {
        basic_auth: false,
        token_header: None,
        oauth2_header: None,
        ..API
    }));
    assert!(
        ClientBuilder::<AsyncTransport>::new("https://example.test", no_auth)
            .token("secret")
            .build()
            .is_err()
    );
    assert!(
        ClientBuilder::<AsyncTransport>::new("https://example.test", no_auth)
            .basic_auth("name", "pass")
            .build()
            .is_err()
    );
}

#[test]
fn continuation_is_checked_and_diagnostics_are_redacted() {
    let step = TokenStep::from_parts(
        false,
        Some("transient-secret".into()),
        Some("totp".into()),
        &["totp"],
    )
    .unwrap();
    match &step {
        TokenStep::Challenge { token, next_action } => {
            assert_eq!(token.expose_secret(), "transient-secret");
            assert_eq!(next_action, "totp");
        }
        _ => panic!("expected challenge"),
    }
    assert!(!format!("{step:?}").contains("secret"));
    let final_step = TokenStep::from_parts(true, Some("final-secret".into()), None, &[]).unwrap();
    assert!(!format!("{final_step:?}").contains("secret"));
    assert!(matches!(
        TokenStep::from_parts(
            false,
            Some("secret".into()),
            Some("unknown".into()),
            &["totp"]
        ),
        Err(Error::UnsupportedAuthStep { .. })
    ));
    assert!(matches!(
        TokenStep::from_parts(false, None, Some("totp".into()), &["totp"]),
        Err(Error::Protocol { .. })
    ));
    assert!(matches!(
        TokenStep::from_parts(true, Some(String::new()), None, &[]),
        Err(Error::Protocol { .. })
    ));
    assert!(matches!(
        TokenStep::from_parts(true, Some("secret".into()), Some("totp".into()), &[]),
        Err(Error::Protocol { .. })
    ));
    let client = ClientBuilder::<AsyncTransport>::new("https://example.test", &API)
        .token("credential-secret")
        .build()
        .unwrap();
    let request = Request::<_, _, (), JsonMap>::new(&client, &BASE, BTreeMap::new(), ());
    assert!(!format!("{client:?} {:?} {request:?}", client.config()).contains("credential-secret"));
    let parts = parts(json!({"name":"input-secret"}));
    assert!(!format!("{parts:?}").contains("input-secret"));
}
