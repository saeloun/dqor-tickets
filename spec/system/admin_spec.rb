require "rails_helper"

RSpec.describe "Avo admin", type: :system do
  let(:admin) { create(:admin_user, password: "password123") }

  def sign_in_through_the_form(user = admin)
    visit new_session_path
    fill_in "email", with: user.email
    fill_in "password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(rails_health_check_path)
  end

  it "sends an unauthenticated visitor to the sign-in form" do
    visit "/avo"

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_button("Sign in")
  end

  it "sends an unauthenticated visitor back to the page they wanted after signing in" do
    visit "/avo/resources/orders"
    expect(page).to have_current_path(new_session_path)

    fill_in "email", with: admin.email
    fill_in "password", with: "password123"
    click_on "Sign in"

    expect(page).to have_current_path("/avo/resources/orders")
    expect(page).to have_content("Orders")
  end

  context "when signed in as an admin" do
    let!(:ticket_type) { create(:ticket_type, name: "Conference Pass", capacity: 10) }

    let!(:paid_order) do
      create(:order, :paid, code: "PAYDAAAA", email: "paid@example.com", buyer_name: "Paid Buyer", total_paise: 350_000).tap do |order|
        create(:ticket, order:, ticket_type:, attendee_name: "Ada Lovelace")
      end
    end

    let!(:pending_order) do
      create(:order, code: "PENDBBBB", email: "waiting@example.com", buyer_name: "Pending Buyer", total_paise: 350_000).tap do |order|
        create(:ticket, order:, ticket_type:, attendee_name: "Grace Hopper")
      end
    end

    before { sign_in_through_the_form }

    it "reaches the sales dashboard" do
      visit "/avo/dashboard"

      expect(page).to have_current_path("/avo/dashboard")
      expect(page).to have_content("Sales dashboard")
      expect(page).to have_content("Gross revenue")
      expect(page).to have_content("₹3,500.00")
      expect(page).to have_content("Sold by ticket type")
      expect(page).to have_content("Conference Pass")
    end

    it "lists orders with their code, status and buyer email on the index" do
      visit "/avo/resources/orders"

      expect(page).to have_current_path(%r{\A/avo/resources/orders})
      expect(page).to have_content("PAYDAAAA")
      expect(page).to have_content("paid@example.com")
      expect(page).to have_content("Paid Buyer")
      expect(page).to have_content("PENDBBBB")
      expect(page).to have_content("waiting@example.com")
      expect(page).to have_content("Pending Buyer")
      expect(page).to have_content("2 records")
    end

    it "narrows the index down with the status filter" do
      visit "/avo/resources/orders"
      expect(page).to have_content("PENDBBBB")

      click_on "Filters"
      select "Paid", from: "avo_filters_status"

      expect(page).to have_content("PAYDAAAA")
      expect(page).to have_no_content("PENDBBBB")
      expect(page).to have_content("1 record")
    end

    it "finds an order by code with the resource search" do
      visit "/avo/resources/orders"
      expect(page).to have_content("PENDBBBB")

      find("input[name='q']").set("paydaaaa")

      expect(page).to have_content("PAYDAAAA")
      expect(page).to have_no_content("PENDBBBB")
      expect(page).to have_content("1 record")
    end

    it "finds an order by buyer email with the resource search" do
      visit "/avo/resources/orders"
      expect(page).to have_content("PAYDAAAA")

      find("input[name='q']").set("waiting@example.com")

      expect(page).to have_content("PENDBBBB")
      expect(page).to have_no_content("PAYDAAAA")
      expect(page).to have_content("1 record")
    end

    it "offers the order actions on the index" do
      visit "/avo/resources/orders"
      expect(page).to have_content("PAYDAAAA")

      click_on "Actions"

      expect(page).to have_link("Resend confirmation")
      expect(page).to have_link("Refund selected tickets")
      expect(page).to have_link("Export orders CSV")
      expect(page).to have_link("Export attendees CSV")
    end

    it "re-delivers the confirmation when the resend action runs on a paid order" do
      allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
      Invoice.issue_for!(paid_order)

      visit "/avo/resources/orders/#{paid_order.id}"
      expect(page).to have_content("PAYDAAAA")

      expect {
        click_on "Actions"
        click_on "Resend confirmation"
        expect(page).to have_content("Confirmation queued")
      }.to have_enqueued_mail(OrderMailer, :confirmation).with(paid_order)

      expect(paid_order.invoices.invoice.sole.pdf).to be_attached
    end

    it "renders the other resource indexes without error" do
      create(:coupon, code: "EARLYBIRD", ticket_type:)

      {
        "tickets" => "Ada Lovelace",
        "coupons" => "EARLYBIRD",
        "ticket_types" => "Conference Pass"
      }.each do |resource, expected_content|
        visit "/avo/resources/#{resource}"

        expect(page).to have_current_path(%r{\A/avo/resources/#{resource}})
        expect(page).to have_content(expected_content)
        expect(page).to have_no_content("We're sorry, but something went wrong")
      end
    end

    it "renders the invoices index with an issued invoice" do
      allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
      invoice = Invoice.issue_for!(paid_order)

      visit "/avo/resources/invoices"

      expect(page).to have_content(invoice.number)
      expect(page).to have_content("invoice")
      expect(page).to have_content("1 record")
    end
  end
end
