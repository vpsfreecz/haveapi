require 'require_all'

module HaveAPI
  module GoClient
    # @param name [String] template within the `../../template/` directory,
    #                      without `.erb` suffix
    # @return [String] absolute path to the template
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
require_rel 'go_client/parameters'
