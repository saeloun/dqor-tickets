require "rails_helper"

RSpec.describe "Check-ins", type: :request do
  let(:date) { "2026-10-08" }

  it "requires an admin session" do
    get checkin_path

    expect(response).to redirect_to(new_session_path)
  end

  it "searches by attendee details and order code" do
    sign_in_admin
    ticket = create(:ticket, attendee_name: "Grace Hopper")

    get checkin_path, params: { q: "grace", date: }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Grace Hopper", ticket.order.code, ticket.secret)
  end

  it "checks in a ticket for the selected day" do
    sign_in_admin
    ticket = create(:ticket)

    post checkin_path, params: { secret: ticket.secret, date: }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("state" => "success")
    expect(ticket.reload.checked_in_at).to have_key(date)
  end

  it "returns a warning with the prior time for a duplicate" do
    sign_in_admin
    ticket = create(:ticket)
    checked_in_at = ticket.check_in!(date)
    time = Time.iso8601(checked_in_at).in_time_zone("Asia/Kolkata").strftime("%H:%M")

    post checkin_path, params: { secret: ticket.secret, date: }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include("state" => "warning", "message" => "Already checked in at #{time}")
  end

  it "rejects a canceled or refunded ticket" do
    sign_in_admin
    ticket = create(:ticket, canceled_at: Time.current)

    post checkin_path, params: { secret: ticket.secret, date: }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("state" => "error", "message" => "Canceled or refunded ticket")
  end
end
