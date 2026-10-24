# Native dry-run regression: no compiler, listener or generated SDK is started.
require_relative 'documentation_acceptance'

class GoDocumentationBuildCheck
  def self.run!
    GoDocumentationAcceptance.check_environment!
    Dir.mktmpdir('haveapi-go-documentation-build-') do |root|
      # Own this invalid ancestor marker; never rely on or alter ambient Git state.
      Dir.mkdir(File.join(root, '.git'))
      consumer = File.join(root, 'consumer')
      FileUtils.mkdir_p(File.join(consumer, 'cmd/probe'))
      File.write(File.join(consumer, 'go.mod'), "module example.test/documentation-consumer\n\ngo 1.20\n")
      File.write(File.join(consumer, 'cmd/probe/main.go'), "package main\nfunc main() {}\n")
      command = GoDocumentationAcceptance.build_command(File.join(root, 'bin')).insert(2, '-n', '-x')
      environment = { 'GOWORK' => 'off', 'GOPROXY' => 'off', 'GOSUMDB' => 'off', 'GOTOOLCHAIN' => 'local' }
      _output, error, status = Open3.capture3(environment, *command, chdir: consumer)
      raise "documentation build plan failed: #{error}" unless status.success?
      raise 'documentation build unexpectedly queried Git status' if error.include?('git status --porcelain')

      # Prove the regression condition with the same command minus its policy flag.
      control = command.reject { |argument| argument == '-buildvcs=false' }
      _output, error, status = Open3.capture3(environment, *control, chdir: consumer)
      unless !status.success? && error.include?('error obtaining VCS status') &&
             error.include?("cd #{root}\n") && error.include?('git status --porcelain')
        raise "unflagged control did not reproduce owned ancestor VCS discovery: #{error}"
      end
    end
    $stdout.write("Go documentation build dry-run and unflagged VCS control passed\n") # rubocop:disable RSpec/Output
  end
end

GoDocumentationBuildCheck.run! if $0 == __FILE__
