require "rails_helper"

RSpec.describe "Rate limits", type: :request do
  describe "ticket access requests" do
    let(:notice) { "If we have tickets for that address, we have sent a link" }

    def request_link(email)
      post find_tickets_path, params: { email: }
    end

    it "stops a flood from one address after three tries in an hour" do
      order = create(:order, :paid, email: "buyer@example.com")
      create(:ticket, order:)

      expect do
        3.times { request_link("buyer@example.com") }
      end.to have_enqueued_mail(TicketAccessMailer, :link).exactly(3).times

      expect do
        request_link("buyer@example.com")
      end.not_to have_enqueued_mail(TicketAccessMailer, :link)
    end

    it "answers a throttled request exactly like an accepted one, so it cannot be used as an oracle" do
      order = create(:order, :paid, email: "buyer@example.com")
      create(:ticket, order:)
      3.times { request_link("buyer@example.com") }

      request_link("buyer@example.com")
      throttled = { status: response.status, location: response.location, flash: flash[:notice] }

      request_link("someone-else@example.com")
      accepted = { status: response.status, location: response.location, flash: flash[:notice] }

      expect(throttled).to eq(accepted)
      expect(throttled[:flash]).to include(notice)
      expect(throttled[:status]).to eq(302)
    end

    it "keeps one address's limit away from another's" do
      first = create(:order, :paid, email: "first@example.com")
      create(:ticket, order: first)
      second = create(:order, :paid, email: "second@example.com")
      create(:ticket, order: second)
      3.times { request_link("first@example.com") }

      expect do
        request_link("second@example.com")
      end.to have_enqueued_mail(TicketAccessMailer, :link).once
    end

    it "stops a flood from one address book across many addresses" do
      5.times { |index| request_link("nobody-#{index}@example.com") }

      request_link("nobody-6@example.com")

      expect(response).to redirect_to(find_tickets_path)
      expect(flash[:notice]).to include(notice)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "sign in" do
    it "throttles repeated failures" do
      admin = create(:admin_user, password: "password123")

      10.times { post session_path, params: { email: admin.email, password: "wrong" } }
      post session_path, params: { email: admin.email, password: "wrong" }

      expect(flash[:alert]).to eq("Try again later.")
      expect(Session.count).to be_zero
    end
  end

  describe "password reset requests" do
    it "throttles repeated requests" do
      admin = create(:admin_user)

      10.times { post passwords_path, params: { email: admin.email } }
      post passwords_path, params: { email: admin.email }

      expect(flash[:alert]).to eq("Try again later.")
    end
  end
end
