class AuthToken < ActiveRecord::Base
  belongs_to :user

  enum lifetime: %i[fixed renewable_manual renewable_auto permanent]

  validates :token, presence: true
  validates :token, length: { is: 100 }

  def renew
    self.valid_to = Time.now + interval
  end
end
