require "rails_helper"

RSpec.describe "Conference social proof", type: :request do
  def attendee(type, email:, status: :paid, canceled: false, public_attendee: true)
    User.create!(email:, name: email, public_attendee:)
    create(:ticket, ticket_type: type, order: create(:order, status:), attendee_email: email, canceled_at: (Time.current if canceled))
  end

  it "counts only confirmed conference seats and shows only their opted-in faces" do
    regular = create(:ticket_type, slug: "conference-pass-regular")
    comp = create(:ticket_type, slug: "complimentary-pass", hidden: true, price_paise: 0)
    girls = create(:ticket_type, slug: "rails-girls-pune")
    supporter = create(:ticket_type, slug: "supporter-pass")
    attendee(regular, email: "conference@example.test")
    attendee(comp, email: "comp@example.test")
    attendee(regular, email: "private@example.test", public_attendee: false)
    attendee(girls, email: "girls@example.test")
    attendee(supporter, email: "supporter@example.test")
    attendee(regular, email: "pending@example.test", status: :pending)
    attendee(regular, email: "canceled@example.test", canceled: true)
    attendee(regular, email: "expired@example.test", status: :expired)
    get root_path
    proof = response.parsed_body.at_css(".whos-coming")
    expect(proof.at_css("strong").text).to eq("4")
    expect(proof.text).to include("Rails Developers attending")
    expect(proof.css("img").map { |image| image["src"] }).to contain_exactly(
      User.find_by!(email: "conference@example.test").gravatar_url(size: 72),
      User.find_by!(email: "comp@example.test").gravatar_url(size: 72),
      User.find_by!(email: "supporter@example.test").gravatar_url(size: 72)
    )
  end

  it "hides the conference proof when only Rails Girls registrations exist" do
    attendee(create(:ticket_type, slug: "rails-girls-pune"), email: "girls-only@example.test")
    get root_path
    expect(response.parsed_body.at_css(".whos-coming")).to be_nil
  end
end
