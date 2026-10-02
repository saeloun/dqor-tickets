class Operations::BusinessContact < Operations::Record
  validates :name, presence: true, length: { maximum: 200 }
  validates :email, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
