require 'bcrypt'

class User < ActiveRecord::Base
  has_many :auth_tokens

  validates :username, :password, presence: true
  validates :username, length: {maximum: 50}

  # Attempt to authenticate user
  # @return [User] if authenticated
  # @return [nil] if not
  def self.authenticate(request, username, password)
    user = find_by(username: username)
    return unless user

    begin
      ::BCrypt::Password.new(user.password) == password
      
    rescue BCrypt::Errors::InvalidHash
      return false
    end

    user
  end

  def self.hash_password(pwd)
    ::BCrypt::Password.create(pwd).to_s
  end
end
