require "rails_helper"

RSpec.describe "Registration desk accounts", type: :request do
  let(:date) { "2026-10-08" }

  def desk_account
    create(:admin_user, role: :desk, password: "password123")
  end

  def admin_account
    create(:admin_user, role: :admin, password: "password123")
  end

  describe "sign-in landing" do
    it "sends desk staff to the check-in scanner" do
      post session_path, params: { email: desk_account.email, password: "password123" }

      expect(response).to redirect_to(checkin_path)
    end

    it "sends admins to the Avo admin" do
      post session_path, params: { email: admin_account.email, password: "password123" }

      expect(response).to redirect_to(Avo.configuration.root_path)
    end
  end

  describe "the check-in scanner" do
    it "is reachable by a desk account" do
      sign_in_admin(desk_account)

      get checkin_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Registration desk")
    end

    it "lets a desk account check a ticket in" do
      sign_in_admin(desk_account)
      ticket = create(:ticket)

      post checkin_path, params: { secret: ticket.secret, date: }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("state" => "success")
      expect(ticket.reload.checked_in_at).to have_key(date)
    end
  end

  describe "the admin area is off-limits to desk accounts" do
    it "bounces a desk account from Avo to the scanner" do
      sign_in_admin(desk_account)

      get "/avo"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to end_with("/checkin")
      expect(response.location).not_to include("/avo")
    end

    it "still admits a full admin to Avo" do
      sign_in_admin(admin_account)

      get "/avo"

      expect(response.location.to_s).not_to end_with("/checkin")
    end
  end
end
