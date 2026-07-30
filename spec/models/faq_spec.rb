require "rails_helper"

RSpec.describe Faq do
  it "requires a question" do
    expect(Faq.new).not_to be_valid
  end

  it "scopes to published, ordered by position" do
    second = Faq.create!(question: "Second?", published: true, position: 2)
    first = Faq.create!(question: "First?", published: true, position: 1)
    Faq.create!(question: "Draft?", published: false)

    expect(Faq.published.ordered.to_a).to eq([ first, second ])
  end
end
