require "rails_helper"

RSpec.describe "Conference badges", type: :request do
  let(:admin) { create(:admin_user, role: :admin) }
  let(:type) { create(:ticket_type, slug: "conference-pass-regular") }
  let(:ticket) { create(:ticket, order: create(:order, :paid), ticket_type: type, attendee_name: "Synthetic Ada", attendee_email: "private-attendee@example.com") }

  it "requires authentication for the roster, sample and printing" do
    [ conference_badges_path, sample_conference_badges_path, sample_conference_badges_path(format: :pdf) ].each do |path|
      get path
      expect(response).to redirect_to(new_session_path)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ], confirmed: true }
    expect(response).to redirect_to(new_session_path)
  end

  [ :admin, :desk ].each do |role|
    it "allows existing #{role} staff to review samples and print a confirmed PDF without grants or attendance writes" do
      operator = create(:admin_user, role:)
      sign_in_admin(operator)
      before = ticket.attributes
      roles = AdminUser.pluck(:id, :role)
      get conference_badges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ticket.attendee_name, "Registration desk")
      get sample_conference_badges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SAMPLE / REHEARSAL", "NOT ADMISSION")
      get sample_conference_badges_path(format: :pdf)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF-")
      post print_conference_badges_path(format: :pdf), params: { ticket_ids: [ ticket.id ], confirmed: "true" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF-")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
      expect(ticket.reload.attributes).to eq(before)
      expect(AdminUser.pluck(:id, :role)).to eq(roles)
      expect(CheckinAudit.count).to eq(0)
      expect(EventSlotRedemption.count).to eq(0)
      expect(ActiveStorage::Attachment.count).to eq(0)
    end

    it "requires renewed authentication when the #{role} staff session is revoked before printing" do
      operator = create(:admin_user, role:)
      sign_in_admin(operator)
      get conference_badges_path
      expect(response).to have_http_status(:ok)
      operator.sessions.destroy_all
      post print_conference_badges_path(format: :pdf), params: { ticket_ids: [ ticket.id ], confirmed: true }
      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include(ticket.secret)
      expect(CheckinAudit.count).to eq(0)
    end
  end

  [ false, true ].each do |tenant_owner|
    it "does not authorize a #{tenant_owner ? 'tenant organizer' : 'signed-in attendee'} account as DQOR staff" do
      user = User.create!(email: "synthetic-badge-attendee@example.test")
      if tenant_owner
        organization = Organization.create!(name: "Other organizer", slug: "badge-other-organizer")
        Membership.create!(organization:, user:, role: :owner)
      end
      token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
      get account_magic_path(token:)
      roles = AdminUser.pluck(:id, :role)
      [ conference_badges_path, sample_conference_badges_path, sample_conference_badges_path(format: :pdf) ].each do |path|
        get path
        expect(response).to redirect_to(new_session_path)
      end
      post print_conference_badges_path(format: :pdf), params: { ticket_ids: [ ticket.id ], confirmed: true }
      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include(ticket.secret)
      expect(AdminUser.pluck(:id, :role)).to eq(roles)
      expect(CheckinAudit.count).to eq(0)
    end
  end

  it "lists eligible names and IDs without roster secrets or private details" do
    sign_in_admin(admin)
    ticket
    excluded = create(:ticket, order: create(:order, :paid), ticket_type: create(:ticket_type, slug: "rails-girls-pune"), attendee_name: "Workshop only")
    missing = create(:ticket, order: ticket.order, ticket_type: type, attendee_name: nil)
    get conference_badges_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ticket.attendee_name, "Missing attendee name", "Add attendee details")
    expect(response.body).not_to include(ticket.secret, ticket.claim_token, ticket.attendee_email, excluded.attendee_name)
    expect(Nokogiri::HTML(response.body).at_css("#badge_ticket_#{missing.id}")["disabled"]).not_to be_nil
    expect(response.body).not_to include("<svg")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
  end

  it "requires confirmation before generating entry QR codes" do
    sign_in_admin(admin)
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Confirm between 1 and 50")
    expect(response.body).not_to include("<svg")
  end

  it "allows a CSRF-protected selected HTML POST, escapes text and does not write attendance" do
    sign_in_admin(admin)
    before = ticket.attributes
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ], companies: { ticket.id.to_s => "<script>alert('company')</script>" }, confirmed: "true" }

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css(".conference-badge").length).to eq(1)
    expect(html.at_css(".badge-name").text).to eq(ticket.attendee_name)
    expect(html.at_css(".badge-company").text).to eq("<script>alert('company')</script>")
    expect(html.css("script")).to be_empty
    expect(response.body).not_to include(ticket.secret, ticket.claim_token, ticket.attendee_email, ticket.order.email, ticket.order.buyer_phone)
    expect(ticket.reload.attributes).to eq(before)
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
  end

  it "rejects a missing CSRF token when forgery protection is enabled" do
    sign_in_admin(admin)
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ], confirmed: true }
    expect(response).to have_http_status(:unprocessable_content)
    expect(CheckinAudit.count).to eq(0)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "revalidates canceled eligibility and rejects the whole batch" do
    sign_in_admin(admin)
    other = create(:ticket, order: ticket.order, ticket_type: type, attendee_name: "Canceled person", canceled_at: Time.current)
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id, other.id ], confirmed: true }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include("<svg")
  end

  it "rejects company text for unselected passes but accepts native blank inputs" do
    sign_in_admin(admin)
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ], companies: { "999999" => "Unselected" }, confirmed: true }
    expect(response).to have_http_status(:unprocessable_content)
    post print_conference_badges_path, params: { ticket_ids: [ ticket.id ], companies: { "999999" => "" }, confirmed: true }
    expect(response).to have_http_status(:ok)
  end

  it "serves a real admin sample PDF without admission data or writes" do
    sign_in_admin(admin)
    get sample_conference_badges_path(format: :pdf)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to start_with("%PDF-")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(Ticket.count).to eq(0)
    expect(CheckinAudit.count).to eq(0)
  end
end
