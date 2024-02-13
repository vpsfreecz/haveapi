require 'bcrypt'

class User < ActiveRecord::Base
  has_many :auth_tokens

  validates :username, :password, presence: true
  validates :username, length: { maximum: 50 }

  # Attempt to authenticate user
  # @return [User] if authenticated
  # @return [nil] if not
  def self.authenticate(request, username, password)
    user = find_by(username:)
    return unless user

    begin
      return user if ::BCrypt::Password.new(user.password) == password
    rescue BCrypt::Errors::InvalidHash
    end

    false
  end

  def self.hash_password(pwd)
    ::BCrypt::Password.create(pwd).to_s
  end
end
