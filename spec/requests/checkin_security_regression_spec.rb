require "rails_helper"

RSpec.describe "Check-in mutation security regressions", type: :request do
  let(:operator) { create(:admin_user, role: :desk) }
  let(:ticket) { create(:ticket, order: create(:order, :paid)) }
  let(:date) { "2026-10-08" }

  it "rejects staff-authenticated admission and batch mutations without a CSRF token" do
    sign_in_admin(operator)
    original = ActionController::Base.allow_forgery_protection
    begin
      ActionController::Base.allow_forgery_protection = true
      post checkin_path, params: { ticket_id: ticket.id, date: }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post batch_checkin_path, params: { ticket_ids: [ ticket.id ], date:, confirmed: true }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.reload.checked_in_at).to eq({})
      expect(CheckinAudit.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
  end

  it "rejects an attendee session from admission and batch mutation routes" do
    user = User.create!(email: "synthetic-scanner-attendee@example.test")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token:)
    post checkin_path, params: { ticket_id: ticket.id, date: }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post batch_checkin_path, params: { ticket_ids: [ ticket.id ], date:, confirmed: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
  end
end
