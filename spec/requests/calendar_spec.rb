require "rails_helper"

RSpec.describe "Calendar", type: :request do
  it "generates an iCalendar file for the conference" do
    get calendar_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/calendar")
    expect(response.body).to include("BEGIN:VEVENT")
    expect(response.body).to include("SUMMARY:Deccan Queen on Rails 2026")
    expect(response.body).to include("DTSTART;VALUE=DATE:20261008")
    expect(response.body).to include("LOCATION:Hyatt Regency, Pune")
  end
end
