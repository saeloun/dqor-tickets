require "rails_helper"

RSpec.describe "Free registration windows", type: :request do
  let!(:owner) { create(:user_for_free_pilot) }
  let!(:attendee) { create(:user_for_free_pilot) }
  let!(:org) { Organization.create!(name: "Window Org", slug: "window-org") }
  let!(:membership) { Membership.create!(organization: org, user: owner, role: :owner) }
  let!(:event) { org.events.create!(title: "Window event", slug: "meetup", status: :published, timezone: "Asia/Kolkata", starts_at: Time.utc(2027, 1, 2, 12), ends_at: Time.utc(2027, 1, 2, 16)) }
  let!(:type) { create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 1, free_published_at: Time.current) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_registration_windows_enabled).and_return(true)
    travel_to Time.utc(2027, 1, 1, 10)
  end

  after { travel_back }

  def access
    { user: owner, organization_id: org.id, event_id: event.id, ticket_type_id: type.id }
  end

  def login(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  def save_window(opens: "2027-01-01T16:00", closes: "2027-01-02T20:00")
    window = FreeEvents::RegistrationWindow.find_by(ticket_type: type)
    FreeEvents::Windows.change(**access, action: "save", revision: window&.lock_version || 0, opens_local: opens, closes_local: closes)
  end

  def publish
    window = FreeEvents::RegistrationWindow.find_by!(ticket_type: type)
    FreeEvents::Windows.change(**access, action: "publish", revision: window.lock_version)
  end

  def state
    FreeEvents::Availability.call(event: event.reload, ticket_type: type).state
  end

  it "shows only usable private-pilot navigation for signed-in and signed-out visitors" do
    [ false, true ].each do |signed_in|
      login(owner) if signed_in
      [ false, true ].each do |pilot_enabled|
        allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(pilot_enabled)
        get published_event_path(org.slug, event.slug)
        expect(response).to have_http_status(:ok)
        links = Nokogiri::HTML(response.body).css("nav a")
        if pilot_enabled
          expect(links.map(&:text)).to eq([ signed_in ? "Your free tickets" : "Sign in" ])
          expect(links.first["href"]).to eq(free_tickets_path)
          get links.first["href"]
          expect(response.status).to eq(signed_in ? 200 : 302)
          expect(response).to redirect_to(account_sign_in_path) unless signed_in
        else
          expect(links).to be_empty
          expect(response.body).not_to include("/free/tickets")
        end
      end
    end
  end

  it "previews required-question and unpublished-event/category barriers truthfully" do
    window = save_window(opens: "", closes: "")
    form = FreeEvents::Questions::Editor.change(**access, action: "add", revision: 0, fields: { "label" => "Topic", "type" => "short_text", "required" => "1" })
    FreeEvents::Questions::Editor.change(**access, action: "publish", revision: form.lock_version)
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(false)
    preview = FreeEvents::Availability.call(event: event, ticket_type: type, preview: window)
    expect(preview.state).to eq(:closed)
    expect(preview.message).to include("questions are temporarily unavailable")
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(true)
    event.update!(status: :draft)
    expect(FreeEvents::Availability.call(event: event, ticket_type: type, preview: window).state).to eq(:closed)
    event.update!(status: :published)
    type.update!(free_published_at: nil)
    expect(FreeEvents::Availability.call(event: event, ticket_type: type, preview: window).state).to eq(:closed)
  end

  it "keeps drafts private, rejects stale first-save publication and changes state only on publish" do
    expect(ENV["FREE_REGISTRATION_WINDOWS_ENABLED"]).not_to eq("true")
    window = save_window
    expect(window.draft_opens_at).to eq(Time.utc(2027, 1, 1, 10, 30))
    expect(state).to eq(:available)
    get published_event_path(org.slug, event.slug)
    expect(response.body).not_to include("16:00", "4:00 PM", "Upcoming")
    expect { FreeEvents::Windows.change(**access, action: "publish", revision: 0) }.to raise_error(FreeEvents::Windows::Invalid, /Another organizer/)
    expect(window.reload.published_at).to be_nil
    publish
    expect(state).to eq(:upcoming)
    get published_event_path(org.slug, event.slug)
    expect(response.body).to include("Upcoming", "Asia/Kolkata", "+05:30")
    expect(response.body).not_to include("Register free")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "enforces inclusive opening, exclusive closing, retries and ticket retrieval after closing" do
    save_window
    window = publish
    expect { FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id) }.to raise_error(FreeEvents::Register::Unavailable, /not opened/)
    travel_to window.opens_at
    expect(state).to eq(:available)
    order = FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id)
    expect(state).to eq(:sold_out)
    travel_to window.closes_at - 1.second
    expect(state).to eq(:sold_out)
    travel_to window.closes_at
    expect(state).to eq(:closed)
    expect(FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id)).to eq(order)
    expect { FreeEvents::Register.call(user: owner, event_id: event.id, ticket_type_id: type.id) }.to raise_error(FreeEvents::Register::Unavailable, /closed/)
    login(attendee)
    get free_event_ticket_path(org.slug, event.slug)
    expect(response).to have_http_status(:ok)
    expect(Order.where(event_id: event.id).count).to eq(1)
    expect(Invoice.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end

  it "validates local dates and DST gaps/folds without guessing, retaining the prior draft" do
    window = save_window
    original = window.draft_opens_at
    [ "2027-02-30T12:00", "2027-01-01T24:00", "2027-01-01T12:00Z", "2027-01-01T12:00:00" ].each do |value|
      expect { save_window(opens: value) }.to raise_error(FreeEvents::Windows::Invalid)
      expect(window.reload.draft_opens_at).to eq(original)
    end
    expect { FreeEvents::Windows.parse_local("2027-03-14T02:30", "America/New_York") }.to raise_error(FreeEvents::Windows::Invalid, /does not exist/)
    expect { FreeEvents::Windows.parse_local("2027-11-07T01:30", "America/New_York") }.to raise_error(FreeEvents::Windows::Invalid, /occurs twice/)
    expect(FreeEvents::Windows.parse_local("2027-11-07T03:30", "America/New_York")).to eq(Time.utc(2027, 11, 7, 8, 30))
    expect { save_window(opens: "2027-01-02T20:00", closes: "2027-01-02T20:00") }.to raise_error(FreeEvents::Windows::Invalid, /after it opens/)
    expect { save_window(closes: "2027-01-02T22:00") }.to raise_error(FreeEvents::Windows::Invalid, /after the event ends/)
    event.update!(timezone: "Europe/London")
    expect { publish }.to raise_error(FreeEvents::Windows::Invalid, /timezone changed/)
  end

  it "applies event-end bounds, blank defaults and fail-closed flags while preserving existing retrieval" do
    save_window(opens: "", closes: "")
    publish
    expect(state).to eq(:available)
    FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id)
    allow(Rails.configuration.x).to receive(:free_registration_windows_enabled).and_return(false)
    expect(state).to eq(:closed)
    expect { FreeEvents::Register.call(user: owner, event_id: event.id, ticket_type_id: type.id) }.to raise_error(FreeEvents::Register::Unavailable, /temporarily unavailable/)
    login(attendee)
    get free_event_ticket_path(org.slug, event.slug)
    expect(response).to have_http_status(:ok)
    login(owner)
    get free_event_window_path(org, event, type)
    expect(response).to have_http_status(:not_found)
    allow(Rails.configuration.x).to receive(:free_registration_windows_enabled).and_return(true)
    travel_to event.ends_at
    expect(state).to eq(:closed)
  end

  it "denies foreign organizations, sibling categories, revoked members and unpublished events" do
    window = save_window
    stranger = Organization.create!(name: "Other", slug: "window-other")
    Membership.create!(organization: stranger, user: owner, role: :owner)
    other_event = stranger.events.create!(title: "Private", slug: "private")
    other_type = create(:ticket_type, event_id: other_event.id, price_paise: 0, active: false, hidden: true)
    expect { FreeEvents::Windows.read(**access.merge(ticket_type_id: other_type.id)) { } }.to raise_error(ActiveRecord::RecordNotFound)
    expect { FreeEvents::Windows.read(**access.merge(organization_id: stranger.id)) { } }.to raise_error(ActiveRecord::RecordNotFound)
    expect { ActiveRecord::Base.transaction(requires_new: true) { window.update_columns(event_id: other_event.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    membership.update!(role: :editor)
    expect { publish }.to raise_error(ActiveRecord::RecordNotFound)
    membership.destroy!
    expect { save_window }.to raise_error(ActiveRecord::RecordNotFound)
    event.update!(status: :draft)
    expect(state).to eq(:closed)
    get published_event_path(org.slug, event.slug)
    expect(response).to have_http_status(:not_found)
    expect { FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "keeps required forms consistent across form entry and submission when a window closes" do
    form = FreeEvents::Questions::Editor.change(**access, action: "add", revision: 0, fields: { "label" => "Topic", "type" => "short_text", "required" => "1" })
    version = FreeEvents::Questions::Editor.change(**access, action: "publish", revision: form.lock_version)
    save_window(opens: "", closes: "2027-01-01T16:00")
    window = publish
    login(attendee)
    get new_free_event_registration_path(org.slug, event.slug, type)
    expect(response).to have_http_status(:ok)
    travel_to window.closes_at
    post free_event_registration_path(org.slug, event.slug), params: { ticket_type_id: type.id, form_version_id: version.id, registration_answers: { version.questions.first["id"] => "Ruby" } }
    expect(response).to redirect_to(published_event_path(org.slug, event.slug))
    expect(Order.where(event_id: event.id)).to be_empty
    expect(FreeEvents::Response.count).to eq(0)
    get new_free_event_registration_path(org.slug, event.slug, type)
    expect(response).to redirect_to(published_event_path(org.slug, event.slug))
    travel_to window.closes_at - 1.second
    post free_event_registration_path(org.slug, event.slug), params: { ticket_type_id: type.id, form_version_id: version.id }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("This answer is required")
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(false)
    expect(state).to eq(:closed)
  end
end
