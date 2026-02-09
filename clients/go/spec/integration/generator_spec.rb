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

      go_out, go_err, go_status = Open3.capture3('go', 'test', './...', chdir: dir)
      expect(go_status).to be_success, "go test failed: #{go_out}\n#{go_err}"
    end
  end
end
