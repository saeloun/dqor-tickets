require "rails_helper"

RSpec.describe "Authentication", type: :system do
  let(:password) { "password123" }
  let!(:admin) { create(:admin_user, email: "admin@example.com", password:) }

  def sign_in(email:, password:)
    visit new_session_path
    fill_in "email", with: email
    fill_in "password", with: password
    click_button "Sign in"
  end

  def sign_out
    page.execute_script(<<~JS)
      const form = document.createElement("form");
      form.method = "post";
      form.action = "/session";
      form.dataset.turbo = "false";

      const override = document.createElement("input");
      override.name = "_method";
      override.value = "delete";
      form.appendChild(override);

      const meta = document.querySelector('meta[name="csrf-token"]');
      if (meta) {
        const token = document.createElement("input");
        token.name = "authenticity_token";
        token.value = meta.content;
        form.appendChild(token);
      }

      document.body.appendChild(form);
      form.submit();
    JS
  end

  describe "signing in" do
    it "lands an admin on an authenticated page and records a session" do
      sign_in(email: admin.email, password:)

      expect(page).to have_current_path(rails_health_check_path)
      expect(admin.sessions.count).to eq(1)

      visit checkin_path
      expect(page).to have_current_path(checkin_path)
    end

    it "normalizes the email so casing and whitespace do not matter" do
      sign_in(email: "  ADMIN@Example.com  ", password:)

      expect(page).to have_current_path(rails_health_check_path)
      expect(admin.sessions.count).to eq(1)
    end

    it "rejects a wrong password without creating a session" do
      sign_in(email: admin.email, password: "wrong-password")

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Try another email address or password.")
      expect(Session.count).to eq(0)
    end

    it "rejects an unknown email without creating a session" do
      sign_in(email: "nobody@example.com", password:)

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Try another email address or password.")
      expect(Session.count).to eq(0)
    end
  end

  describe "protected pages" do
    it "sends a signed out visitor to the sign-in page" do
      visit checkin_path

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_button("Sign in")
    end

    it "returns the admin to the originally requested page after signing in" do
      visit checkin_path
      expect(page).to have_current_path(new_session_path)

      fill_in "email", with: admin.email
      fill_in "password", with: password
      click_button "Sign in"

      expect(page).to have_current_path(checkin_path)
    end

    it "returns the admin to the Avo dashboard requested before signing in" do
      visit "/avo/dashboard"
      expect(page).to have_current_path(new_session_path)

      fill_in "email", with: admin.email
      fill_in "password", with: password
      click_button "Sign in"

      expect(page).to have_current_path("/avo/dashboard")
    end
  end

  describe "signing out" do
    it "destroys the session and re-protects admin pages" do
      sign_in(email: admin.email, password:)
      expect(Session.count).to eq(1)

      visit checkin_path
      sign_out

      expect(page).to have_current_path(new_session_path)
      expect(Session.count).to eq(0)

      visit checkin_path
      expect(page).to have_current_path(new_session_path)
      expect(page).to have_button("Sign in")
    end
  end

  describe "password reset" do
    before { ActionMailer::Base.deliveries.clear }

    def request_reset_for(email)
      visit new_password_path
      fill_in "email", with: email
      click_button "Email reset instructions"
    end

    def reset_token_from_last_email
      body = ActionMailer::Base.deliveries.last.body.encoded
      body[%r{/passwords/([^/"\s]+)/edit}, 1]
    end

    it "enqueues a reset email for a known address" do
      expect {
        request_reset_for(admin.email)
        expect(page).to have_content("Password reset instructions sent")
      }.to have_enqueued_mail(PasswordsMailer, :reset).with(admin)

      expect(page).to have_current_path(new_session_path)
    end

    it "shows the same message and sends nothing for an unknown address" do
      expect {
        request_reset_for("nobody@example.com")
        expect(page).to have_content("Password reset instructions sent")
      }.not_to have_enqueued_mail(PasswordsMailer, :reset)

      expect(page).to have_current_path(new_session_path)
    end

    it "lets the admin set a new password from the emailed link and sign in with it" do
      perform_enqueued_jobs do
        request_reset_for(admin.email)
        expect(page).to have_content("Password reset instructions sent")
      end

      token = reset_token_from_last_email
      expect(token).to be_present

      visit edit_password_path(token)
      fill_in "password", with: "brand-new-secret"
      fill_in "password_confirmation", with: "brand-new-secret"
      click_button "Save"

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Password has been reset.")

      sign_in(email: admin.email, password: "brand-new-secret")
      expect(page).to have_current_path(rails_health_check_path)
    end

    it "rejects the old password once it has been reset" do
      visit edit_password_path(admin.password_reset_token)
      fill_in "password", with: "brand-new-secret"
      fill_in "password_confirmation", with: "brand-new-secret"
      click_button "Save"

      expect(page).to have_content("Password has been reset.")

      sign_in(email: admin.email, password:)

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Try another email address or password.")
    end

    it "signs out every existing session when the password is reset" do
      sign_in(email: admin.email, password:)
      expect(Session.count).to eq(1)

      visit edit_password_path(admin.password_reset_token)
      fill_in "password", with: "brand-new-secret"
      fill_in "password_confirmation", with: "brand-new-secret"
      click_button "Save"

      expect(page).to have_content("Password has been reset.")
      expect(Session.count).to eq(0)

      visit checkin_path
      expect(page).to have_current_path(new_session_path)
    end

    it "keeps the admin on the form when the confirmation does not match" do
      visit edit_password_path(admin.password_reset_token)
      fill_in "password", with: "brand-new-secret"
      fill_in "password_confirmation", with: "something-else"
      click_button "Save"

      expect(page).to have_content("Password confirmation doesn't match Password")
      expect(page).to have_button("Save")
      expect(admin.reload.authenticate(password)).to be_truthy
    end

    it "reports the real reason when the new password is too short" do
      visit edit_password_path(admin.password_reset_token)
      fill_in "password", with: "short1"
      fill_in "password_confirmation", with: "short1"
      click_button "Save"

      expect(page).to have_content("Password is too short (minimum is 8 characters)")
      expect(page).to have_no_content("Passwords did not match.")
      expect(admin.reload.authenticate(password)).to be_truthy
    end

    it "rejects a forged token" do
      visit edit_password_path("not-a-real-token")

      expect(page).to have_current_path(new_password_path)
      expect(page).to have_content("Password reset link is invalid or has expired.")
    end

    it "rejects a token that has expired" do
      expired_token = travel_to(16.minutes.ago) { admin.password_reset_token }

      visit edit_password_path(expired_token)

      expect(page).to have_current_path(new_password_path)
      expect(page).to have_content("Password reset link is invalid or has expired.")
    end
  end
end
