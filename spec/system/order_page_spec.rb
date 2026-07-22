require "rails_helper"

RSpec.describe "Order page", type: :system do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def paid_order_with_invoice(**attributes)
    create(:order, :paid, **attributes).tap { |order| Invoice.issue_for!(order) }
  end

  describe "a paid order" do
    it "renders the confirmation, the buyer email and the invoice download" do
      ticket_type = create(:ticket_type, name: "Conference Pass Regular")
      order = create(:order, :paid, email: "buyer@example.com", buyer_name: "Ada Lovelace")
      create(:ticket, order:, ticket_type:, attendee_name: "Ada Lovelace", attendee_email: "ada@example.com")
      invoice = Invoice.issue_for!(order)

      visit order_path(order.code)

      expect(page).to have_css("h1", text: "Your tickets are confirmed")
      expect(page).to have_css(".status-card--paid")
      expect(page).to have_css(".section-label", text: order.code)
      expect(page).to have_content("We sent the invoice to buyer@example.com")
      expect(page).to have_css("h3", text: "Conference Pass Regular")
      expect(page).to have_link("Download tax invoice", href: rails_blob_path(invoice.reload.pdf, disposition: "attachment"))
      expect(page).to have_title("Order #{order.code} · Deccan Queen on Rails")
    end

    it "renders the assigned attendee and their ticket download" do
      order = paid_order_with_invoice
      ticket = create(:ticket, order:, attendee_name: "Grace Hopper", attendee_email: "grace@example.com")
      ticket.attach_pdf!

      visit order_path(order.code)

      expect(page).to have_css("h2", text: "1 of 1 tickets assigned")
      expect(page).to have_content("Grace Hopper")
      expect(page).to have_content("grace@example.com")
      expect(page).to have_link("Download ticket", href: rails_blob_path(ticket.pdf, disposition: "attachment"))
      expect(page).to have_no_field("claim_link_#{ticket.id}")
    end

    it "renders a claim link and no attendee for an unassigned ticket" do
      order = paid_order_with_invoice
      ticket = create(:ticket, order:, attendee_name: nil, attendee_email: nil)

      visit order_path(order.code)

      expect(page).to have_css("h2", text: "0 of 1 tickets assigned")
      expect(page).to have_content("Assign each ticket now, or share its private claim link with the attendee.")
      expect(page).to have_field("claim_link_#{ticket.id}", readonly: true)
      expect(find_field("claim_link_#{ticket.id}").value).to end_with(ticket_claim_path(ticket.claim_token))
      expect(page).to have_no_link("Download ticket")
    end

    it "lists every ticket type in the order and skips canceled tickets" do
      order = paid_order_with_invoice
      create(:ticket, order:, ticket_type: create(:ticket_type, name: "Conference Pass"))
      create(:ticket, order:, ticket_type: create(:ticket_type, name: "Explore Pune Day"))
      create(:ticket, order:, ticket_type: create(:ticket_type, name: "Refunded Pass"), canceled_at: Time.current)

      visit order_path(order.code)

      expect(page).to have_css("h2", text: "2 of 2 tickets assigned")
      expect(page).to have_css("article.ticket-assignment", count: 2)
      expect(page).to have_css("h3", text: "Conference Pass")
      expect(page).to have_css("h3", text: "Explore Pune Day")
      expect(page).to have_no_css("h3", text: "Refunded Pass")
    end

    it "offers credit note downloads alongside the tax invoice" do
      order = paid_order_with_invoice
      create(:ticket, order:)
      invoice = order.invoices.invoice.sole
      credit_note = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: invoice.line_items)
      credit_note.attach_pdf!

      visit order_path(order.code)

      expect(page).to have_link("Download tax invoice")
      expect(page).to have_link("Download credit note #{credit_note.number}", href: rails_blob_path(credit_note.pdf, disposition: "attachment"))
    end

    it "generates the missing invoice pdf on first view" do
      order = paid_order_with_invoice
      create(:ticket, order:)
      invoice = order.invoices.invoice.sole
      expect(invoice.pdf).not_to be_attached

      visit order_path(order.code)

      expect(page).to have_link("Download tax invoice")
      expect(invoice.reload.pdf).to be_attached
    end

    it "still shows the tickets when the paid order has no invoice yet" do
      order = create(:order, :paid)
      create(:ticket, order:)

      visit order_path(order.code)

      expect(page).to have_content("Your tickets are confirmed")
      expect(page).to have_no_content("The page you were looking for doesn't exist")
      expect(page).to have_no_link("Download tax invoice")
    end
  end

  describe "a pending order" do
    it "renders the polling confirmation state" do
      order = create(:order)

      visit order_path(order.code)

      expect(page).to have_css("h1", text: "Confirming your payment")
      expect(page).to have_content("Razorpay is confirming the payment. This page updates automatically.")
      expect(page).to have_content("Please keep this page open.")
      expect(page).to have_css("turbo-frame#order_status[data-poll-active-value='true']")
      expect(page).to have_css(".status-card--pending .spinner", visible: :all)
      expect(page).to have_no_link("Download tax invoice")
    end

    it "renders the failure state after a failed payment" do
      order = create(:order)
      create(:payment_event, order:, kind: "payment.failed")

      visit order_path(order.code)

      expect(page).to have_css("h1", text: "Confirming your payment")
      expect(page).to have_content("The payment failed. No charge was confirmed.")
      expect(page).to have_link("Choose tickets", href: root_path)
      expect(page).to have_no_content("Please keep this page open.")
    end

    it "swaps to the confirmed view once the order is paid" do
      order = create(:order)
      create(:ticket, order:, attendee_name: nil, attendee_email: nil)

      visit order_path(order.code)
      expect(page).to have_css("h1", text: "Confirming your payment")

      order.update!(status: :paid)
      Invoice.issue_for!(order)

      expect(page).to have_css("h1", text: "Your tickets are confirmed", wait: 15)
      expect(page).to have_link("Download tax invoice")
    end
  end

  describe "an expired order" do
    it "renders the expiry notice with a retry link" do
      order = create(:order, status: :expired, expires_at: 1.minute.ago)

      visit order_path(order.code)

      expect(page).to have_css("h1", text: "This order expired")
      expect(page).to have_content("The inventory hold ended before payment confirmation. No payment was captured.")
      expect(page).to have_link("Try again", href: root_path)
      expect(page).to have_css("turbo-frame#order_status[data-poll-active-value='false']")
      expect(page).to have_no_link("Download tax invoice")
    end
  end

  describe "a canceled order" do
    it "renders the cancellation notice" do
      order = create(:order, status: :canceled)

      visit order_path(order.code)

      expect(page).to have_css("h1", text: "This order was canceled")
      expect(page).to have_link("Return to tickets", href: root_path)
      expect(page).to have_no_content("Your tickets are confirmed")
      expect(page).to have_no_link("Download tax invoice")
    end
  end

  describe "an unknown order code" do
    it "renders the 404 page for a well-formed but unused code" do
      visit order_path("UNKNOWN3")

      expect(page).to have_content("The page you were looking for doesn't exist")
      expect(page).to have_no_css("main.status-page")
    end

    it "renders the 404 page for a garbage code" do
      visit order_path("not-a-real-order-code")

      expect(page).to have_content("The page you were looking for doesn't exist")
    end
  end
end
