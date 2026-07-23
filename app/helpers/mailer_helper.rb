module MailerHelper
  BODY_FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif".freeze
  DISPLAY_FONT = "Georgia,'Times New Roman',serif".freeze

  INK = "#33302c".freeze
  MUTED = "#5f574d".freeze
  RUBY = "#7a1220".freeze
  GOLD = "#6b5214".freeze
  RULE = "#e4d6b6".freeze

  def mail_heading(text)
    tag.h1 text, style: "margin:0 0 16px;font-family:#{DISPLAY_FONT};color:#{INK};font-size:24px;line-height:1.25;font-weight:bold;"
  end

  def mail_text(content = nil, &block)
    tag.p (content || capture(&block)), style: "margin:0 0 16px;font-family:#{BODY_FONT};color:#{INK};font-size:16px;line-height:1.6;"
  end

  def mail_note(content = nil, &block)
    tag.p (content || capture(&block)), style: "margin:0 0 16px;font-family:#{BODY_FONT};color:#{MUTED};font-size:14px;line-height:1.6;"
  end

  def mail_label(text)
    tag.div text, style: "font-family:#{BODY_FONT};color:#{GOLD};font-size:13px;letter-spacing:0.09em;text-transform:uppercase;font-weight:600;"
  end

  def mail_field(label, value)
    safe_join([
      mail_label(label),
      tag.p(value.presence || "—", style: "margin:2px 0 14px;font-family:#{BODY_FONT};color:#{INK};font-size:17px;line-height:1.4;")
    ])
  end

  def mail_button(text, url)
    link_to text, url, style: "display:inline-block;background:#{RUBY};color:#ffffff;text-decoration:none;font-family:#{BODY_FONT};font-size:16px;font-weight:bold;padding:14px 30px;border-radius:6px;border:1px solid #c99a3f;"
  end

  def mail_link(text, url)
    link_to text, url, style: "color:#{RUBY};font-family:#{BODY_FONT};"
  end

  def mail_divider
    tag.div "", style: "border-top:1px solid #{RULE};margin:22px 0;"
  end
end
