class Dummy < ActiveRecord::Base
  validate :name, presence: true
end
