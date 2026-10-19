use haveapi_rust_fixture::{Client, Error};
use serde_json::json;
use std::time::Duration;

fn base_url() -> String {
    std::env::var("HAVEAPI_TEST_BASE_URL").expect("fixture runner must supply a local URL")
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

// Identical generated builders, inputs and assertions exercise both adapters.
macro_rules! real_protocol_cases {
    ($client:expr, $send:ident) => {{
        let api = $client;
        let omitted = $send!(api.test().echo_optional()).expect("Test::EchoOptional omitted input");
        assert_eq!(omitted.output.dt_provided, Some(false));
        let null = $send!(api.test().echo_optional().dt_null()).expect("Test::EchoOptional null input");
        assert_eq!(null.output.dt_provided, Some(true));
        assert_eq!(null.output.dt_nil, Some(true));
        let query_null = $send!(api.test().echo_optional_get().dt_null()).expect("Test::EchoOptionalGet");
        assert_eq!(query_null.output.dt_provided, Some(true));
        assert_eq!(query_null.output.dt_nil, Some(true));

        let echo = $send!(api.test().echo()
            .i(0).f(0.0).b(false).dt("2020-01-31T10:20Z")
            .s("scalar").t("line one\nline two")).expect("Test::Echo");
        assert_eq!(echo.output.i, Some(0));
        assert_eq!(echo.output.b, Some(false));
        assert_eq!(echo.output.s.as_deref(), Some("scalar"));
        assert_eq!(echo.output.t.as_deref(), Some("line one\nline two"));

        let body = $send!(api.rust_fixture().echo().number(0).flag(false).text("")).expect("RustFixture::Echo");
        assert_eq!(body.output.received, Some(json!({"number": 0, "flag": false, "text": ""})));
        let queried = $send!(api.rust_fixture().query().number_null().flag(false))
            .expect("RustFixture::Query GET");
        assert_eq!(queried.output.received, Some(json!({"number": null, "flag": false})), "RustFixture::Query GET");

        let custom = json!({"nested": [0, false, null, {"text": "a&b + c"}]});
        let global_meta = json!({"global_marker": {"confirmed": false}});
        let object_meta = json!({"object_marker": [0, null]});
        let deleted = $send!(api.rust_fixture().delete_body()
            .number_null().zero(0).flag(false).text("").value(custom.clone())
            .global_meta(global_meta.as_object().unwrap().clone())
            .object_meta(object_meta.as_object().unwrap().clone()))
            .expect("RustFixture::DeleteBody DELETE JSON");
        assert_eq!(deleted.output.received, Some(json!({
            "number": null, "zero": 0, "flag": false, "text": "", "value": custom.clone()
        })), "RustFixture::DeleteBody exact JSON input with omitted field absent");
        assert_eq!(deleted.output.received_meta, Some(json!({
            "global_marker": {"confirmed": false}, "object_marker": [0, null]
        })), "RustFixture::DeleteBody global and object metadata");
        let flat = $send!(api.rust_fixture().unnamespaced().number(0).flag(false)).expect("RustFixture::Unnamespaced");
        assert_eq!(flat.output.received, Some(json!({"number": 0, "flag": false})));
        let result = $send!(api.rust_fixture().echo_custom().value(custom.clone())).expect("RustFixture::EchoCustom");
        assert_eq!(result.output.value, Some(custom));
        assert!($send!(api.rust_fixture().custom_query().value(json!({"nested": true})))
            .err().unwrap().validation_errors().is_some());

        let project = $send!(api.project().create().name("Rust fixture")).expect("Project::Create");
        let id = project.output.id.unwrap();
        let show = $send!(api.project().show(id)).expect("Project::Show");
        assert_eq!(show.output.name.as_deref(), Some("Rust fixture"));
        assert_eq!(show.meta.resolved, Some(true));
        assert!(show.meta.path_params.is_some());
        let task = $send!(api.project__task(id).create().label("child").done(true)).expect("Project::Task::Create");
        let task_id = task.output.id.unwrap();
        let update = $send!(api.project__task(id).update(task_id).done(false)).expect("Project::Task::Update");
        assert_eq!(update.output.done, Some(false));
        let child = $send!(api.project__task(id).show(task_id)).expect("Project::Task::Show");
        assert_eq!(child.output.label.as_deref(), Some("child"));
        let submitted = $send!(api.project__task(id).run(task_id)).expect("Project::Task::Run");
        assert!(submitted.meta.action_state_id.is_some());
        let list = $send!(api.project().index().global_meta(
            json!({"count": true}).as_object().unwrap().clone()
        )).expect("Project::Index with count metadata");
        assert!(list.output.iter().any(|p| p.id == Some(id)));
        assert_eq!(list.http_status, 200);
        assert!(list.meta.total_count.is_some());
        assert!(list.output.iter().all(|p| p.object_meta.is_some()));
        let public = $send!(api.project().public_show(id)).expect("Project::PublicShow");
        assert!(public.meta.path_params.is_none());
        let associated = $send!(api.rust_fixture().association()).expect("RustFixture::Association");
        assert_eq!(associated.output.project.unwrap().as_map().get("id"), Some(&json!(1)));

        use haveapi_rust_fixture::resources::rust_fixture::batch::Input as BatchInput;
        use haveapi_rust_fixture::runtime::InputValue;
        let batch = $send!(api.rust_fixture().batch().input(vec![
            BatchInput { number: InputValue::Value(0), ..Default::default() },
            BatchInput { number: InputValue::Value(42), ..Default::default() },
        ])).expect("RustFixture::Batch");
        assert_eq!(batch.output[0].number, Some(0));
        assert_eq!(batch.output[1].number, Some(42));

        let failure = $send!(api.test().fail()).err().expect("real failure envelope");
        assert!(matches!(failure, Error::Api { .. }));
        assert_eq!(failure.http_status(), Some(400));
        let missing = $send!(api.project().show(999999)).err().expect("real 404 envelope");
        assert_eq!(missing.http_status(), Some(404));
        let invalid = $send!(api.test().echo().f(f64::NAN)).err().expect("local validation");
        assert!(invalid.validation_errors().is_some());
    }};
}

macro_rules! token_cases {
    ($client_type:ty, $send:ident) => {{
        use haveapi_rust_fixture::runtime::TokenStep;
        let api = <$client_type>::builder(base_url())
            .basic_auth("admin", "pass")
            .build()
            .unwrap();
        let pending = $send!(
            api.authentication__token__token()
                .request()
                .user("user")
                .password("totp")
                .lifetime("fixed")
        )
        .expect("Token::Request challenge")
        .output;
        let TokenStep::Challenge { token, next_action } = pending.token_step().unwrap() else {
            panic!("TOTP must be an explicit challenge");
        };
        assert_eq!(next_action, "totp");
        let reset = $send!(
            api.authentication__token__token()
                .totp()
                .token(token.expose_secret())
                .code("123456")
        )
        .expect("Token::Totp")
        .output;
        let TokenStep::Challenge { token, next_action } = reset.token_step().unwrap() else {
            panic!("password reset must be an explicit challenge");
        };
        assert_eq!(next_action, "reset_password");
        let done = $send!(
            api.authentication__token__token()
                .reset_password()
                .token(token.expose_secret())
                .new_password1("fixture-new-password")
                .new_password2("fixture-new-password")
        )
        .expect("Token::ResetPassword")
        .output;
        let TokenStep::Complete { token } = done.token_step().unwrap() else {
            panic!("expected a complete token step");
        };
        assert!(!format!("{token:?}").contains(token.expose_secret()));
        let session = <$client_type>::builder(base_url())
            .token(token.expose_secret())
            .build()
            .unwrap();
        assert!(
            !$send!(session.project().index())
                .expect("Project::Index with existing token")
                .output
                .is_empty()
        );
        $send!(session.authentication__token__token().renew()).expect("Token::Renew");
        // Real ok! response:{} regression (FROZEN clarification 2).
        $send!(session.authentication__token__token().revoke()).expect("Token::Revoke");
        assert_eq!(
            $send!(session.project().index())
                .err()
                .unwrap()
                .http_status(),
            Some(401)
        );
        let unknown = $send!(
            api.authentication__token__token()
                .request()
                .user("user")
                .password("unknown")
                .lifetime("fixed")
        )
        .expect("Token::Request unknown challenge")
        .output;
        assert!(matches!(
            unknown.token_step(),
            Err(Error::UnsupportedAuthStep { .. })
        ));
    }};
}

#[tokio::test]
async fn real_haveapi_async() {
    let client = Client::builder(base_url())
        .basic_auth("admin", "pass")
        .build()
        .unwrap();
    real_protocol_cases!(client, async_response);
    token_cases!(Client, async_response);
}

#[cfg(feature = "blocking")]
#[test]
fn real_haveapi_blocking() {
    let client = haveapi_rust_fixture::blocking::Client::builder(base_url())
        .basic_auth("admin", "pass")
        .build()
        .unwrap();
    real_protocol_cases!(client, blocking_response);
    token_cases!(haveapi_rust_fixture::blocking::Client, blocking_response);
}

#[tokio::test]
async fn existing_oauth2_token_and_deadline() {
    let client = Client::builder(base_url())
        .oauth2_token("oauth-user")
        .build()
        .unwrap();
    assert!(
        !client
            .project()
            .index()
            .send()
            .await
            .unwrap()
            .output
            .is_empty()
    );
    let client = Client::builder(base_url())
        .timeout(Duration::from_millis(25))
        .build()
        .unwrap();
    assert!(matches!(
        client.test().slow().send().await,
        Err(Error::Transport { .. })
    ));
}

// The entire blocking-client lifecycle stays in the worker, including Drop.
#[cfg(feature = "blocking")]
async fn blocking_bridge() {
    tokio::task::spawn_blocking(|| {
        let client = haveapi_rust_fixture::blocking::Client::builder(base_url())
            .basic_auth("admin", "pass")
            .build()
            .unwrap();
        assert_eq!(client.project().show(1).send().unwrap().output.id, Some(1));
    })
    .await
    .unwrap();
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "current_thread")]
async fn blocking_lifecycle_on_current_thread() {
    blocking_bridge().await;
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn blocking_lifecycle_on_multiple_threads() {
    blocking_bridge().await;
}

#[cfg(feature = "blocking")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn started_blocking_work_keeps_its_http_deadline_after_abort() {
    let (started, running) = std::sync::mpsc::channel();
    let task = tokio::task::spawn_blocking(move || {
        let client = haveapi_rust_fixture::blocking::Client::builder(base_url())
            .timeout(Duration::from_millis(100))
            .build()
            .unwrap();
        started.send(()).unwrap();
        client.test().slow().send().err().unwrap()
    });
    running.recv_timeout(Duration::from_secs(2)).unwrap();
    task.abort();
    // Tokio cannot abort an already-running blocking worker. Its own request
    // deadline still ends the call; a mutation would not be rolled back.
    assert!(task.await.unwrap().is_timeout());
}
