require "rails_helper"
require Rails.root.join("db/migrate/20261002220000_correct_day_one_welcome_programme")

RSpec.describe "Day 1 programme correction", type: :request do
  let(:zone) { ActiveSupport::TimeZone["Asia/Kolkata"] }
  let!(:amanda) { Talk.create!(title: "Welcome address", speaker_name: "Amanda", starts_at: at("10:20"), ends_at: at("10:28"), published: true) }
  let!(:video) { Talk.create!(title: "DHH welcome video", starts_at: at("10:28"), ends_at: at("10:30"), published: true) }
  let!(:keynote) { Talk.create!(title: "Opening keynote", starts_at: at("10:30"), ends_at: at("11:15"), published: true) }

  def at(time)
    zone.parse("2026-10-08 #{time}")
  end

  def correct
    CorrectDayOneWelcomeProgramme.new.up
  end

  it "adds exactly two minutes to Amanda, preserves neighbours and hides the video idempotently" do
    historical = Talk.create!(title: "DHH retrospective", starts_at: zone.parse("2026-10-09 12:00"), published: true)
    before_keynote = keynote.attributes
    2.times { correct }
    expect(amanda.reload.starts_at).to eq(at("10:20"))
    expect(amanda.ends_at).to eq(at("10:30"))
    expect(video.reload).not_to be_published
    expect(keynote.reload.attributes).to eq(before_keynote)
    expect(historical.reload).to be_published
    get schedule_path
    expect(response.body).to include("10:20 AM – 10:30 AM", "Conference afterparty: Thursday, October 8, 2026")
    expect(response.body).not_to include("DHH welcome video")
    get talk_path(video)
    expect(response).to redirect_to(schedule_path)
  end

  it "fails before changing either record if organizers edited the verified times" do
    amanda.update!(ends_at: at("10:29"))
    expect { correct }.to raise_error(RuntimeError, /preserve edits/)
    expect(video.reload).to be_published
    expect(amanda.reload.ends_at).to eq(at("10:29"))
  end

  it "fails safely on ambiguous programme items" do
    video.dup.save!
    expect { correct }.to raise_error(RuntimeError, /exactly one/)
    expect(amanda.reload.ends_at).to eq(at("10:28"))
  end

  it "shows the corrected party date and exact attendee label with the real count" do
    create(:ticket, order: create(:order, :paid))
    create(:ticket, order: create(:order, :paid))
    create(:ticket_type, slug: "conference-pass-regular")
    [ root_path, tickets_store_path ].each do |path|
      get path
      expect(response.body).to include("Conference afterparty (Oct 8)", "Rails Developers attending")
      expect(response.body).not_to include("Conference afterparty (Oct 9)")
      label = Nokogiri::HTML(response.body).at_css(".whos-coming__count")
      expect(label.text).not_to include("Rubyist")
      expect(label.at_css("strong").text).to eq("2")
    end
  end
end
