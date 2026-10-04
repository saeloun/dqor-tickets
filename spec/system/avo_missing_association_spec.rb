require "rails_helper"

RSpec.describe "Avo association navigation", type: :system do
  it "keeps supported ticket navigation working and returns not found for the stale speaker route" do
    admin = create(:admin_user, password: "password123")
    speaker = Speaker.create!(name: "Synthetic browser stale-route speaker")
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: "Synthetic browser association attendee")

    visit new_session_path
    fill_in "email", with: admin.email
    fill_in "password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path("/avo/dashboard")

    visit "/avo/resources/orders/#{order.id}/tickets"
    expect(page).to have_content(ticket.attendee_name)
    page.save_screenshot(Rails.root.join("tmp/capybara/avo-supported-association.png"))

    response = page.evaluate_async_script(<<~JS, "/avo/resources/speakers/#{speaker.id}/talk")
      const route = arguments[0];
      const done = arguments[1];
      fetch(route, { credentials: "same-origin" }).then(async response => {
        done({ status: response.status, body: await response.text() });
      });
    JS
    expect(response).to eq("status" => 404, "body" => "")
  end
end
