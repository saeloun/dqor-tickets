class SeedInitialContent < ActiveRecord::Migration[8.1]
  def up
    return unless Rails.env.production?

    InfoPage.find_or_create_by!(slug: "venue") do |page|
      page.title = "Venue"
      page.published = true
      page.position = 1
      page.body = <<~TEXT
        Deccan Queen on Rails takes place at Hyatt Regency, Pune, from 8 to 11 October 2026.

        Talks run on 8 and 9 October. 11 October is the optional Explore Pune Day.

        Detailed travel and accommodation guidance will be added here soon.
      TEXT
    end

    faqs = [
      [ "When and where is Deccan Queen on Rails?", "8 to 11 October 2026 at Hyatt Regency, Pune. Talks are on 8 and 9 October; 11 October is the optional Explore Pune Day." ],
      [ "Do I need a password to sign in?", "No. Enter your email and we send you a one-tap sign-in link. You can add a password later in your account settings." ],
      [ "How do I get my ticket and entry pass?", "After payment you receive an entry-pass QR by email and in your account. Sign in and open your account to show the QR at the door." ],
      [ "Can I get a GST invoice?", "Yes. Add your company GST details at checkout and they appear on your tax invoice." ]
    ]

    faqs.each_with_index do |(question, answer), index|
      Faq.find_or_create_by!(question: question) do |faq|
        faq.answer = answer
        faq.published = true
        faq.position = index + 1
      end
    end
  end

  def down
  end
end
