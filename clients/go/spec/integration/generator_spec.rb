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

      expect(File).to exist(File.join(dir, 'client', 'resource_test_cd8aff96.go'))
      expect(File).to exist(
        File.join(dir, 'client', 'resource_test_action_test_b557b63f.go')
      )
      expect(File).to exist(File.join(dir, 'client', 'resource_test_generated.go'))

      build_out, build_err, build_status = Open3.capture3(
        { 'CGO_ENABLED' => '0' },
        'go',
        'build',
        './...',
        chdir: dir
      )
      expect(build_status).to be_success,
                              "go build failed: #{build_out}\n#{build_err}"

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
