module Avatarable
  extend ActiveSupport::Concern

  def avatar_image_url(fallback: true)
    return avatar_url if respond_to?(:avatar_url) && avatar_url.present?
    return github_avatar_url if respond_to?(:github_avatar_url) && github_avatar_url.present?
    return gravatar_url if respond_to?(:gravatar_url) && gravatar_url.present?

    initials_svg if fallback
  end

  def initials_svg
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="#{ERB::Util.html_escape(name)}">
        <rect width="64" height="64" fill="#{svg_fill}" rx="32"/>
        <text x="32" y="36" text-anchor="middle" font-size="24" font-family="Inter, sans-serif" fill="white" font-weight="600">#{ERB::Util.html_escape(initials)}</text>
      </svg>
    SVG
  end

  def svg_fill
    hue = name.to_s.downcase.bytes.sum % 360
    "hsl(#{hue}, 65%, 45%)"
  end
end
