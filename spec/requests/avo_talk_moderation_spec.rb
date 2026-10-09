require "rails_helper"

%w[talk_questions talk_feedbacks].each do |resource|
  RSpec.describe "Avo #{resource}", type: :request do
    let!(:author) { User.create!(email: "moderation-author@example.com", name: "Moderation Author <script>") }
    let!(:talk) { Talk.create!(title: "Synthetic Rails questions", published: true) }
    let!(:record) do
      if resource == "talk_questions"
        TalkQuestion.create!(talk: talk, user: author, body: "How does Rails handle this?")
      else
        TalkFeedback.create!(talk: talk, user: author, rating: 5, comment: "Clear Rails explanation")
      end
    end

    it "renders the mounted index and show with the existing talk and escaped author" do
      sign_in_admin
      before = [ record.attributes, author.attributes ]

      [ "/avo/resources/#{resource}", "/avo/resources/#{resource}/#{record.id}" ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.text).to include(talk.title, author.name)
        if path.end_with?("/#{record.id}")
          expect(response.parsed_body.text).to include(record.is_a?(TalkQuestion) ? record.body : record.comment)
        end
        expect(response.body).to include("Moderation Author &lt;script&gt;")
        expect(response.parsed_body.css("a[href*='/avo/resources/users']")).to be_empty
      end
      expect([ record.reload.attributes, author.reload.attributes ]).to eq(before)
    end

    it "uses a neutral label without exposing email for an unnamed author" do
      author.update!(name: nil)
      sign_in_admin
      get "/avo/resources/#{resource}/#{record.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.text).to include("Attendee")
      expect(response.body).not_to include(author.email)
    end

    it "does not expose author administration in the edit form" do
      sign_in_admin
      get "/avo/resources/#{resource}/#{record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.css("input[name*='user'], select[name*='user'], input[name*='author']")).to be_empty
      expect(response.parsed_body.at_css("textarea")).to be_present
    end

    it "denies anonymous access to both mounted routes" do
      [ "/avo/resources/#{resource}", "/avo/resources/#{resource}/#{record.id}" ].each do |path|
        get path
        expect(response).to redirect_to("/session/new")
        expect(response.body).not_to include(record.is_a?(TalkQuestion) ? record.body : record.comment, author.email)
      end
    end

    it "keeps registration desk staff on the scanner" do
      sign_in_admin(create(:admin_user, role: :desk))
      [ "/avo/resources/#{resource}", "/avo/resources/#{resource}/#{record.id}" ].each do |path|
        get path
        expect(response).to redirect_to("/checkin")
        expect(response.body).not_to include(record.is_a?(TalkQuestion) ? record.body : record.comment, author.email)
      end
    end
  end
end
