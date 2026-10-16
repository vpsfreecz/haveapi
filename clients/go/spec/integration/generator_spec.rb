# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::GoClient::Generator do
  let(:base_url) { TEST_SERVER.base_url }
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:cwd) { File.join(root, 'clients', 'go') }

  def oauth2_action_description(method:, path:, output_params:)
    {
      aliases: [],
      input: nil,
      output: {
        layout: 'object',
        namespace: 'action_state',
        parameters: output_params
      },
      method:,
      path:,
      meta: {},
      blocking: false
    }
  end

  def oauth2_revoke_description(revoke_url: '/revoke')
    {
      authentication: {
        oauth2: {
          http_header: 'X-HaveAPI-OAuth2-Token',
          revoke_url:
        }
      },
      meta: { namespace: '_meta' },
      resources: {
        action_state: {
          resources: {},
          actions: {
            show: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}',
              output_params: { id: { type: 'Integer' } }
            ),
            poll: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}/poll',
              output_params: { finished: { type: 'Boolean' } }
            )
          }
        }
      }
    }
  end

  def action_description(method:, path:, aliases: [], input: nil, output: nil, meta: {}, blocking: false)
    {
      aliases:,
      input:,
      output:,
      method:,
      path:,
      meta:,
      blocking:
    }
  end

  it 'generates a client that compiles and can call the API' do
    Dir.mktmpdir('haveapi-go-client-') do |dir|
      cmd = [
        'bundle', 'exec', 'ruby', 'bin/haveapi-go-client',
        base_url, dir,
        '--module', 'example.com/haveapi-test',
        '--package', 'client',
        '--basic-user', 'user',
        '--basic-password', 'pass'
      ]

      stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
      expect(status).to be_success, "generator failed: #{stdout}\n#{stderr}"

      File.write(File.join(dir, 'client', 'client_integration_test.go'), <<~GO)
        package client

        import (
          "net/http"
          "testing"
          "time"
        )

        func TestProjectList(t *testing.T) {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")

          resp, err := c.Project.List.Prepare().Call()
          if err != nil {
            t.Fatalf("list failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if len(resp.Output) < 2 {
            t.Fatalf("expected at least 2 projects, got %d", len(resp.Output))
          }
        }

        func TestProjectPublicResponsesWithoutPathParams(t *testing.T) {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")

          showReq := c.Project.PublicShow.Prepare()
          showReq.SetPathParamInt("project_id", 1)
          showResp, err := showReq.Call()
          if err != nil {
            t.Fatalf("public show failed: %v", err)
          }

          if !showResp.Status {
            t.Fatalf("public show failed: %s", showResp.Message)
          }

          if showResp.Output.Name != "Alpha" {
            t.Fatalf("expected public show name Alpha, got %q", showResp.Output.Name)
          }

          listResp, err := c.Project.PublicList.Prepare().Call()
          if err != nil {
            t.Fatalf("public list failed: %v", err)
          }

          if !listResp.Status {
            t.Fatalf("public list failed: %s", listResp.Message)
          }

          if len(listResp.Output) < 2 {
            t.Fatalf("expected at least 2 public projects, got %d", len(listResp.Output))
          }

          if listResp.Output[0].Name != "Alpha" {
            t.Fatalf("expected first public project Alpha, got %q", listResp.Output[0].Name)
          }
        }

        func TestClientTimeout(t *testing.T) {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")
          c.SetTimeout(10 * time.Millisecond)

          _, err := c.Test.Slow.Prepare().Call()
          if err == nil {
            t.Fatalf("expected timeout error, got nil")
          }
        }

        func TestClientHTTPClient(t *testing.T) {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")
          c.SetHTTPClient(&http.Client{Timeout: 10 * time.Millisecond})

          _, err := c.Test.Slow.Prepare().Call()
          if err == nil {
            t.Fatalf("expected timeout error, got nil")
          }
        }
      GO

      File.write(File.join(dir, 'client', 'client_validation_test.go'), <<~GO)
        package client

        import (
          "math"
          "net/http"
          "strings"
          "testing"
        )

        func newValidationClient() *Client {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")
          return c
        }

        func TestValidationErrorCompatibility(t *testing.T) {
          verr := NewValidationError()
          verr.Add("field", "broken")
          if verr.Empty() {
            t.Fatalf("expected validation error to be non-empty")
          }

          legacyLiteral := ValidationError{map[string][]string{
            "field": []string{"broken"},
          }}
          if legacyLiteral.Empty() {
            t.Fatalf("expected legacy literal validation error to be non-empty")
          }
        }

        func TestEchoRejectsNaNFloat(t *testing.T) {
          c := newValidationClient()
          req := c.Test.Echo.Prepare()
          in := req.NewInput()
          in.SetI(1)
          in.SetF(math.NaN())
          in.SetB(true)
          in.SetDt("2020-01-01T00:00:00Z")
          in.SetS("x")
          in.SetT("y")

          _, err := req.Call()
          if err == nil {
            t.Fatalf("expected validation error, got nil")
          }

          verr, ok := err.(*ValidationError)
          if !ok {
            t.Fatalf("expected ValidationError, got %T: %v", err, err)
          }

          if verr.Errors["f"] == nil {
            t.Fatalf("expected float error, got %#v", verr.Errors)
          }
        }

        func TestLanguageHeaderAndLocalizedValidation(t *testing.T) {
          c := newValidationClient()
          if err := c.SetLanguage("cs-CZ"); err != nil {
            t.Fatalf("set language failed: %v", err)
          }
          if err := c.SetLanguageHeader("X-Language"); err != nil {
            t.Fatalf("set language header failed: %v", err)
          }
          if got := c.GetLanguage(); got != "cs-CZ" {
            t.Fatalf("expected configured language cs-CZ, got %q", got)
          }
          if got := c.GetLanguageHeader(); got != "X-Language" {
            t.Fatalf("expected configured language header X-Language, got %q", got)
          }

          httpReq, err := http.NewRequest("GET", "#{base_url}/v1/test", nil)
          if err != nil {
            t.Fatalf("new request failed: %v", err)
          }
          c.addLanguageHeader(httpReq)
          if got := httpReq.Header.Get("X-Language"); got != "cs-CZ" {
            t.Fatalf("expected language header cs-CZ, got %q", got)
          }

          req := c.Test.Echo.Prepare()
          in := req.NewInput()
          in.SetI(1)
          in.SetF(math.NaN())
          in.SetB(true)
          in.SetDt("2020-01-01T00:00:00Z")
          in.SetS("x")
          in.SetT("y")

          _, err = req.Call()
          if err == nil {
            t.Fatalf("expected validation error, got nil")
          }

          verr, ok := err.(*ValidationError)
          if !ok {
            t.Fatalf("expected ValidationError, got %T: %v", err, err)
          }

          if got := strings.Join(verr.Errors["f"], " "); !strings.Contains(got, "není platné desetinné číslo") {
            t.Fatalf("expected Czech float error, got %q", got)
          }

          if !strings.Contains(err.Error(), "validace selhala") {
            t.Fatalf("expected Czech validation summary, got %q", err.Error())
          }
        }

        func TestLocalizedChoiceMetadataAcceptsValidValue(t *testing.T) {
          c := newValidationClient()
          if err := c.SetLanguage("cs"); err != nil {
            t.Fatalf("set language failed: %v", err)
          }

          req := c.Test.EchoChoice.Prepare()
          in := req.NewInput()
          in.SetFormat("archive")

          resp, err := req.Call()
          if err != nil {
            t.Fatalf("request failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if resp.Output.Format != "archive" {
            t.Fatalf("expected archive format, got %q", resp.Output.Format)
          }
        }

        func TestEchoRejectsInvalidDatetime(t *testing.T) {
          c := newValidationClient()
          req := c.Test.Echo.Prepare()
          in := req.NewInput()
          in.SetI(1)
          in.SetF(1.0)
          in.SetB(true)
          in.SetDt("not-a-date")
          in.SetS("x")
          in.SetT("y")

          _, err := req.Call()
          if err == nil {
            t.Fatalf("expected validation error, got nil")
          }

          verr, ok := err.(*ValidationError)
          if !ok {
            t.Fatalf("expected ValidationError, got %T: %v", err, err)
          }

          if verr.Errors["dt"] == nil {
            t.Fatalf("expected datetime error, got %#v", verr.Errors)
          }
        }

        func TestEchoResourceRejectsNegativeID(t *testing.T) {
          c := newValidationClient()
          req := c.Test.EchoResource.Prepare()
          in := req.NewInput()
          in.SetProject(-1)

          _, err := req.Call()
          if err == nil {
            t.Fatalf("expected validation error, got nil")
          }

          verr, ok := err.(*ValidationError)
          if !ok {
            t.Fatalf("expected ValidationError, got %T: %v", err, err)
          }

          if verr.Errors["project"] == nil {
            t.Fatalf("expected resource error, got %#v", verr.Errors)
          }
        }

        func TestEchoResourceOptionalAcceptsNil(t *testing.T) {
          c := newValidationClient()
          req := c.Test.EchoResourceOptional.Prepare()
          in := req.NewInput()
          in.SetProjectNil(true)

          resp, err := req.Call()
          if err != nil {
            t.Fatalf("request failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if !resp.Output.ProjectNil {
            t.Fatalf("expected ProjectNil=true, got false")
          }

          if !resp.Output.ProjectProvided {
            t.Fatalf("expected ProjectProvided=true, got false")
          }
        }

        func TestEchoOptionalAcceptsNil(t *testing.T) {
          c := newValidationClient()
          req := c.Test.EchoOptional.Prepare()
          in := req.NewInput()
          in.SetDtNil(true)

          resp, err := req.Call()
          if err != nil {
            t.Fatalf("request failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if !resp.Output.DtNil {
            t.Fatalf("expected DtNil=true, got false")
          }

          if !resp.Output.DtProvided {
            t.Fatalf("expected DtProvided=true, got false")
          }
        }

        func TestEchoOptionalGetAcceptsNil(t *testing.T) {
          c := newValidationClient()
          req := c.Test.EchoOptionalGet.Prepare()
          in := req.NewInput()
          in.SetDtNil(true)

          resp, err := req.Call()
          if err != nil {
            t.Fatalf("request failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if !resp.Output.DtNil {
            t.Fatalf("expected DtNil=true, got false")
          }

          if !resp.Output.DtProvided {
            t.Fatalf("expected DtProvided=true, got false")
          }
        }

        func TestEchoAcceptsValidInput(t *testing.T) {
          c := newValidationClient()
          req := c.Test.Echo.Prepare()
          in := req.NewInput()
          in.SetI(123)
          in.SetF(1.5)
          in.SetB(true)
          in.SetDt("2020-01-01")
          in.SetS("hello")
          in.SetT("world")

          resp, err := req.Call()
          if err != nil {
            t.Fatalf("echo failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'allocates resource and action members without hiding client configuration' do
    description = oauth2_revoke_description
    description[:resources].merge!(
      language: {
        resources: {},
        actions: {}
      },
      set_language: {
        resources: {},
        actions: {}
      },
      get_language: {
        resources: {},
        actions: {}
      },
      url: {
        resources: {},
        actions: {}
      },
      authentication: {
        resources: {},
        actions: {}
      },
      revoke_access_token: {
        resources: {},
        actions: {}
      },
      widget: {
        resources: {
          client: {
            resources: {},
            actions: {}
          },
          list: {
            resources: {},
            actions: {}
          }
        },
        actions: {
          run: action_description(
            method: 'GET',
            path: '/widgets/run',
            aliases: %w[client list]
          )
        }
      }
    )

    Dir.mktmpdir('haveapi-go-client-member-names-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: description
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://unused.example',
        dir,
        module: 'example.com/haveapi-member-names',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'member_names_test.go'), <<~GO)
        package client

        import "testing"

        func TestCollisionSafeMemberNames(t *testing.T) {
          c := New("http://unused.example")

          if c.Language == nil {
            t.Fatalf("language resource is not initialized")
          }
          if c.SetLanguageResource == nil || c.GetLanguageResource == nil {
            t.Fatalf("language method collision resources are not initialized")
          }
          if c.UrlResource == nil || c.AuthenticationResource == nil {
            t.Fatalf("fixed client member collision resources are not initialized")
          }
          if c.RevokeAccessTokenResource == nil {
            t.Fatalf("OAuth2 method collision resource is not initialized")
          }
          if c.Widget.ClientResource == nil || c.Widget.List == nil {
            t.Fatalf("nested resources are not initialized")
          }
          if c.Widget.Run != c.Widget.ClientAction {
            t.Fatalf("client alias does not reference the run action")
          }
          if c.Widget.Run != c.Widget.ListAction {
            t.Fatalf("list alias does not reference the run action")
          }

          if err := c.SetLanguage("cs-CZ"); err != nil {
            t.Fatalf("set language failed: %v", err)
          }
          if err := c.SetLanguageHeader("X-Language"); err != nil {
            t.Fatalf("set language header failed: %v", err)
          }
          if c.GetLanguage() != "cs-CZ" || c.GetLanguageHeader() != "X-Language" {
            t.Fatalf("language configuration was not retained")
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'reserves only authentication methods emitted for the described API' do
    description = oauth2_revoke_description
    description[:resources][:revoke_access_token] = {
      resources: {},
      actions: {}
    }

    with_oauth2 = HaveAPI::GoClient::ApiVersion.new(description)
    oauth2_resource = with_oauth2.resources.detect do |resource|
      resource.name == 'revoke_access_token'
    end
    expect(oauth2_resource.go_member_name).to eq('RevokeAccessTokenResource')

    description[:authentication] = {}
    without_oauth2 = HaveAPI::GoClient::ApiVersion.new(description)
    plain_resource = without_oauth2.resources.detect do |resource|
      resource.name == 'revoke_access_token'
    end
    expect(plain_resource.go_member_name).to eq('RevokeAccessToken')
  end

  it 'generates an OAuth2 client that sends the revoke token as form data' do
    Dir.mktmpdir('haveapi-go-client-oauth2-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: oauth2_revoke_description
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://unused.example',
        dir,
        module: 'example.com/haveapi-oauth2-revoke',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'oauth2_revoke_test.go'), <<~GO)
        package client

        import (
          "io"
          "net/http"
          "net/url"
          "strings"
          "testing"
        )

        type captureTransport struct {
          req  *http.Request
          body string
        }

        func (transport *captureTransport) RoundTrip(req *http.Request) (*http.Response, error) {
          if req.Body != nil {
            body, err := io.ReadAll(req.Body)
            if err != nil {
              return nil, err
            }

            if err := req.Body.Close(); err != nil {
              return nil, err
            }

            transport.body = string(body)
          }

          transport.req = req

          return &http.Response{
            StatusCode: 200,
            Status:     "200 OK",
            Body:       io.NopCloser(strings.NewReader("ok")),
            Header:     make(http.Header),
            Request:    req,
          }, nil
        }

        func TestOAuth2RevokeSendsTokenFormBody(t *testing.T) {
          transport := &captureTransport{}
          token := "secret-token"

          c := New("http://unused.example")
          c.SetHTTPClient(&http.Client{Transport: transport})
          c.SetExistingOAuth2Auth(token)
          if err := c.SetLanguage("cs-CZ"); err != nil {
            t.Fatalf("set language failed: %v", err)
          }
          if err := c.SetLanguageHeader("X-Language"); err != nil {
            t.Fatalf("set language header failed: %v", err)
          }

          if err := c.RevokeAccessToken(); err != nil {
            t.Fatalf("revoke failed: %v", err)
          }

          if transport.req == nil {
            t.Fatalf("expected revoke request")
          }

          if got := transport.req.Method; got != "POST" {
            t.Fatalf("expected POST revoke, got %s", got)
          }

          if got := transport.req.URL.String(); got != "http://unused.example/revoke" {
            t.Fatalf("unexpected revoke URL: %s", got)
          }

          if got := transport.req.Header.Get("X-HaveAPI-OAuth2-Token"); got != token {
            t.Fatalf("expected OAuth2 header %q, got %q", token, got)
          }

          if got := transport.req.Header.Get("X-Language"); got != "cs-CZ" {
            t.Fatalf("expected language header cs-CZ, got %q", got)
          }

          if got := transport.req.Header.Get("Content-Type"); got != "application/x-www-form-urlencoded" {
            t.Fatalf("expected form content type, got %q", got)
          }

          form, err := url.ParseQuery(transport.body)
          if err != nil {
            t.Fatalf("invalid form body %q: %v", transport.body, err)
          }

          if got := form.Get("token"); got != token {
            t.Fatalf("expected revoke token %q, got %q in body %q", token, got, transport.body)
          }

          if c.Authentication != nil {
            t.Fatalf("expected authentication to be cleared after revoke")
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'generates context and raw calls with shared request and response ownership' do
    description = oauth2_revoke_description
    description[:authentication] = { basic: {} }
    output = { layout: 'object', namespace: 'probe', parameters: { value: { type: 'String' } } }
    input = {
      layout: 'hash', namespace: 'payload',
      parameters: {
        s: { type: 'String' }, f: { type: 'Float' },
        skip: { type: 'String', nullable: true }, unused: { type: 'String', nullable: true }
      }
    }
    meta = {
      global: {
        input: { layout: 'hash', namespace: '_meta', parameters: { includes: { type: 'String' } } }
      }
    }
    description[:resources][:probe] = {
      resources: {},
      actions: {
        list: action_description(
          method: 'GET', path: '/probes',
          output: { layout: 'object_list', namespace: 'probes', parameters: { value: { type: 'String' } } }
        ),
        fetch: action_description(method: 'GET', path: '/probes/{probe_id}', input:, output:, meta:),
        create: action_description(method: 'POST', path: '/probes', input:, output:, meta:),
        ping: action_description(method: 'POST', path: '/ping')
      }
    }
    custom_input = {
      layout: 'hash', namespace: 'payload',
      parameters: {
        label: { type: 'String' }, value: { type: 'Custom', required: true },
        optional: { type: 'Custom', nullable: true }
      }
    }
    custom_output = {
      layout: 'object', namespace: 'record',
      parameters: { label: { type: 'String' }, value: { type: 'Custom' } }
    }
    custom_meta = {
      global: {
        input: { layout: 'hash', namespace: '_meta', parameters: { includes: { type: 'Custom' } } }
      }
    }
    description[:resources][:record] = {
      resources: {},
      actions: {
        create: action_description(method: 'POST', path: '/records', input: custom_input, output: custom_output,
                                   meta: custom_meta),
        update: action_description(method: 'PUT', path: '/records', input: custom_input, output: custom_output,
                                   meta: custom_meta),
        read: action_description(method: 'GET', path: '/records', output: custom_output, meta: custom_meta)
      }
    }

    Dir.mktmpdir('haveapi-go-client-context-raw-') do |dir|
      communicator = instance_double(HaveAPI::Client::Communicator, describe_api: description)
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)
      generator = described_class.new(
        'http://api.example', dir,
        module: 'example.com/haveapi-context-raw', package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'context_raw_test.go'), <<~'GO')
        package client

        import (
          "bytes"
          "context"
          "encoding/json"
          "errors"
          "io"
          "math"
          "net/http"
          "reflect"
          "strings"
          "testing"
          "time"
        )

        type contextRawTransport func(*http.Request) (*http.Response, error)

        func (f contextRawTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

        type contextRawBody struct {
          io.Reader
          closes int
        }

        func (b *contextRawBody) Close() error { b.closes++; return nil }

        func contextRawClient(f contextRawTransport) *Client {
          c := New("http://api.example")
          c.SetHTTPClient(&http.Client{Transport: f})
          c.SetBasicAuthentication("user", "password")
          c.SetLanguage("cs")
          return c
        }

        func contextRawReply(code int, body io.ReadCloser) *http.Response {
          return &http.Response{StatusCode: code, Header: make(http.Header), Body: body}
        }

        func TestContextRawSerializationAndLegacyCalls(t *testing.T) {
          for _, mode := range []string{"legacy", "context", "raw"} {
            for _, method := range []string{"GET", "POST"} {
              t.Run(mode+method, func(t *testing.T) {
                calls := 0
                body := &contextRawBody{Reader: strings.NewReader(`{"status":true,"response":{"probe":{"value":"ok"}}}`)}
                c := contextRawClient(func(r *http.Request) (*http.Response, error) {
                  calls++
                  if r.Method != method || r.Header.Get("Accept-Language") != "cs" {
                    t.Fatal("method/language changed")
                  }
                  user, pass, ok := r.BasicAuth()
                  if !ok || user != "user" || pass != "password" { t.Fatal("authentication lost") }
                  if method == "GET" {
                    if r.URL.EscapedPath() != "/probes/a%20%2F%3F" || r.Body != nil { t.Fatal("path/body changed", r.URL) }
                    want := map[string][]string{"payload[s]": {" a +b"}, "payload[skip]": {""}, "_meta[includes]": {"node"}}
                    if !reflect.DeepEqual(map[string][]string(r.URL.Query()), want) { t.Fatal("query selection changed", r.URL.RawQuery) }
                  } else {
                    if r.URL.Path != "/probes" || r.Header.Get("Content-Type") != "application/json" { t.Fatal("body route/type changed") }
                    var got map[string]interface{}
                    if err := json.NewDecoder(r.Body).Decode(&got); err != nil { t.Fatal(err) }
                    want := map[string]interface{}{"payload": map[string]interface{}{"s": " a +b", "skip": nil}, "_meta": map[string]interface{}{"includes": "node"}}
                    if !reflect.DeepEqual(got, want) { t.Fatal("body selection/namespace changed", got) }
                  }
                  return contextRawReply(200, body), nil
                })
                ctx := context.Background()
                var typed *ActionProbeFetchResponse
                var err error
                if method == "GET" {
                  inv := c.Probe.Fetch.Prepare().SetPathParamString("probe_id", "a /?")
                  in := inv.NewInput(); in.SetS(" a +b").SetSkipNil(true)
                  inv.NewMetaInput().SetIncludes("node")
                  switch mode {
                  case "legacy": typed, err = inv.Call()
                  case "context": typed, err = inv.CallContext(ctx)
                  case "raw":
                    var raw *RawResponse
                    raw, err = inv.CallRaw(ctx)
                    if err == nil && (raw.StatusCode != 200 || !bytes.Contains(raw.Body, []byte(`"value":"ok"`))) { t.Fatal(raw) }
                  }
                  if mode != "raw" && err == nil && (!typed.Status || typed.Output.Value != "ok") { t.Fatal(typed) }
                } else {
                  inv := c.Probe.Create.Prepare()
                  in := inv.NewInput(); in.SetS(" a +b").SetSkipNil(true)
                  inv.NewMetaInput().SetIncludes("node")
                  var result *ActionProbeCreateResponse
                  switch mode {
                  case "legacy": result, err = inv.Call()
                  case "context": result, err = inv.CallContext(ctx)
                  case "raw":
                    var raw *RawResponse
                    raw, err = inv.CallRaw(ctx)
                    if err == nil && raw.StatusCode != 200 { t.Fatal(raw) }
                  }
                  if mode != "raw" && err == nil && (!result.Status || result.Output.Value != "ok") { t.Fatal(result) }
                }
                if err != nil || calls != 1 || body.closes != 1 { t.Fatal(err, calls, body.closes) }
              })
            }
          }
        }

        func TestContextRawNoInputShortcuts(t *testing.T) {
          bodies := []*contextRawBody{}
          c := contextRawClient(func(r *http.Request) (*http.Response, error) {
            text := `{"status":true,"response":{"probes":[]}}`
            if r.Method == "POST" { text = `{"status":true}` }
            b := &contextRawBody{Reader: strings.NewReader(text)}; bodies = append(bodies, b)
            return contextRawReply(200, b), nil
          })
          if result, err := c.Probe.List.Call(); err != nil || !result.Status || len(result.Output) != 0 { t.Fatal(result, err) }
          if result, err := c.Probe.List.CallContext(context.Background()); err != nil || !result.Status { t.Fatal(result, err) }
          if _, err := c.Probe.List.CallRaw(context.Background()); err != nil { t.Fatal(err) }
          if result, err := c.Probe.Ping.Call(); err != nil || !result.Status { t.Fatal(result, err) }
          if result, err := c.Probe.Ping.CallContext(context.Background()); err != nil || !result.Status { t.Fatal(result, err) }
          if _, err := c.Probe.Ping.CallRaw(context.Background()); err != nil { t.Fatal(err) }
          if len(bodies) != 6 { t.Fatal(len(bodies)) }
          for _, body := range bodies { if body.closes != 1 { t.Fatal(body.closes) } }
        }

        func TestContextRawUntouchedBodiesAndStatus(t *testing.T) {
          for _, code := range []int{200, 302, 400, 403, 404, 500} {
            for _, text := range []string{
              " \nnull \t", "not-json", string([]byte{0xff, 0}),
              ` {"status":true,"response":{"probes":[{"value":null,"n":184467440737095516160000,"_meta":{"resolved":false,"path_params":[9007199254740993]}}]}} `,
              `{"status":false,"message":"failed","errors":{"field":["invalid"]}}`,
            } {
              body := &contextRawBody{Reader: strings.NewReader(text)}; calls := 0
              c := contextRawClient(func(*http.Request) (*http.Response, error) { calls++; return contextRawReply(code, body), nil })
              got, err := c.Probe.List.CallRaw(context.Background())
              if err != nil || got.StatusCode != code || !bytes.Equal(got.Body, []byte(text)) || calls != 1 || body.closes != 1 {
                t.Fatal("raw response was decoded, classified or replayed", code, got, err, calls, body.closes)
              }
            }
          }
        }

        func TestContextTypedEnvelopeAndOutputGuards(t *testing.T) {
          for _, method := range []string{"GET", "POST"} {
            for _, text := range []string{
              "", "null", "[]", "true", `{}`, `{"message":"missing status"}`,
              `{"status":null}`, `{"status":"true"}`, `{"status":true}`,
              `{"status":true,"response":null}`, `{"status":true,"response":[]}`,
              `{"status":true,"response":{}}`, `{"status":true,"response":{"probes":null,"probe":null}}`,
              `{"status":true,"response":{"probes":{},"probe":[]}}`,
            } {
              body := &contextRawBody{Reader: strings.NewReader(text)}; calls := 0
              c := contextRawClient(func(*http.Request) (*http.Response, error) { calls++; return contextRawReply(200, body), nil })
              var err error
              if method == "GET" { _, err = c.Probe.List.CallContext(context.Background()) } else { _, err = c.Probe.Create.Prepare().CallContext(context.Background()) }
              if err == nil || calls != 1 || body.closes != 1 { t.Fatal("malformed typed response accepted", method, text, err, calls, body.closes) }
            }
          }
        }

        func TestContextTypedPreservesHTTPAndAPIStatusSemantics(t *testing.T) {
          for _, code := range []int{200, 400, 500} {
            for _, success := range []bool{false, true} {
              text := `{"status":false,"message":"failed","errors":{"field":["invalid"]}}`
              if success { text = `{"status":true,"response":{"probes":[]}}` }
              c := contextRawClient(func(*http.Request) (*http.Response, error) {
                return contextRawReply(code, &contextRawBody{Reader: strings.NewReader(text)}), nil
              })
              got, err := c.Probe.List.CallContext(context.Background())
              if err != nil || got.Status != success || (!success && (got.Message != "failed" || len(got.Errors["field"]) != 1)) { t.Fatal(got, err) }
            }
          }
        }

        func TestContextRawValidationBeforeDispatch(t *testing.T) {
          for _, mode := range []string{"legacy", "context", "raw"} {
            for _, method := range []string{"GET", "POST"} {
              calls := 0
              c := contextRawClient(func(*http.Request) (*http.Response, error) { calls++; return nil, errors.New("unexpected dispatch") })
              var err error
              if method == "GET" {
                inv := c.Probe.Fetch.Prepare().SetPathParamInt("probe_id", 1); inv.NewInput().SetF(math.NaN())
                switch mode { case "legacy": _, err = inv.Call(); case "context": _, err = inv.CallContext(context.Background()); case "raw": _, err = inv.CallRaw(context.Background()) }
              } else {
                inv := c.Probe.Create.Prepare(); inv.NewInput().SetF(math.NaN())
                switch mode { case "legacy": _, err = inv.Call(); case "context": _, err = inv.CallContext(context.Background()); case "raw": _, err = inv.CallRaw(context.Background()) }
              }
              var validation *ValidationError
              if !errors.As(err, &validation) || calls != 0 { t.Fatal("validation skipped", method, mode, err, calls) }
            }
          }
        }

        func TestContextRawUnsafePathsBeforeDispatch(t *testing.T) {
          for _, path := range []string{"@other.invalid/", "//other.invalid/", "https://other.invalid/", "/%zz"} {
            c := contextRawClient(func(*http.Request) (*http.Response, error) { t.Fatal("unsafe path dispatched"); return nil, nil })
            inv := c.Probe.Create.Prepare(); inv.Path = path
            if _, err := inv.CallRaw(context.Background()); err == nil { t.Fatal(path) }
            if _, err := inv.CallContext(context.Background()); err == nil { t.Fatal(path) }
            get := c.Probe.List.Prepare(); get.Path = path
            if _, err := get.CallRaw(context.Background()); err == nil { t.Fatal(path) }
            if _, err := get.CallContext(context.Background()); err == nil { t.Fatal(path) }
            var output interface{}
            err := c.DoBodyRequest("POST", path, math.NaN(), &output)
            if err == nil || strings.Contains(err.Error(), "unsupported value") { t.Fatal("path refusal was overwritten by JSON error", path, err) }
          }
        }

        func TestContextCanceledBeforeDispatch(t *testing.T) {
          c := contextRawClient(func(*http.Request) (*http.Response, error) { t.Fatal("canceled request dispatched"); return nil, nil })
          ctx, cancel := context.WithCancel(context.Background()); cancel()
          if _, err := c.Probe.List.CallContext(ctx); !errors.Is(err, context.Canceled) { t.Fatal(err) }
          if _, err := c.Probe.List.CallRaw(ctx); !errors.Is(err, context.Canceled) { t.Fatal(err) }
          if _, err := c.Probe.Ping.CallContext(ctx); !errors.Is(err, context.Canceled) { t.Fatal(err) }
          if _, err := c.Probe.Ping.CallRaw(ctx); !errors.Is(err, context.Canceled) { t.Fatal(err) }
        }

        type contextWaitingBody struct {
          ctx context.Context
          reading chan struct{}
          closes int
        }

        func (b *contextWaitingBody) Read([]byte) (int, error) { close(b.reading); <-b.ctx.Done(); return 0, b.ctx.Err() }
        func (b *contextWaitingBody) Close() error { b.closes++; return nil }

        func TestContextCancellationDuringHeadersAndBody(t *testing.T) {
          for _, raw := range []bool{false, true} {
            for _, reading := range []bool{false, true} {
              ctx, cancel := context.WithCancel(context.Background())
              started := make(chan struct{}); done := make(chan error, 1); calls := 0
              var body *contextWaitingBody
              c := contextRawClient(func(r *http.Request) (*http.Response, error) {
                calls++
                if !reading { close(started); <-r.Context().Done(); return nil, r.Context().Err() }
                body = &contextWaitingBody{ctx: r.Context(), reading: started}
                return contextRawReply(200, body), nil
              })
              go func() {
                var err error
                if raw { _, err = c.Probe.List.CallRaw(ctx) } else { _, err = c.Probe.List.CallContext(ctx) }
                done <- err
              }()
              select { case <-started: cancel(); case <-time.After(3*time.Second): cancel(); t.Fatal("request never reached intended boundary") }
              select {
              case err := <-done:
                if !errors.Is(err, context.Canceled) || calls != 1 || (reading && body.closes != 1) { t.Fatal(err, calls, body) }
              case <-time.After(3*time.Second): t.Fatal("cancellation did not return")
              }
            }
          }
        }

        type contextFailingReader struct { err error }
        func (r contextFailingReader) Read([]byte) (int, error) { return 0, r.err }

        func TestContextRawTransportAndReadFailures(t *testing.T) {
          failure := errors.New("synthetic failure")
          for _, raw := range []bool{false, true} {
            for _, duringRead := range []bool{false, true} {
              calls := 0
              body := &contextRawBody{Reader: contextFailingReader{failure}}
              c := contextRawClient(func(*http.Request) (*http.Response, error) {
                calls++
                if !duringRead { return nil, failure }
                return contextRawReply(200, body), nil
              })
              var err error
              if raw { _, err = c.Probe.List.CallRaw(context.Background()) } else { _, err = c.Probe.List.CallContext(context.Background()) }
              if !errors.Is(err, failure) || calls != 1 || (duringRead && body.closes != 1) { t.Fatal(err, calls, body.closes) }
            }
          }
        }

        type contextRedirectBody struct { contextRawBody }

        func (b *contextRedirectBody) Read(p []byte) (int, error) {
          if b.closes != 0 { panic("read after response body close") }
          return b.Reader.Read(p)
        }

        func (b *contextRedirectBody) Close() error {
          b.closes++
          if b.closes != 1 { panic("response body closed more than once") }
          return nil
        }

        func TestContextRawRedirectResponseOwnership(t *testing.T) {
          refusal := errors.New("synthetic redirect refusal")
          const text = `{"status":true,"response":{"probe":{"value":"redirect body"}}}`
          for _, mode := range []string{"legacy", "context", "raw", "low-level"} {
            for _, method := range []string{"GET", "POST"} {
              for _, useLast := range []bool{false, true} {
                policy := "refuse"
                if useLast { policy = "last-response" }
                t.Run(mode+"/"+method+"/"+policy, func(t *testing.T) {
                  calls, redirects := 0, 0
                  body := &contextRedirectBody{contextRawBody{Reader: strings.NewReader(text)}}
                  c := contextRawClient(func(r *http.Request) (*http.Response, error) {
                    calls++
                    if r.Method != method { t.Fatal("request method changed", r.Method) }
                    resp := contextRawReply(http.StatusFound, body)
                    resp.Header.Set("Location", "/redirect-target")
                    return resp, nil
                  })
                  c.httpClient.CheckRedirect = func(req *http.Request, via []*http.Request) error {
                    redirects++
                    if req.URL.Path != "/redirect-target" || len(via) != 1 || body.closes != 0 {
                      t.Fatal("redirect policy boundary changed", req.URL, len(via), body.closes)
                    }
                    if useLast { return http.ErrUseLastResponse }
                    return refusal
                  }
                  var err error
                  var value string
                  if mode == "low-level" {
                    var result struct { Response struct { Probe struct { Value string } } }
                    if method == "GET" {
                      err = c.DoQueryStringRequest("/probes/1", nil, &result)
                    } else {
                      err = c.DoBodyRequest("POST", "/probes", nil, &result)
                    }
                    value = result.Response.Probe.Value
                  } else if method == "GET" {
                    inv := c.Probe.Fetch.Prepare().SetPathParamInt("probe_id", 1)
                    var result *ActionProbeFetchResponse
                    switch mode {
                    case "legacy": result, err = inv.Call()
                    case "context": result, err = inv.CallContext(context.Background())
                    case "raw":
                      var raw *RawResponse
                      raw, err = inv.CallRaw(context.Background())
                      if useLast && (raw == nil || raw.StatusCode != http.StatusFound || !bytes.Equal(raw.Body, []byte(text))) {
                        t.Fatal("last raw response not read intact", raw, err)
                      }
                    }
                    if err == nil && result != nil { value = result.Output.Value }
                  } else {
                    inv := c.Probe.Create.Prepare()
                    var result *ActionProbeCreateResponse
                    switch mode {
                    case "legacy": result, err = inv.Call()
                    case "context": result, err = inv.CallContext(context.Background())
                    case "raw":
                      var raw *RawResponse
                      raw, err = inv.CallRaw(context.Background())
                      if useLast && (raw == nil || raw.StatusCode != http.StatusFound || !bytes.Equal(raw.Body, []byte(text))) {
                        t.Fatal("last raw response not read intact", raw, err)
                      }
                    }
                    if err == nil && result != nil { value = result.Output.Value }
                  }
                  if useLast {
                    if err != nil || (mode != "raw" && value != "redirect body") { t.Fatal("last response not decoded", value, err) }
                  } else if !errors.Is(err, refusal) {
                    t.Fatal("redirect refusal identity lost", err)
                  }
                  if calls != 1 || redirects != 1 || body.closes != 1 { t.Fatal("redirect replay/close mismatch", calls, redirects, body.closes) }
                })
              }
            }
          }
        }

        func TestContextDeadlineAndClientBodyTimeout(t *testing.T) {
          for _, clientTimeout := range []bool{false, true} {
            var body *contextWaitingBody
            c := contextRawClient(func(r *http.Request) (*http.Response, error) {
              body = &contextWaitingBody{ctx: r.Context(), reading: make(chan struct{})}
              return contextRawReply(200, body), nil
            })
            ctx := context.Background()
            cancel := func() {}
            if clientTimeout { c.SetTimeout(15*time.Millisecond) } else { ctx, cancel = context.WithTimeout(ctx, 15*time.Millisecond) }
            _, err := c.Probe.List.CallRaw(ctx); cancel()
            if !errors.Is(err, context.DeadlineExceeded) || body.closes != 1 { t.Fatal(err, body) }
          }
        }

        func TestLegacyLowLevelHelpersShareRawOwner(t *testing.T) {
          for _, method := range []string{"GET", "POST"} {
            calls := 0; body := &contextRawBody{Reader: strings.NewReader(`{"value":5}`)}
            c := contextRawClient(func(r *http.Request) (*http.Response, error) {
              calls++
              if r.Method != method { t.Fatal(r.Method) }
              return contextRawReply(200, body), nil
            })
            var output struct { Value int }
            var err error
            if method == "GET" { err = c.DoQueryStringRequest("/probes", map[string]string{"x":"y"}, &output) } else { err = c.DoBodyRequest("POST", "/probes", map[string]string{"x":"y"}, &output) }
            if err != nil || output.Value != 5 || calls != 1 || body.closes != 1 { t.Fatal(output, err, calls, body.closes) }
          }
        }

        func TestCustomInputJSONValues(t *testing.T) {
          for _, mode := range []string{"legacy", "context", "raw"} {
            for _, method := range []string{"POST", "PUT"} {
              for _, value := range []string{`{"nested":[null,9007199254740993]}`, `[1,"x",false]`, `"text"`, `true`, `9007199254740993`, `null`} {
                t.Run(mode+method+value, func(t *testing.T) {
                  calls := 0
                  c := contextRawClient(func(r *http.Request) (*http.Response, error) {
                    calls++
                    if r.Method != method || r.URL.Path != "/records" { t.Fatal(r.Method, r.URL) }
                    var got map[string]map[string]json.RawMessage
                    if err := json.NewDecoder(r.Body).Decode(&got); err != nil { t.Fatal(err) }
                    if len(got) != 2 || len(got["payload"]) != 2 || string(got["payload"]["value"]) != value ||
                      string(got["payload"]["label"]) != `"sibling"` || len(got["_meta"]) != 1 || string(got["_meta"]["includes"]) != `"node"` {
                      t.Fatal("custom input was omitted, rounded or encoded as a string", got)
                    }
                    return contextRawReply(200, &contextRawBody{Reader: strings.NewReader(`{"status":true,"response":{"record":{"label":"ok","value":{"output":9007199254740993}}}}`)}), nil
                  })
                  var err error
                  if method == "POST" {
                    inv := c.Record.Create.Prepare()
                    inv.NewInput().SetValue(json.RawMessage(value)).SetLabel("sibling")
                    inv.NewMetaInput().SetIncludes("node")
                    switch mode {
                    case "legacy": _, err = inv.Call()
                    case "context": _, err = inv.CallContext(context.Background())
                    case "raw": _, err = inv.CallRaw(context.Background())
                    }
                  } else {
                    inv := c.Record.Update.Prepare()
                    inv.NewInput().SetValue(json.RawMessage(value)).SetLabel("sibling")
                    inv.NewMetaInput().SetIncludes("node")
                    switch mode {
                    case "legacy": _, err = inv.Call()
                    case "context": _, err = inv.CallContext(context.Background())
                    case "raw": _, err = inv.CallRaw(context.Background())
                    }
                  }
                  if err != nil || calls != 1 { t.Fatal(err, calls) }
                })
              }
            }
          }
        }

        func TestCustomInputSelectionAndNull(t *testing.T) {
          cases := []struct {
            name string
            input func() *ActionRecordCreateInput
            want string
          }{
            {"nil-input", func() *ActionRecordCreateInput { return nil }, `{}`},
            {"select-all", func() *ActionRecordCreateInput { return &ActionRecordCreateInput{Label:"all", Value:json.RawMessage(`true`)} }, `{"label":"all","optional":null,"value":true}`},
            {"unset-select-all", func() *ActionRecordCreateInput { return &ActionRecordCreateInput{} }, `{"label":"","optional":null,"value":null}`},
            {"setter", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetValue(json.RawMessage(`[1]`)) }, `{"value":[1]}`},
            {"empty-selection", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{Value:json.RawMessage(`broken`)}).SelectParameters() }, `{}`},
            {"unselect", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetValue(json.RawMessage(`broken`)).UnselectParameters("Value").SetLabel("only") }, `{"label":"only"}`},
            {"nil-raw", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetValue(nil) }, `{"value":null}`},
            {"literal-null", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetValue(json.RawMessage(`null`)) }, `{"value":null}`},
            {"nullable-override", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetOptional(json.RawMessage(`broken`)).SetOptionalNil(true) }, `{"optional":null}`},
            {"nullable-clear", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetOptional(json.RawMessage(`false`)).SetOptionalNil(true).SetOptionalNil(false) }, `{"optional":false}`},
            {"setter-clears-nil", func() *ActionRecordCreateInput { return (&ActionRecordCreateInput{}).SetOptionalNil(true).SetOptional(json.RawMessage(`{"x":1}`)) }, `{"optional":{"x":1}}`},
          }
          for _, mode := range []string{"legacy", "context", "raw"} {
            for _, tc := range cases {
              t.Run(mode+"/"+tc.name, func(t *testing.T) {
                calls := 0
                c := contextRawClient(func(r *http.Request) (*http.Response, error) {
                  calls++
                  var got map[string]json.RawMessage
                  if err := json.NewDecoder(r.Body).Decode(&got); err != nil { t.Fatal(err) }
                  if len(got) != 2 || string(got["_meta"]) != `{}` || string(got["payload"]) != tc.want { t.Fatal("selection/null changed", got, tc.want) }
                  return contextRawReply(200, &contextRawBody{Reader: strings.NewReader(`{"status":true,"response":{"record":{"label":"ok"}}}`)}), nil
                })
                inv := c.Record.Create.Prepare().SetInput(tc.input())
                var err error
                switch mode {
                case "legacy": _, err = inv.Call()
                case "context": _, err = inv.CallContext(context.Background())
                case "raw": _, err = inv.CallRaw(context.Background())
                }
                if err != nil || calls != 1 { t.Fatal(err, calls) }
              })
            }
          }
          if _, ok := reflect.TypeOf(&ActionRecordCreateInput{}).MethodByName("SetValueNil"); ok { t.Fatal("nonnullable Custom input gained nil helper") }
        }

        type customInputAuthCounter struct { calls int }
        func (a *customInputAuthCounter) Authenticate(*http.Request) { a.calls++ }

        func TestCustomInputInvalidJSONBeforeAuthAndDispatch(t *testing.T) {
          for _, mode := range []string{"legacy", "context", "raw"} {
            for _, value := range []json.RawMessage{json.RawMessage{}, json.RawMessage(`broken`), json.RawMessage(`{} []`)} {
              auth := &customInputAuthCounter{}
              c := contextRawClient(func(*http.Request) (*http.Response, error) { t.Fatal("invalid JSON dispatched"); return nil,nil })
              c.Authentication = auth
              inv := c.Record.Create.Prepare()
              inv.NewInput().SetValue(value)
              var err error
              switch mode {
              case "legacy": _, err = inv.Call()
              case "context": _, err = inv.CallContext(context.Background())
              case "raw": _, err = inv.CallRaw(context.Background())
              }
              var marshalErr *json.MarshalerError
              if !errors.As(err, &marshalErr) || auth.calls != 0 { t.Fatal("invalid JSON reached authentication", err, auth.calls) }
            }
          }
        }

        func TestCustomInputLeavesApplicationValidationToServer(t *testing.T) {
          const text = `{"status":false,"message":"invalid value","errors":{"value":["required"]}}`
          for _, mode := range []string{"legacy", "context", "raw"} {
            calls := 0
            c := contextRawClient(func(r *http.Request) (*http.Response, error) {
              calls++
              var got map[string]map[string]json.RawMessage
              if err := json.NewDecoder(r.Body).Decode(&got); err != nil { t.Fatal(err) }
              if value, ok := got["payload"]["value"]; !ok || string(value) != "null" { t.Fatal("required null was changed", got) }
              return contextRawReply(400, &contextRawBody{Reader:strings.NewReader(text)}),nil
            })
            inv := c.Record.Create.Prepare()
            inv.NewInput().SetValue(nil)
            var result *ActionRecordCreateResponse
            var err error
            switch mode {
            case "legacy": result, err = inv.Call()
            case "context": result, err = inv.CallContext(context.Background())
            case "raw":
              var raw *RawResponse
              raw, err = inv.CallRaw(context.Background())
              if err == nil && (raw.StatusCode != 400 || !bytes.Equal(raw.Body,[]byte(text))) { t.Fatal(raw) }
            }
            if err != nil || calls != 1 { t.Fatal(err,calls) }
            if mode != "raw" && (result.Status || result.Message != "invalid value" || len(result.Errors["value"]) != 1) { t.Fatal(result) }
          }
        }

        func TestCustomMetadataIncludesAndOutputBoundary(t *testing.T) {
          calls := 0
          const text = `{"status":true,"response":{"record":{"label":"ok","value":{"n":9007199254740993}}}}`
          c := contextRawClient(func(r *http.Request) (*http.Response, error) {
            calls++
            if r.Method != "GET" || r.URL.RawQuery != "_meta%5Bincludes%5D=node__location" { t.Fatal("Custom includes query changed", r.URL) }
            return contextRawReply(200, &contextRawBody{Reader:strings.NewReader(text)}),nil
          })
          inv := c.Record.Read.Prepare()
          inv.NewMetaInput().SetIncludes("node__location")
          typed, err := inv.CallContext(context.Background())
          if err != nil || typed.Output.Label != "ok" { t.Fatal(typed,err) }
          if _, ok := reflect.TypeOf(ActionRecordReadOutput{}).FieldByName("Value"); ok { t.Fatal("unsupported Custom output gained typed field") }
          raw, err := inv.CallRaw(context.Background())
          if err != nil || !bytes.Equal(raw.Body,[]byte(text)) || calls != 2 { t.Fatal(raw,err,calls) }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' }, 'go', 'test', './...', chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'rejects ordinary Custom query inputs before emitting files' do
    description = oauth2_revoke_description
    description[:resources][:record] = {
      resources: {},
      actions: {
        search: action_description(
          method: 'GET', path: '/records',
          input: { layout: 'hash', namespace: 'record', parameters: { value: { type: 'Custom' } } }
        )
      }
    }
    Dir.mktmpdir('haveapi-go-custom-query-') do |dir|
      destination = File.join(dir, 'not-created')
      communicator = instance_double(HaveAPI::Client::Communicator, describe_api: description)
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)
      expect do
        described_class.new('http://api.example', destination, module: 'example.com/custom-query', package: 'client')
      end.to raise_error(RuntimeError, "unsupported Custom query input 'value' for action 'Record#Search'")
      expect(File.exist?(destination)).to be(false)
    end
  end

  it 'rejects generated action paths that can switch request authority' do
    malicious_description = {
      authentication: {
        basic: {}
      },
      meta: { namespace: '_meta' },
      resources: {
        action_state: {
          resources: {},
          actions: {
            show: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}',
              output_params: { id: { type: 'Integer' } }
            ),
            poll: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}/poll',
              output_params: { finished: { type: 'Boolean' } }
            )
          }
        },
        victim: {
          resources: {},
          actions: {
            list: action_description(method: 'GET', path: '@attacker.example/capture')
          }
        }
      }
    }

    Dir.mktmpdir('haveapi-go-client-action-authority-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: malicious_description
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://api.example',
        dir,
        module: 'example.com/haveapi-action-authority',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'action_authority_test.go'), <<~GO)
        package client

        import (
          "errors"
          "net/http"
          "testing"
        )

        type unexpectedActionTransport struct {
          req *http.Request
        }

        func (transport *unexpectedActionTransport) RoundTrip(req *http.Request) (*http.Response, error) {
          transport.req = req
          return nil, errors.New("unexpected request")
        }

        func TestActionPathAuthoritySwitchIsRejectedBeforeAuth(t *testing.T) {
          transport := &unexpectedActionTransport{}

          c := New("http://api.example")
          c.SetHTTPClient(&http.Client{Transport: transport})
          c.SetBasicAuthentication("user", "pass")

          if _, err := c.Victim.List.Call(); err == nil {
            t.Fatalf("expected unsafe action path error")
          }

          if transport.req != nil {
            t.Fatalf(
              "unexpected request to %s with authorization %q",
              transport.req.URL.String(),
              transport.req.Header.Get("Authorization"),
            )
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'escapes generated action path parameters as single path segments' do
    description = {
      authentication: {
        basic: {}
      },
      meta: { namespace: '_meta' },
      resources: {
        action_state: {
          resources: {},
          actions: {
            show: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}',
              output_params: { id: { type: 'Integer' } }
            ),
            poll: oauth2_action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}/poll',
              output_params: { finished: { type: 'Boolean' } }
            )
          }
        },
        user: {
          resources: {},
          actions: {
            show: action_description(
              method: 'GET',
              path: '/users/{user_id}',
              output: {
                layout: 'object',
                namespace: 'user',
                parameters: { id: { type: 'Integer' } }
              }
            )
          }
        }
      }
    }

    Dir.mktmpdir('haveapi-go-client-path-param-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: description
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://api.example',
        dir,
        module: 'example.com/haveapi-path-param',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'path_param_escape_test.go'), <<~GO)
        package client

        import (
          "io"
          "net/http"
          "net/url"
          "strings"
          "testing"
        )

        type pathParamEscapeTransport struct {
          req *http.Request
        }

        func (transport *pathParamEscapeTransport) RoundTrip(req *http.Request) (*http.Response, error) {
          transport.req = req

          return &http.Response{
            StatusCode: 200,
            Status:     "200 OK",
            Body:       io.NopCloser(strings.NewReader(`{"status":true,"response":{"user":{"id":42}}}`)),
            Header:     make(http.Header),
            Request:    req,
          }, nil
        }

        func TestPathParamIsEscapedAsSingleSegment(t *testing.T) {
          transport := &pathParamEscapeTransport{}
          pathArg := "42?user[name]=alice&_meta[includes]=group__secret/section#frag%2Fencoded=1"

          c := New("http://api.example")
          c.SetHTTPClient(&http.Client{Transport: transport})

          resp, err := c.User.Show.Prepare().SetPathParamString("user_id", pathArg).Call()
          if err != nil {
            t.Fatalf("request failed: %v", err)
          }

          if !resp.Status {
            t.Fatalf("request failed: %s", resp.Message)
          }

          if transport.req == nil {
            t.Fatalf("expected request")
          }

          if got := transport.req.URL.RawQuery; got != "" {
            t.Fatalf("path parameter injected query string %q", got)
          }

          if got := transport.req.URL.Fragment; got != "" {
            t.Fatalf("path parameter injected fragment %q", got)
          }

          expectedPath := "/users/" + url.PathEscape(pathArg)
          if got := transport.req.URL.EscapedPath(); got != expectedPath {
            t.Fatalf("expected escaped path %q, got %q", expectedPath, got)
          }

          if got := transport.req.URL.Query().Get("user[name]"); got != "" {
            t.Fatalf("unexpected injected user[name] query value %q", got)
          }

          if got := transport.req.URL.Query().Get("_meta[includes]"); got != "" {
            t.Fatalf("unexpected injected _meta[includes] query value %q", got)
          }

          if !strings.Contains(transport.req.URL.EscapedPath(), "%252Fencoded") {
            t.Fatalf("expected percent-encoded input to remain data, got %q", transport.req.URL.EscapedPath())
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'rejects OAuth2 revoke URLs outside the client origin before sending the token' do
    Dir.mktmpdir('haveapi-go-client-oauth2-revoke-origin-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: oauth2_revoke_description(
          revoke_url: 'http://attacker.example/collect-token'
        )
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://api.example',
        dir,
        module: 'example.com/haveapi-oauth2-revoke-origin',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'oauth2_revoke_origin_test.go'), <<~GO)
        package client

        import (
          "errors"
          "net/http"
          "testing"
        )

        type unexpectedRevokeTransport struct {
          req *http.Request
        }

        func (transport *unexpectedRevokeTransport) RoundTrip(req *http.Request) (*http.Response, error) {
          transport.req = req
          return nil, errors.New("unexpected request")
        }

        func TestOAuth2RevokeCrossOriginURLIsRejectedBeforeAuth(t *testing.T) {
          transport := &unexpectedRevokeTransport{}

          c := New("http://api.example")
          c.SetHTTPClient(&http.Client{Transport: transport})
          c.SetExistingOAuth2Auth("secret-token")

          if err := c.RevokeAccessToken(); err == nil {
            t.Fatalf("expected unsafe revoke URL error")
          }

          if transport.req != nil {
            t.Fatalf(
              "unexpected request to %s with token header %q",
              transport.req.URL.String(),
              transport.req.Header.Get("X-HaveAPI-OAuth2-Token"),
            )
          }

          if c.Authentication == nil {
            t.Fatalf("authentication should remain configured after failed revoke")
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'allows explicitly trusted OAuth2 revoke origins' do
    Dir.mktmpdir('haveapi-go-client-oauth2-revoke-trusted-origin-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: oauth2_revoke_description(
          revoke_url: 'http://auth.example/revoke'
        )
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://api.example',
        dir,
        module: 'example.com/haveapi-oauth2-revoke-trusted-origin',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      File.write(File.join(dir, 'client', 'oauth2_revoke_trusted_origin_test.go'), <<~GO)
        package client

        import (
          "io"
          "net/http"
          "net/url"
          "strings"
          "testing"
        )

        type trustedOriginRevokeTransport struct {
          req  *http.Request
          body string
        }

        func (transport *trustedOriginRevokeTransport) RoundTrip(req *http.Request) (*http.Response, error) {
          if req.Body != nil {
            body, err := io.ReadAll(req.Body)
            if err != nil {
              return nil, err
            }

            if err := req.Body.Close(); err != nil {
              return nil, err
            }

            transport.body = string(body)
          }

          transport.req = req

          return &http.Response{
            StatusCode: 200,
            Status:     "200 OK",
            Body:       io.NopCloser(strings.NewReader("ok")),
            Header:     make(http.Header),
            Request:    req,
          }, nil
        }

        func TestOAuth2RevokeTrustedOrigin(t *testing.T) {
          transport := &trustedOriginRevokeTransport{}
          token := "trusted-origin-token"

          c := New("http://api.example")
          if err := c.AllowOAuth2Origin("http://auth.example"); err != nil {
            t.Fatalf("allow OAuth2 origin failed: %v", err)
          }
          c.SetHTTPClient(&http.Client{Transport: transport})
          c.SetExistingOAuth2Auth(token)

          if err := c.RevokeAccessToken(); err != nil {
            t.Fatalf("revoke failed: %v", err)
          }

          if transport.req == nil {
            t.Fatalf("expected revoke request")
          }

          if got := transport.req.URL.String(); got != "http://auth.example/revoke" {
            t.Fatalf("unexpected revoke URL: %s", got)
          }

          if got := transport.req.Header.Get("X-HaveAPI-OAuth2-Token"); got != token {
            t.Fatalf("expected OAuth2 header %q, got %q", token, got)
          }

          form, err := url.ParseQuery(transport.body)
          if err != nil {
            t.Fatalf("invalid form body %q: %v", transport.body, err)
          }

          if got := form.Get("token"); got != token {
            t.Fatalf("expected revoke token %q, got %q in body %q", token, got, transport.body)
          }
        }
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end

  it 'escapes untrusted API descriptions when generating Go source' do
    injected_path = <<~PATH.chomp
      /safe",
      \t}
      }

      func init() {
      \tpanic("generated code executed from API description")
      }

      func (action *ActionVictimList) unused() *ActionVictimListInvocation {
      \treturn &ActionVictimListInvocation{
      \t\tAction: action,
      \t\tPath: "/safe
    PATH

    injected_name = "bad\"\nfunc init() { panic(\"name\") }\n"
    injected_method = "POST\"\nfunc init() { panic(\"method\") }\n"
    injected_auth = "X-Token\"\nfunc init() { panic(\"auth\") }\n"

    malicious_description = {
      authentication: {
        oauth2: {
          http_header: injected_auth,
          revoke_url: "https://auth.example/revoke\"\nfunc init() { panic(\"revoke\") }\n"
        }
      },
      meta: { namespace: "_meta#{injected_name}" },
      resources: {
        action_state: {
          resources: {},
          actions: {
            show: action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}',
              output: {
                layout: 'object',
                namespace: 'action_state',
                parameters: { id: { type: 'Integer' } }
              }
            ),
            poll: action_description(
              method: 'GET',
              path: '/action_states/{action_state_id}/poll',
              output: {
                layout: 'object',
                namespace: 'action_state',
                parameters: { finished: { type: 'Boolean' } }
              }
            )
          }
        },
        victim: {
          resources: {},
          actions: {
            list: action_description(method: 'GET', path: injected_path)
          }
        },
        injected_name => {
          resources: {},
          actions: {
            injected_name => action_description(
              method: injected_method,
              path: "/#{injected_name}",
              aliases: [injected_name],
              input: {
                layout: 'object',
                namespace: "input#{injected_name}",
                parameters: {
                  injected_name => { type: 'String', nullable: true }
                }
              },
              output: {
                layout: 'object',
                namespace: "output#{injected_name}",
                parameters: {
                  injected_name => { type: 'String' }
                }
              },
              meta: {
                global: {
                  input: {
                    layout: 'object',
                    namespace: "meta#{injected_name}",
                    parameters: {
                      "meta#{injected_name}" => { type: 'String' }
                    }
                  }
                }
              }
            )
          }
        }
      }
    }

    Dir.mktmpdir('haveapi-go-client-injection-') do |dir|
      communicator = instance_double(
        HaveAPI::Client::Communicator,
        describe_api: malicious_description
      )
      allow(HaveAPI::Client::Communicator).to receive(:new).and_return(communicator)

      generator = described_class.new(
        'http://unused.example',
        dir,
        module: 'example.com/haveapi-injection',
        package: 'client'
      )
      generator.generate
      generator.go_fmt

      generated_sources = Dir[File.join(dir, 'client', '*.go')].map do |path|
        File.read(path)
      end.join("\n")

      expect(generated_sources).not_to match(/^\s*func init\(\)/)

      File.write(File.join(dir, 'client', 'package_load_test.go'), <<~GO)
        package client

        import "testing"

        func TestGeneratedPackageLoads(t *testing.T) {}
      GO

      go_out, go_err, go_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'test',
        './...',
        chdir: dir
      )
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end
end
