require 'open3'

module Overcommit::Hook::PreCommit
  class PythonChecks < Base
    def run
      root = File.expand_path('../..', __dir__)
      python = File.join(root, 'clients/python')
      commands = [
        ['uv', 'run', '--locked', 'python', 'utils/run_ruff.py', '--config', 'pyproject.toml', 'format', '--check', '.', '../../utils/release'],
        ['uv', 'run', '--locked', 'python', 'utils/run_ruff.py', '--config', 'pyproject.toml', 'check', '.', '../../utils/release']
      ]
      commands.each do |command|
        stdout, stderr, status = Open3.capture3(*command, chdir: python)
        return [:fail, [stdout, stderr].reject(&:empty?).join("\n")] unless status.success?
      end
      :pass
    end
  end
end
