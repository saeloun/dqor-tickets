class OrderEmailObfuscation
  EMAIL = /[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/

  attr_reader :protection_requests

  def initialize(app)
    @app = app
    @protection_requests = []
  end

  def call(env)
    if env["PATH_INFO"] == "/cdn-cgi/l/email-protection"
      @protection_requests << env["HTTP_TURBO_FRAME"]
      return [ 404, { "content-type" => "text/html" }, [ "<html><body>Email protection</body></html>" ] ]
    end

    status, headers, body = @app.call(env)
    return [ status, headers, body ] unless headers["content-type"].to_s.include?("text/html")

    html = +""
    body.each { |part| html << part }
    body.close if body.respond_to?(:close)
    html = html.split(/(<!--email_off-->.*?<!--\/email_off-->)/m).map do |part|
      next part if part.start_with?("<!--email_off-->")

      part.gsub(/>([^<>]*)</) do
        ">#{Regexp.last_match(1).gsub(EMAIL) { |email| protection_link(email) }}<"
      end
    end.join
    html = html.sub("</body>", "#{decoder}</body>")
    headers = headers.except("content-length", "etag")
    [ status, headers, [ html ] ]
  end

  private
    def protection_link(email)
      encoded = [ 107, *email.bytes.map { |byte| byte ^ 107 } ].pack("C*").unpack1("H*")
      %(<a class="__cf_email__" href="/cdn-cgi/l/email-protection\##{encoded}" data-cfemail="#{encoded}">[email protected]</a>)
    end

    def decoder
      <<~HTML
        <script>
          document.addEventListener("DOMContentLoaded", () => {
            document.querySelectorAll("a.__cf_email__").forEach((link) => {
              const bytes = link.dataset.cfemail.match(/../g).map((byte) => parseInt(byte, 16));
              const email = bytes.slice(1).map((byte) => String.fromCharCode(byte ^ bytes[0])).join("");
              link.replaceWith(document.createTextNode(email));
            });
          });
        </script>
      HTML
    end
end

Capybara.register_driver(:order_email_obfuscation) do |app|
  options = { window_size: [ 1400, 1000 ], process_timeout: 30, timeout: 20, headless: true, js_errors: false }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options] = { "no-sandbox": nil, "disable-dev-shm-usage": nil } if ENV["CHROME_NO_SANDBOX"].present?
  Capybara::Cuprite::Driver.new(app, **options)
end
