require 'securerandom'

class AuthToken < ActiveRecord::Base
  belongs_to :user
  
  enum lifetime: %i(fixed renewable_manual renewable_auto permanent)

  validates :token, presence: true
  validates :token, length: {is: 100}
  
  def self.generate
    SecureRandom.hex(50)
  end

  def renew
    self.valid_to = Time.now + interval
  end
end
