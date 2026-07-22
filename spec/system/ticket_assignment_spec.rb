require "rails_helper"

RSpec.describe "Ticket assignment", type: :system do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  let(:order) do
    create(:order, :paid).tap { |paid_order| Invoice.issue_for!(paid_order) }
  end

  def unassigned_ticket(attributes = {})
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, **attributes)
  end

  def order_form_for(ticket)
    find("form.assignment-form[action='#{assign_order_ticket_path(order.code, ticket)}']")
  end

  def bypass_html5_validation
    page.execute_script("document.querySelectorAll('form.assignment-form').forEach((form) => { form.noValidate = true })")
  end

  describe "assigning from the order page" do
    it "persists every attendee detail the buyer fills in" do
      ticket = unassigned_ticket

      visit order_path(order.code)

      within order_form_for(ticket) do
        fill_in "Attendee name", with: "Grace Hopper"
        fill_in "Attendee email", with: "grace@example.com"
        fill_in "Dietary restrictions", with: "No peanuts"
        check "Needs childcare / day care"
        click_button "Assign this ticket"
      end

      expect(page).to have_content("Ticket assigned to Grace Hopper.")
      expect(page).to have_content("grace@example.com")

      expect(ticket.reload).to have_attributes(
        attendee_name: "Grace Hopper",
        attendee_email: "grace@example.com",
        dietary_preference: "No peanuts",
        childcare_needed: true
      )
      expect(ticket).to be_assigned
      expect(ticket.assigned_at).to be_present
    end

    it "updates the assigned counter as tickets are claimed" do
      first_ticket = unassigned_ticket
      unassigned_ticket

      visit order_path(order.code)

      expect(page).to have_content("0 of 2 tickets assigned")

      within order_form_for(first_ticket) do
        fill_in "Attendee name", with: "Grace Hopper"
        fill_in "Attendee email", with: "grace@example.com"
        click_button "Assign this ticket"
      end

      expect(page).to have_content("1 of 2 tickets assigned")
      expect(page).to have_content("Assign each ticket now")
    end

    it "enqueues the attendee ticket email" do
      ticket = unassigned_ticket

      visit order_path(order.code)

      expect do
        within order_form_for(ticket) do
          fill_in "Attendee name", with: "Grace Hopper"
          fill_in "Attendee email", with: "grace@example.com"
          click_button "Assign this ticket"
        end

        expect(page).to have_content("Ticket assigned to Grace Hopper.")
      end.to have_enqueued_mail(OrderMailer, :ticket).with(ticket)
    end

    it "shows a private claim link for each unassigned ticket" do
      first_ticket = unassigned_ticket
      second_ticket = unassigned_ticket

      visit order_path(order.code)

      expect(find("#claim_link_#{first_ticket.id}").value).to end_with("/claim/#{first_ticket.claim_token}")
      expect(find("#claim_link_#{second_ticket.id}").value).to end_with("/claim/#{second_ticket.claim_token}")
      expect(first_ticket.claim_token).not_to eq(second_ticket.claim_token)
    end

    it "hides the claim link once the ticket is assigned" do
      ticket = unassigned_ticket

      visit order_path(order.code)
      expect(page).to have_selector("#claim_link_#{ticket.id}")

      within order_form_for(ticket) do
        fill_in "Attendee name", with: "Grace Hopper"
        fill_in "Attendee email", with: "grace@example.com"
        click_button "Assign this ticket"
      end

      expect(page).to have_content("1 of 1 tickets assigned")
      expect(page).to have_no_selector("#claim_link_#{ticket.id}")
    end
  end

  describe "assigning through the private claim link" do
    it "assigns only the ticket the link belongs to" do
      ticket = unassigned_ticket
      other_ticket = unassigned_ticket

      visit ticket_claim_path(ticket.claim_token)

      expect(page).to have_content("Claim your ticket")
      expect(page).to have_content(/#{Regexp.escape(ticket.ticket_type.name)}/i)

      fill_in "Attendee name", with: "Ada Lovelace"
      fill_in "Attendee email", with: "ada@example.com"
      fill_in "Dietary restrictions", with: "Vegan"
      check "Needs childcare / day care"
      click_button "Assign this ticket"

      expect(page).to have_content("Ticket assigned to Ada Lovelace.")

      expect(ticket.reload).to have_attributes(
        attendee_name: "Ada Lovelace",
        attendee_email: "ada@example.com",
        dietary_preference: "Vegan",
        childcare_needed: true
      )
      expect(ticket).to be_assigned

      expect(other_ticket.reload).not_to be_assigned
      expect(other_ticket).to have_attributes(
        attendee_name: nil,
        attendee_email: nil,
        assigned_at: nil,
        childcare_needed: false
      )
    end

    it "enqueues the attendee ticket email" do
      ticket = unassigned_ticket

      visit ticket_claim_path(ticket.claim_token)

      expect do
        fill_in "Attendee name", with: "Ada Lovelace"
        fill_in "Attendee email", with: "ada@example.com"
        click_button "Assign this ticket"

        expect(page).to have_content("Ticket assigned to Ada Lovelace.")
      end.to have_enqueued_mail(OrderMailer, :ticket).with(ticket)
    end

    it "lets the attendee correct the details afterwards" do
      ticket = unassigned_ticket

      visit ticket_claim_path(ticket.claim_token)

      fill_in "Attendee name", with: "Ada Lovelace"
      fill_in "Attendee email", with: "ada@example.com"
      click_button "Assign this ticket"

      expect(page).to have_button("Update ticket")

      fill_in "Attendee email", with: "ada.lovelace@example.com"
      click_button "Update ticket"

      expect(page).to have_content("Ticket assigned to Ada Lovelace.")
      expect(ticket.reload.attendee_email).to eq("ada.lovelace@example.com")
    end

    it "refuses to assign a canceled ticket" do
      ticket = unassigned_ticket(canceled_at: Time.current)

      visit ticket_claim_path(ticket.claim_token)

      fill_in "Attendee name", with: "Ada Lovelace"
      fill_in "Attendee email", with: "ada@example.com"
      click_button "Assign this ticket"

      expect(page).to have_content("canceled ticket cannot be assigned")
      expect(ticket.reload).not_to be_assigned
      expect(ticket.attendee_name).to be_nil
    end
  end

  describe "validation" do
    it "rejects a blank attendee name submitted past the browser validation" do
      ticket = unassigned_ticket

      visit ticket_claim_path(ticket.claim_token)

      fill_in "Attendee email", with: "ada@example.com"
      bypass_html5_validation
      click_button "Assign this ticket"

      expect(page).to have_content("Attendee name can't be blank")
      expect(ticket.reload).not_to be_assigned
      expect(ticket.assigned_at).to be_nil
    end

    it "rejects an invalid attendee email submitted past the browser validation" do
      ticket = unassigned_ticket

      visit ticket_claim_path(ticket.claim_token)

      fill_in "Attendee name", with: "Ada Lovelace"
      bypass_html5_validation
      fill_in "Attendee email", with: "nope-at-example"
      click_button "Assign this ticket"

      expect(page).to have_content("Attendee email is invalid")
      expect(ticket.reload).not_to be_assigned
      expect(ticket.attendee_email).to be_nil
    end

    it "rejects a blank attendee name from the order page without assigning" do
      ticket = unassigned_ticket

      visit order_path(order.code)

      within order_form_for(ticket) do
        fill_in "Attendee email", with: "ada@example.com"
      end
      bypass_html5_validation
      within(order_form_for(ticket)) { click_button "Assign this ticket" }

      expect(page).to have_content("Attendee name can't be blank")
      expect(ticket.reload).not_to be_assigned
    end
  end
end
