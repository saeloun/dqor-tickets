require "rails_helper"

RSpec.describe Avatarable do
  let(:model) do
    Class.new do
      include Avatarable
      attr_accessor :name, :email, :github_login

      def initialize(name: nil, email: nil, github_login: nil)
        @name = name
        @email = email
        @github_login = github_login
      end

      def avatar_url
        nil
      end

      def github_avatar_url
        github_login.present? ? "https://github.com/#{github_login}.png" : nil
      end

      def gravatar_url
        email.present? ? "https://gravatar.com/avatar" : nil
      end

      def initials
        name.to_s.split(" ").map { |n| n[0]&.upcase }.compact.first(2).join
      end
    end
  end

  it "falls back through uploaded, GitHub, Gravatar, then initials" do
    instance = model.new(name: "Ada Lovelace", email: "ada@example.com", github_login: "ada")
    expect(instance.avatar_image_url).to eq("https://github.com/ada.png")

    instance.github_login = nil
    expect(instance.avatar_image_url).to eq("https://gravatar.com/avatar")

    instance.email = nil
    expect(instance.avatar_image_url).to include("<svg")
  end

  it "produces a deterministic initials SVG" do
    instance = model.new(name: "Ada Lovelace")
    svg = instance.initials_svg

    expect(svg).to include("Ada Lovelace")
    expect(svg).to include("AL")
    expect(svg).to include("<svg")
  end
end
