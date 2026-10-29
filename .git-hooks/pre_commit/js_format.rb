require 'open3'

module Overcommit::Hook::PreCommit
  class JsFormat < Base
    def run
      root = File.expand_path('../..', __dir__)
      stdout, stderr, status = Open3.capture3('npm', '--prefix', 'clients/js', 'run', 'format:check', chdir: root)
      return :pass if status.success?

      [:fail, [stdout, stderr].reject(&:empty?).join("\n")]
    end
  end
end
