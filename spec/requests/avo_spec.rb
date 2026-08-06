require "rails_helper"

RSpec.describe "Avo admin", type: :request do
  it "redirects unauthenticated visitors to the existing sign-in" do
    get "/avo"

    expect(response).to redirect_to("/session/new")
  end

  it "allows an authenticated admin to load resources and the dashboard" do
    sign_in_admin

    get "/avo/resources/orders"
    expect(response).to have_http_status(:ok)

    get "/avo/dashboard"
    expect(response).to have_http_status(:ok)
  end

  it "shows attendee logistics (t-shirt tally, dietary roster, childcare) for paid tickets" do
    paid = create(:order, :paid)
    create(:ticket, order: paid, attendee_name: "A", attendee_email: "a@example.com", tshirt_size: "M", dietary_preference: "Vegetarian")
    create(:ticket, order: paid, attendee_name: "B", attendee_email: "b@example.com", tshirt_size: "M", dietary_preference: "Vegetarian")
    create(:ticket, order: paid, attendee_name: "C", attendee_email: "c@example.com", tshirt_size: "L", childcare_needed: true)
    create(:ticket, order: paid, attendee_name: "D", attendee_email: "d@example.com", tshirt_size: nil)
    # Unpaid ticket must be excluded from every logistics count. Its distinctive
    # dietary note only appears in the roster if it were wrongly counted.
    create(:ticket, order: create(:order), attendee_name: "E", attendee_email: "e@example.com", tshirt_size: "L", dietary_preference: "UnpaidOnlyMeal")

    sign_in_admin
    get "/avo/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Attendee logistics")
    expect(response.body).to include("Vegetarian")
    expect(response.body).to include("Need childcare / day care")
    expect(response.body).not_to include("UnpaidOnlyMeal")
  end
end
