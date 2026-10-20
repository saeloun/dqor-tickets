require "rails_helper"

RSpec.describe "Account QR scanner link", type: :request do
  let(:attendee) { User.create!(email: "attendee@example.com", name: "Account attendee") }

  def sign_in_attendee(user = attendee)
    token = Rails.application.message_verifier(:account_magic_link)
      .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token:)
  end

  def scanner_link
    Nokogiri::HTML(response.body).at_css(".account-header .account-actions a[href='#{checkin_path}']")
  end

  [ :account_root_path, :account_settings_path ].each do |route|
    describe route.to_s do
      it "requires attendee sign-in for anonymous visitors" do
        get public_send(route)

        expect(response).to redirect_to(account_sign_in_path)
        expect(scanner_link).to be_nil
      end

      it "hides the scanner from an ordinary attendee" do
        sign_in_attendee

        get public_send(route)

        expect(response).to have_http_status(:ok)
        expect(scanner_link).to be_nil
        expect(response.body).not_to include("QR scanner")
      end

      [ :admin, :desk ].each do |role|
        context "with a #{role} staff account" do
          let(:staff) { create(:admin_user, role:, password: "password123") }

          it "shows the scanner for a signed-in staff session alongside the attendee session" do
            sign_in_attendee
            sign_in_admin(staff)

            get public_send(route)

            expect(response).to have_http_status(:ok)
            expect(scanner_link).to be_present
            expect(scanner_link.text).to eq("QR scanner")
            expect(scanner_link["class"].split).to include("btn", "btn-secondary")
            expect(response.body).to include(attendee.email)

            get scanner_link["href"]

            expect(response).to have_http_status(:ok)
            expect(response.body).to include("Attendee check-in")
          end

          it "does not treat a matching attendee email as a staff session" do
            sign_in_attendee(User.create!(email: staff.email))

            get public_send(route)

            expect(response).to have_http_status(:ok)
            expect(scanner_link).to be_nil
            expect(staff.sessions).to be_empty
          end

          it "keeps the attendee sign-in guard for a staff-only session" do
            sign_in_admin(staff)

            get public_send(route)

            expect(response).to redirect_to(account_sign_in_path)
            expect(scanner_link).to be_nil
          end

          it "hides the scanner after the staff session is revoked" do
            sign_in_attendee
            sign_in_admin(staff)
            get public_send(route)
            expect(scanner_link).to be_present
            staff.sessions.destroy_all

            get public_send(route)

            expect(response).to have_http_status(:ok)
            expect(scanner_link).to be_nil
            expect(response.body).to include(attendee.email)
          end

          it "hides the scanner after staff sign-out while preserving the attendee account" do
            sign_in_attendee
            sign_in_admin(staff)
            get public_send(route)
            expect(scanner_link).to be_present

            delete session_path
            get public_send(route)

            expect(response).to have_http_status(:ok)
            expect(scanner_link).to be_nil
            expect(response.body).to include(attendee.email)
            expect(staff.sessions).to be_empty
          end
        end
      end
    end
  end

  [ :admin, :desk ].each do |role|
    it "keeps scanner HTML and JSON protected for an attendee matching a #{role} email" do
      staff = create(:admin_user, role:, password: "password123")
      sign_in_attendee(User.create!(email: staff.email))

      get checkin_path

      expect(response).to redirect_to(new_session_path)

      get checkin_path, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include(
        "state" => "error",
        "message" => "Session expired. Sign in before checking in."
      )
    end
  end
end
