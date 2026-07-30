require "rails_helper"

RSpec.describe EmailSequenceStep do
  let(:event) { create(:event, title: "RubyConf") }

  it "renders subject and body with merge fields" do
    step = event.email_sequence_steps.create!(trigger_type: "on_registration", subject: "Hi {name}", body: "See you at {event_title}. {schedule_link}")

    expect(step.render_subject(name: "Ada")).to eq("Hi Ada")
    expect(step.render_body(name: "Ada", event_title: "RubyConf", schedule_link: "http://x")).to eq("See you at RubyConf. http://x")
  end

  it "identifies relative triggers" do
    relative = event.email_sequence_steps.new(trigger_type: "relative_to_event_start", subject: "s", body: "b", offset_seconds: -86_400)
    absolute = event.email_sequence_steps.new(trigger_type: "on_registration", subject: "s", body: "b")

    expect(relative.relative?).to be(true)
    expect(absolute.relative?).to be(false)
  end

  it "validates trigger type and requires subject and body" do
    expect(event.email_sequence_steps.new(trigger_type: "bogus", subject: "s", body: "b")).not_to be_valid
    expect(event.email_sequence_steps.new(trigger_type: "on_registration", subject: nil, body: "b")).not_to be_valid
  end

  it "dedupes sends per step and registration" do
    step = event.email_sequence_steps.create!(subject: "s", body: "b")
    registration = create(:registration, event:)
    step.email_sequence_sends.create!(registration:)

    expect(step.email_sequence_sends.new(registration:)).not_to be_valid
  end

  it "lists only enabled steps" do
    on = event.email_sequence_steps.create!(subject: "s", body: "b", enabled: true)
    event.email_sequence_steps.create!(subject: "s", body: "b", enabled: false)

    expect(event.email_sequence_steps.enabled).to contain_exactly(on)
  end
end
