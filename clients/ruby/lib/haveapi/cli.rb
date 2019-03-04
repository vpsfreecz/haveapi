require 'haveapi/client'

module HaveAPI
  module CLI
    module Commands ; end
  end
end

require_rel 'cli/*.rb'
require_rel 'cli/authentication/'
require_rel 'cli/commands/'
