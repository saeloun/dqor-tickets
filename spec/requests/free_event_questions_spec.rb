require "rails_helper"

RSpec.describe "Free event registration questions", type: :request do
  let!(:owner) { create(:user_for_free_pilot) }
  let!(:attendee) { create(:user_for_free_pilot, name: "Answer Attendee") }
  let!(:org) { Organization.create!(name: "Question Org", slug: "question-org") }
  let!(:membership) { Membership.create!(organization: org, user: owner, role: :owner) }
  let!(:event) { org.events.create!(title: "Questions meetup", slug: "meetup", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now) }
  let!(:type) { create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 3, free_published_at: Time.current) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(true)
  end

  def login(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  def access
    { user: owner, organization_id: org.id, event_id: event.id, ticket_type_id: type.id }
  end

  def add_question(label: "What would you like to learn?", kind: "short_text", required: "1", choices: "")
    form = FreeEvents::Form.find_by(ticket_type: type)
    FreeEvents::Questions::Editor.change(**access, action: "add", revision: form&.lock_version || 0,
      fields: { "label" => label, "type" => kind, "required" => required, "choices" => choices })
  end

  def publish
    form = FreeEvents::Form.find_by!(ticket_type: type)
    FreeEvents::Questions::Editor.change(**access, action: "publish", revision: form.lock_version)
  end

  def registration(version, answers)
    login(attendee)
    post free_event_registration_path(org.slug, event.slug), params: {
      ticket_type_id: type.id, form_version_id: version.id, registration_answers: answers,
      email: "forged@example.test", total_paise: 9900
    }
  end

  it "keeps question configuration off by default and drafts private without changing existing registration" do
    expect(ENV["FREE_EVENT_QUESTIONS_ENABLED"]).not_to eq("true")
    add_question(label: "PRIVATE DRAFT LABEL")
    login(attendee)
    get new_free_event_registration_path(org.slug, event.slug, type)
    expect(response).to have_http_status(:not_found)
    get published_event_path(org.slug, event.slug)
    expect(response.body).not_to include("PRIVATE DRAFT LABEL")
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(false)
    login(owner)
    get free_event_questions_path(org, event, type)
    expect(response).to have_http_status(:not_found)
    expect { FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id) }.to change(Ticket, :count).by(1)
  end

  it "uses stable identifiers and ordered drafts with immutable published versions" do
    first = add_question.draft_questions.first
    form = add_question(label: "Second", required: "0")
    version = publish
    FreeEvents::Questions::Editor.change(**access, action: "up", revision: form.reload.lock_version, question_id: form.draft_questions.last["id"])
    second_version = publish
    expect(second_version.questions.last["id"]).to eq(first["id"])
    expect(version.reload.questions.first["id"]).to eq(first["id"])
    expect { version.update!(questions: []) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { version.update_columns(questions: []) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { version.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { FreeEvents::Questions::Editor.change(**access, action: "remove", revision: -1, question_id: first["id"]) }.to raise_error(FreeEvents::Questions::Invalid, /Another organizer/)
  end

  it "rejects stale untouched-category save, publish and ordering without changing the saved draft" do
    login(owner)
    get free_event_questions_path(org, event, type)
    expect(response.body).to include('name="revision" value="0"')
    form = add_question
    expect(form.lock_version).to eq(1)
    saved = form.draft_questions.deep_dup
    %w[add publish up].each do |operation|
      patch free_event_questions_path(org, event, type), params: {
        operation: operation, revision: 0, question_id: saved.first["id"],
        question: { label: "Unseen overwrite", type: "short_text", required: "0" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Another organizer changed this draft")
      expect(form.reload.draft_questions).to eq(saved)
      expect(form.versions.count).to eq(0)
    end
    expect(publish.questions).to eq(saved)
  end

  it "enforces required typed answers and rejects unknown, nested and overlong values before issuing tickets" do
    add_question
    add_question(label: "Years using Ruby", kind: "integer")
    add_question(label: "Would you join a workshop?", kind: "yes_no")
    add_question(label: "Track", kind: "single_choice", choices: "Ruby\nRails")
    add_question(label: "Notes", kind: "long_text", required: "0")
    version = publish
    ids = version.questions.map { |q| q["id"] }
    bad = { ids[0] => "x" * 201, ids[1] => "1.2", ids[2] => "maybe", ids[3] => "other", ids[4] => [ "array" ], "unknown" => "x" }
    expect { registration(version, bad) }.not_to change(Order, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Use at most 200", "whole number", "Choose yes or no", "listed options", "single value", "Unknown questions")
    good = { ids[0] => "Ruby internals", ids[1] => "3", ids[2] => "no", ids[3] => version.questions[3]["options"][0]["id"], ids[4] => "" }
    expect { registration(version, good) }.to change(Ticket, :count).by(1)
    saved = FreeEvents::Response.sole
    expect(saved.answers).to include(ids[1] => 3, ids[2] => false, ids[4] => nil)
    expect(saved.ticket.attendee_email).to eq(attendee.email)
    expect(saved.ticket.price_paise).to eq(0)
    expect { registration(version, good.merge(ids[0] => "Overwrite")) }.not_to change { saved.reload.answers }
    expect { saved.update!(answers: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(enqueued_jobs).to be_empty
  end

  it "rejects malformed schemas and control characters and redacts answer logs" do
    [ nil, {}, [ nil ], [ { "id" => "bad" } ] ].each do |schema|
      expect { FreeEvents::Questions::Schema.validate!(schema) }.to raise_error(FreeEvents::Questions::Invalid)
    end
    add_question
    version = publish
    expect { registration(version, { version.questions.first["id"] => "bad\u0000value" }) }.not_to change(Ticket, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("unsupported control characters")
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("registration_answers" => { "id" => "PRIVATE" }, "answers" => "PRIVATE").values).to all(eq("[FILTERED]"))
  end

  it "rejects stale versions and fails closed if the questions flag is disabled after publication" do
    add_question
    old = publish
    add_question(label: "Optional second", required: "0")
    current = publish
    expect { registration(old, {}) }.not_to change(Ticket, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("registration form changed", "Optional second")
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(false)
    expect { registration(current, {}) }.not_to change(Ticket, :count)
    expect(response).to redirect_to(published_event_path(org.slug, event.slug))
  end

  it "isolates organizer drafts, preview and answers by organization, event, category and fresh role" do
    add_question(label: "PRIVATE QUESTION")
    version = publish
    registration(version, { version.questions.first["id"] => "PRIVATE ANSWER" })
    other_org = Organization.create!(name: "Other", slug: "other-questions")
    sibling = org.events.create!(title: "Sibling", slug: "sibling")
    login(owner)
    [ [ other_org, event ], [ org, sibling ] ].each do |organization, target|
      get free_event_questions_path(organization, target, type)
      expect(response).to have_http_status(:not_found)
      get export_free_event_answers_path(organization, target, type)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("PRIVATE ANSWER")
    end
    %w[editor viewer].each do |role|
      membership.update!(role: role)
      [ free_event_questions_path(org, event, type), preview_free_event_questions_path(org, event, type), export_free_event_answers_path(org, event, type) ].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
      patch free_event_questions_path(org, event, type), params: { operation: "publish", revision: 0 }
      expect(response).to have_http_status(:not_found)
    end
    membership.destroy!
    get free_event_questions_path(org, event, type)
    expect(response).to have_http_status(:not_found)
    login(attendee)
    get export_free_event_answers_path(org, event, type)
    expect(response).to have_http_status(:not_found)
  end

  it "exports historical labels and answers safely only in the explicit answer export" do
    form = add_question(label: "=Original prompt")
    version = publish
    id = version.questions.first["id"]
    registration(version, { id => "=PRIVATE_FORMULA()" })
    FreeEvents::Questions::Editor.change(**access, action: "update", revision: form.reload.lock_version, question_id: id,
      fields: { "label" => "Changed prompt", "type" => "short_text", "required" => "0" })
    publish
    login(owner)
    get export_free_event_answers_path(org, event, type)
    rows = CSV.parse(response.body)
    expect(rows.last).to include("'=Original prompt", "'=PRIVATE_FORMULA()")
    expect(response.body).not_to include("Changed prompt", attendee.email)
    get free_event_attendees_path(org, event, format: :csv)
    expect(response.body).not_to include("PRIVATE_FORMULA", "Original prompt")
    expect(Order.attendees_csv).not_to include("PRIVATE_FORMULA")
  end

  it "keeps category drafts private and rejects a different category's published version" do
    add_question(label: "Public category question")
    current = publish
    draft_type = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false)
    other_access = access.merge(ticket_type_id: draft_type.id)
    form = FreeEvents::Questions::Editor.change(**other_access, action: "add", revision: 0,
      fields: { "label" => "PRIVATE CATEGORY QUESTION", "type" => "short_text", "required" => "1" })
    other_version = FreeEvents::Questions::Editor.change(**other_access, action: "publish", revision: form.lock_version)
    login(attendee)
    get new_free_event_registration_path(org.slug, event.slug, type)
    expect(response.body).to include("Public category question")
    expect(response.body).not_to include("PRIVATE CATEGORY QUESTION")
    expect { registration(other_version, {}) }.not_to change(Ticket, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include("PRIVATE CATEGORY QUESTION")
    get new_free_event_registration_path(org.slug, event.slug, draft_type)
    expect(response).to have_http_status(:not_found)
    expect(current.questions.first["label"]).to eq("Public category question")
  end

  it "enforces event and category ownership in database answer relationships" do
    add_question
    version = publish
    registration(version, { version.questions.first["id"] => "Ruby" })
    saved = FreeEvents::Response.sole
    another = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false)
    expect {
      FreeEvents::Response.transaction(requires_new: true) do
        FreeEvents::Response.where(id: saved.id).update_all(ticket_type_id: another.id)
      end
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
