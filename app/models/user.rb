class User < ApplicationRecord
  has_secure_password validations: false
  has_one_attached :avatar

  has_many :connections, dependent: :destroy
  has_many :connected_users, through: :connections, source: :connected_user

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  def paid_orders
    Order.paid.where("lower(orders.email) = ?", email)
  end

  def tickets
    Ticket.joins(:order).merge(paid_orders)
  end

  def gravatar_url(size: 200)
    hash = Digest::MD5.hexdigest(email.to_s.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end

  def connected_to?(other)
    connections.exists?(connected_user_id: other.id)
  end

  def display_name
    name.presence || email.split("@").first
  end
end
