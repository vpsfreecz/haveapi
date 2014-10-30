module HaveAPI
  class Metadata
    def self.namespace
      :_meta
    end

    def self.describe
      {
          namespace: namespace
      }
    end
  end
end
