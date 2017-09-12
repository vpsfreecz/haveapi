require 'nesty'

module HaveAPI
  class BuildError < StandardError
    include Nesty::NestedError
  end
end
