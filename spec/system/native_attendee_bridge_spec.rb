require "rails_helper"
require "net/http"

RSpec.describe "Native attendee browser consent", type: :system, native_attendee_bridge: true do
  let!(:user) { User.create!(email: "native-browser-synthetic@example.test", name: "Synthetic Browser Attendee") }
  let!(:ticket) { create(:ticket, order: create(:order, :paid), attendee_email: user.email) }

  it "uses local Chromium email/consent and an intercepted callback before native JSON reads and revocation" do
    ActionMailer::Base.deliveries.clear
    browser = page.driver.browser
    callbacks = Queue.new
    observations = Queue.new
    browser.network.intercept
    interceptor = browser.on(:request) do |request|
      uri = URI.parse(request.url)
      observations << [ request.method, uri.path, request.headers.transform_keys(&:downcase) ]
      if %w[127.0.0.1 localhost].include?(uri.host)
        request.continue
      elsif request.url.start_with?(NativeAttendeeBridgeHelpers::CALLBACK + "?")
        callbacks << request.url
        request.respond(responseCode: 200, body: "Synthetic callback intercepted locally. No request reached production.", responseHeaders: { "content-type" => "text/plain", "cache-control" => "private, no-store", "referrer-policy" => "no-referrer", "content-security-policy" => "default-src 'none'" })
      else
        request.abort
      end
    end
    params = { client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK, state: NativeAttendeeBridgeHelpers::STATE,
      code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), code_challenge_method: "S256" }
    visit native_attendee_authorize_path(params)
    expect(page).to have_css("h1", text: "Connect DQOR for iOS")
    fill_in "Account email", with: user.email
    perform_enqueued_jobs(only: NativeAttendeeVerificationJob) { click_button "Send verification link" }
    expect(page).to have_css("h1", text: "Check your email")
    expect(NativeAttendeeSession.count).to eq(0)
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    visit native_verification_path(mail)
    expect(page).to have_css("h1", text: "Approve DQOR for iOS?")
    expect(page).to have_content(user.email)
    expect(page).to have_content("30 minutes")
    page.save_screenshot(Rails.root.join("tmp/capybara/native-attendee-consent.png"))
    click_button "Approve account and pass reads"
    expect(page).to have_content("Synthetic callback intercepted locally")
    callback = URI.parse(callbacks.pop)
    values = Rack::Utils.parse_query(callback.query)
    expect(values.fetch("state")).to eq(NativeAttendeeBridgeHelpers::STATE)
    server = URI.parse(Capybara.current_session.server.base_url)
    recorded = []
    recorded << observations.pop until observations.empty?
    forms = recorded.select { |method, path, _headers| method == "POST" && path.start_with?("/account/native/") }
    expect(forms.size).to eq(2)
    forms.each { |_method, _path, headers| expect(headers.fetch("origin")).to eq(server.to_s) }
    recorded.filter_map { |_method, _path, headers| headers["referer"] }.each do |referrer|
      value = URI.parse(referrer)
      expect(value.path).to eq("/")
      expect(value.query).to be_nil
      expect(value.fragment).to be_nil
    end
    http = Net::HTTP.new(server.host, server.port)
    request = Net::HTTP::Post.new("/api/native/attendee/v1/token", "Content-Type" => "application/json")
    request.body = { code: values.fetch("code"), code_verifier: NativeAttendeeBridgeHelpers::VERIFIER,
      client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK }.to_json
    result = http.request(request)
    expect(result.code).to eq("200")
    expect(result["Cache-Control"]).to eq("private, no-store")
    token = JSON.parse(result.body).fetch("access_token")
    headers = { "Authorization" => "Bearer #{token}" }
    result = http.request(Net::HTTP::Get.new("/api/native/attendee/v1/passes", headers))
    expect(result.code).to eq("200")
    expect(JSON.parse(result.body).fetch("passes").pluck("id")).to eq([ ticket.id.to_s ])
    result = http.request(Net::HTTP::Delete.new("/api/native/attendee/v1/session", headers))
    expect(result.code).to eq("204")
    result = http.request(Net::HTTP::Get.new("/api/native/attendee/v1/account", headers))
    expect(result.code).to eq("401")
    expect(NativeAttendeeSession.last.revoked_at).to be_present
  ensure
    browser&.page&.command("Fetch.disable")
    browser&.page&.off(:request, interceptor) if interceptor
  end
end
