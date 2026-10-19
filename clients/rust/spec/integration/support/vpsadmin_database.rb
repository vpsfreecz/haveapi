# frozen_string_literal: true

require 'tmpdir'

module RustClientFixtures
  def self.database_state_dir
    # TestDb places its Unix socket below this directory. Artifact TMPDIRs can
    # exceed the platform socket-path limit, so use a short private directory.
    Dir.mktmpdir('rust-vpsadmin-', '/tmp')
  end
end
