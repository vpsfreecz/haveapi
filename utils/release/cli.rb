require_relative 'publish'
require_relative 'workflow'

begin
  root = File.expand_path('../..', __dir__)
  artifacts = HaveAPI::Release::Artifacts.new(root)
  command, argument = ARGV
  case command
  when 'artifact-state'
    File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') { |f| f.puts "id=#{HaveAPI::Release::Workflow.artifact_id}" }
  when 'check-activation'
    HaveAPI::Release::Workflow.check_activation
  when 'check', 'check-clean'
    artifacts.check(clean: command == 'check-clean', release_tag: argument)
    puts "Release metadata valid: #{artifacts.version}"
  when 'manifest'
    artifacts.write_manifest(argument || 'dist')
  when 'verify'
    artifacts.verify(argument || 'dist')
    puts "Verified retained artifacts: #{artifacts.tag} at #{artifacts.source}"
  when 'smoke-npm'
    artifacts.verify(argument || 'dist')
    artifacts.smoke_npm(argument || 'dist')
  when 'github-prepare', 'publish'
    unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['GITHUB_REPOSITORY'] == HaveAPI::Release::REPOSITORY &&
           ENV['GITHUB_EVENT_NAME'] == 'push' && ENV['GITHUB_REF'] == "refs/tags/#{artifacts.tag}"
      raise HaveAPI::Release::Error, 'Publication is available only in the tagged GitHub Actions release job'
    end
    raise HaveAPI::Release::Error, 'Use the top-level Nix release shell' unless ENV['HAVEAPI_DEV_SHELL'] == 'haveapi'

    artifacts.check_tag(artifacts.tag)
    publisher = HaveAPI::Release::Publisher.new(artifacts, argument || 'dist')
    if command == 'github-prepare'
      publisher.prepare_github
    else
      publisher.publish
    end
  else
    raise HaveAPI::Release::Error, 'See doc/agent-instructions/releases.md for release helper commands'
  end
rescue HaveAPI::Release::Error, KeyError, JSON::ParserError, Errno::ENOENT => e
  warn "Release failed: #{e.message}"
  exit 1
end
