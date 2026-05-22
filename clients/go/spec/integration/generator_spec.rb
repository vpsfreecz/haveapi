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

  def oauth2_revoke_description
    {
      authentication: {
        oauth2: {
          http_header: 'X-HaveAPI-OAuth2-Token',
          revoke_url: 'https://auth.example/revoke'
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
          "testing"
        )

        func newValidationClient() *Client {
          c := New("#{base_url}")
          c.SetBasicAuthentication("user", "pass")
          return c
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

          if err := c.RevokeAccessToken(); err != nil {
            t.Fatalf("revoke failed: %v", err)
          }

          if transport.req == nil {
            t.Fatalf("expected revoke request")
          }

          if got := transport.req.Method; got != "POST" {
            t.Fatalf("expected POST revoke, got %s", got)
          }

          if got := transport.req.URL.String(); got != "https://auth.example/revoke" {
            t.Fatalf("unexpected revoke URL: %s", got)
          }

          if got := transport.req.Header.Get("X-HaveAPI-OAuth2-Token"); got != token {
            t.Fatalf("expected OAuth2 header %q, got %q", token, got)
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
end
