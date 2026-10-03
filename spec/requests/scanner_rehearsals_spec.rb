require "rails_helper"

RSpec.describe "Scanner rehearsal", type: :request do
  it "requires staff authentication" do
    get scanner_rehearsal_path
    expect(response).to redirect_to(new_session_path)
  end

  it "serves only a synthetic sample with browser connections blocked" do
    sign_in_admin(create(:admin_user, role: :desk))
    get scanner_rehearsal_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Security-Policy"]).to include("connect-src 'none'")
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.body).to include(ScannerRehearsalsController::TEST_QR, "REHEARSAL ONLY")
    expect(response.body).not_to include('data-controller="checkin"', 'data-controller="slot-scanner"')
    expect(Ticket.count).to eq(0)
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
  end
end
