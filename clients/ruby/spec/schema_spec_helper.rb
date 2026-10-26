require_relative '../lib/haveapi/schema'
require 'tmpdir'
require 'stringio'
require 'open3'
require 'rbconfig'

module SchemaFixtures
  URL = 'https://schema.example.test/mount/v7.0/'.freeze

  def description
    {
      'help' => '/mount/v7.0/', 'meta' => { 'namespace' => '_meta' },
      'authentication' => {}, 'resources' => {
        'widget' => { 'actions' => {}, 'resources' => {} }
      }
    }
  end

  def envelope
    { 'status' => true, 'version' => '2.0', 'response' => description }
  end

  def snapshot
    HaveAPI::Schema::Snapshot.from_envelope(envelope, api_version: '7.0', source_url: URL,
                                                      profile: 'fixture', mount_path: '/mount/')
  end
end
