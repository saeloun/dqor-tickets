require "rails_helper"

RSpec.describe AdminUser, type: :model do
  it "normalizes email and authenticates a password" do
    admin = create(:admin_user, email: " Admin@Example.com ")

    expect(admin.email).to eq("admin@example.com")
    expect(described_class.authenticate_by(email: "admin@example.com", password: "password123")).to eq(admin)
  end
end
