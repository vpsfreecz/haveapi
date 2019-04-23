require 'require_all'

module HaveAPI
  module GoClient
    def self.tpl(name)
      File.join(
        File.dirname(__FILE__),
        '..', '..',
        'template',
        "#{name}.erb"
      )
    end
  end
end

require_rel 'go_client/*.rb'
require_rel 'go_client/authentication'
