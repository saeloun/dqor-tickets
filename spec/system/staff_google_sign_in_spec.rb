require "rails_helper"

RSpec.describe "Staff Google sign-in browser", type: :system do
  around do |example|
    original_mode = OmniAuth.config.test_mode
    original_auth = OmniAuth.config.mock_auth[:google_oauth2]
    original_forgery = ActionController::Base.allow_forgery_protection
    original_credentials = ENV.values_at("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET")
    OmniAuth.config.test_mode = true
    ActionController::Base.allow_forgery_protection = true
    ENV["GOOGLE_CLIENT_ID"] = "test-client-id"
    ENV["GOOGLE_CLIENT_SECRET"] = "test-client-secret"
    example.run
  ensure
    OmniAuth.config.test_mode = original_mode
    OmniAuth.config.mock_auth[:google_oauth2] = original_auth
    ActionController::Base.allow_forgery_protection = original_forgery
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET].zip(original_credentials).each do |key, value|
      value ? ENV[key] = value : ENV.delete(key)
    end
  end

  def google_identity(email:, verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "synthetic-browser-staff", info: { email:, name: "Synthetic Staff" },
      extra: { raw_info: { email_verified: verified } })
  end

  def screenshot(name)
    return unless ENV["STAFF_GOOGLE_EVIDENCE_DIR"].present?

    if %w[staff-google-login staff-google-denied].include?(name)
      expect(page).to have_css(".auth-page .status-card", style: { opacity: "1" })
    end
    page.save_screenshot(File.join(ENV.fetch("STAFF_GOOGLE_EVIDENCE_DIR"), "#{name}.png"), full: true)
  end

  %i[admin desk].each do |role|
    it "lets existing #{role} staff use Google from the real login page and keeps their role" do
      staff = create(:admin_user, role:, email: "#{role}@example.test")
      google_identity(email: staff.email)
      visit new_session_path
      expect(page).to have_button("Sign in")
      expect(page).to have_button("Continue with Google")
      screenshot("staff-google-login")
      click_button "Continue with Google"
      expect(page).to have_current_path(role == :desk ? checkin_path : "/avo/dashboard")
      expect(Session.sole.admin_user).to eq(staff)
      expect(staff.reload.role).to eq(role.to_s)
      expect(User.count).to eq(0)
      screenshot("staff-google-#{role}")
      visit "/avo/dashboard" if role == :desk
      expect(page).to have_current_path(checkin_path) if role == :desk
    end
  end

  it "keeps denied Google identities on staff login without provisioning an attendee" do
    google_identity(email: "unknown@example.test")
    visit new_session_path
    click_button "Continue with Google"
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_content("Google sign-in requires an existing staff account")
    expect(page).to have_button("Sign in")
    expect(AdminUser.count).to eq(0)
    expect(User.count).to eq(0)
    expect(Session.count).to eq(0)
    screenshot("staff-google-denied")
  end

  it "rejects an unverified Google identity and still permits the existing staff password" do
    staff = create(:admin_user, role: :desk, password: "password123")
    google_identity(email: staff.email, verified: false)
    visit new_session_path
    click_button "Continue with Google"
    expect(page).to have_content("Google sign-in requires an existing staff account")
    expect(Session.count).to eq(0)
    fill_in "Email address", with: staff.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(checkin_path)
    expect(Session.sole.admin_user).to eq(staff)
    expect(User.count).to eq(0)
    screenshot("staff-password-fallback")
  end
end
