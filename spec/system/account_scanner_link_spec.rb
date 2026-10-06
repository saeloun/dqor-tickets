require "rails_helper"

RSpec.describe "Account QR scanner navigation", type: :system do
  def sign_in_attendee(user)
    token = Rails.application.message_verifier(:account_magic_link)
      .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token:)
    expect(page).to have_current_path(account_root_path)
  end

  def sign_in_staff(staff)
    visit checkin_path
    expect(page).to have_current_path(new_session_path)
    fill_in "email", with: staff.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(checkin_path)
    expect(page).to have_content("Attendee check-in")
  end

  { mobile: [ 390, 844 ], desktop: [ 1400, 1400 ] }.each do |device, dimensions|
    context "on #{device}" do
      before { page.driver.browser.resize(width: dimensions.first, height: dimensions.last) }

      [ :admin, :desk ].each do |role|
        it "opens the scanner from the dashboard and settings for signed-in #{role} staff" do
          attendee = User.create!(email: "attendee@example.com", name: "Account attendee")
          staff = create(:admin_user, role:, password: "password123")
          sign_in_attendee(attendee)
          sign_in_staff(staff)

          [ account_root_path, account_settings_path ].each do |path|
            visit path
            expect(page).to have_content(attendee.email)
            within ".account-header .account-actions" do
              expect(page).to have_link("QR scanner", href: checkin_path, visible: true)
              click_link "QR scanner"
            end
            expect(page).to have_current_path(checkin_path)
            expect(page).to have_content("Attendee check-in")
            expect(page).to have_button("Request Camera Permissions")
          end

          click_button "Sign out"
          expect(page).to have_current_path(new_session_path)
          expect(staff.sessions).to be_empty

          [ account_root_path, account_settings_path ].each do |path|
            visit path
            expect(page).to have_current_path(path)
            expect(page).to have_content(attendee.email)
            expect(page).to have_no_link("QR scanner")
          end
        end

        it "hides the scanner from an attendee matching a #{role} staff email without staff sign-in" do
          staff = create(:admin_user, role:, password: "password123")
          sign_in_attendee(User.create!(email: staff.email))

          [ account_root_path, account_settings_path ].each do |path|
            visit path
            expect(page).to have_current_path(path)
            expect(page).to have_no_link("QR scanner")
          end
          expect(staff.sessions).to be_empty
        end
      end
    end
  end
end
