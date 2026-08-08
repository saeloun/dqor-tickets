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
    svg = RQRCode::QRCode.new(ticket.secret).as_svg(module_size: 5, standalone: true, use_path: true, viewbox: true)
    svg.sub(/\A<\?xml.*?\?>\s*/m, "").html_safe
  end
end
