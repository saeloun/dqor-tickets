require "rails_helper"

RSpec.describe "Custom questions" do
  let(:event) { create(:event) }
  let(:ticket_type) { create(:ticket_type, event:) }

  it "defines typed questions and stores an attendee answer" do
    question = event.questions.create!(label: "T-shirt size", kind: "single_choice", options: %w[S M L], answer_scope: "attendee", required: true)
    order = create(:order, event:)
    ticket = create(:ticket, order:, ticket_type:)

    answer = question.answers.create!(ticket:, value: "M")

    expect(question.kind).to eq("single_choice")
    expect(question).to be_choice
    expect(answer.value).to eq("M")
    expect(event.questions.enabled.ordered).to include(question)
  end

  it "requires exactly one subject (order xor ticket)" do
    question = event.questions.create!(label: "Company", answer_scope: "order")
    order = create(:order, event:)
    ticket = create(:ticket, order:, ticket_type:)

    expect(question.answers.new(order:, ticket:)).not_to be_valid
    expect(question.answers.new).not_to be_valid
    expect(question.answers.new(order:)).to be_valid
  end

  it "scopes questions by ask_at" do
    checkout_q = event.questions.create!(label: "Diet", ask_at: "checkout")
    checkin_q = event.questions.create!(label: "Badge name", ask_at: "checkin")
    both_q = event.questions.create!(label: "Pronouns", ask_at: "both")

    expect(event.questions.for_checkout).to include(checkout_q, both_q)
    expect(event.questions.for_checkout).not_to include(checkin_q)
    expect(event.questions.for_checkin).to include(checkin_q, both_q)
  end

  it "validates the question kind and answer scope" do
    expect(event.questions.new(label: "X", kind: "bogus")).not_to be_valid
    expect(event.questions.new(label: "X", answer_scope: "nope")).not_to be_valid
  end
end
