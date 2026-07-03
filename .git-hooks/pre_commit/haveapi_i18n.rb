require 'open3'

module Overcommit::Hook::PreCommit
  class HaveapiI18n < Base
    def run
      root = File.expand_path('../..', __dir__)
      env = { 'BUNDLE_GEMFILE' => File.join(root, 'Gemfile') }
      cmd = ['bundle', 'exec', 'rake', 'i18n:health']
      stdout, stderr, status = Open3.capture3(env, *cmd, chdir: root)

      return :pass if status.success?

      [:fail, [stdout, stderr].reject(&:empty?).join("\n")]
    end
  end
end
