# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::GoClient::Generator do
  let(:base_url) { TEST_SERVER.base_url }
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:cwd) { File.join(root, 'clients', 'go') }

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

        import "testing"

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

      go_out, go_err, go_status = Open3.capture3('go', 'test', './...', chdir: dir)
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end
end
