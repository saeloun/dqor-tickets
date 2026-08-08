module ApplicationHelper
  def inr(paise)
    rupees, cents = paise.divmod(100)
    digits = rupees.to_s
    grouped = digits.length > 3 ? "#{digits[0...-3].reverse.scan(/.{1,2}/).join(",").reverse},#{digits[-3..]}" : digits
    "₹#{grouped}#{format(".%02d", cents) unless cents.zero?}"
  end

  def avatar_image_tag(user, size:, **options)
    if user.avatar.attached?
      image_tag user.avatar, **options
    else
      image_tag user.gravatar_url(size: size * 2), **options
    end
  end

  def entry_qr_svg(ticket)
    qr_svg(ticket.secret)
  end

  def connect_qr_svg(url)
    qr_svg(url)
  end

  def attendee_social_links(user)
    [
      [ "X", "https://x.com/#{ERB::Util.url_encode(user.x_username)}", user.x_username ],
      [ "Bluesky", "https://bsky.app/profile/#{ERB::Util.url_encode(user.bluesky)}", user.bluesky ],
      [ "GitHub", "https://github.com/#{ERB::Util.url_encode(user.github)}", user.github ],
      [ "Mastodon", mastodon_profile_url(user.mastodon), user.mastodon ],
      [ "LinkedIn", "https://www.linkedin.com/in/#{ERB::Util.url_encode(user.linkedin)}", user.linkedin ]
    ].select { |_, _, value| value.present? }
  end

  private
    def qr_svg(value)
      svg = RQRCode::QRCode.new(value).as_svg(module_size: 5, standalone: true, use_path: true, viewbox: true)
      svg.sub(/\A<\?xml.*?\?>\s*/m, "").html_safe
    end

    def mastodon_profile_url(handle)
      return if handle.blank?
      return handle if handle.match?(/\Ahttps?:\/\//i)

      if handle.match?(/\A[^@]+@[^@]+\z/)
        username, host = handle.split("@", 2)
        "https://#{host}/@#{ERB::Util.url_encode(username)}"
      else
        "https://#{handle}"
      end
    end
end
