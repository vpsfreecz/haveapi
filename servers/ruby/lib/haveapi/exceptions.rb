require 'nesty'

module HaveAPI
  class BuildError < StandardError
    include Nesty::NestedError
  end

  class AuthenticationError < StandardError ; end
end
