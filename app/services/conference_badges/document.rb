module ConferenceBadges
  class Document
    def self.qr_svg(value)
      RQRCode::QRCode.new(value, level: :h).as_svg(module_size: 1, offset: 4, fill: "ffffff", color: "000000", standalone: true, use_path: true, viewbox: true)
        .sub(/\A<\?xml.*?\?>\s*/m, "").html_safe
    end

    def self.html(badges)
      ApplicationController.render(template: "conference_badges/print", layout: false, locals: {
        badges:, css: Rails.root.join("app/assets/stylesheets/conference_badges.css").read,
        logo: "data:image/png;base64,#{Base64.strict_encode64(Rails.root.join("app/assets/images/deccan-logo.png").binread)}"
      })
    end

    def self.preview(badges)
      with_browser(badges) { |_browser, html| html }
    end

    def self.pdf(badges)
      with_browser(badges) do |browser, _html|
        browser.pdf(format: :A4, encoding: :binary, print_background: true, prefer_css_page_size: true,
          margin_top: 0, margin_bottom: 0, margin_left: 0, margin_right: 0, scale: 1)
      end
    end

    def self.with_browser(badges)
      options = { process_timeout: 30, timeout: 30 }
      options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
      if ENV["CHROME_NO_SANDBOX"] == "1"
        options[:browser_options] = {
          "no-sandbox" => nil,
          "disable-gpu" => nil,
          "disable-dev-shm-usage" => nil,
          "disable-setuid-sandbox" => nil,
          "no-zygote" => nil,
          "single-process" => nil
        }
      end
      browser = Ferrum::Browser.new(**options)
      html = html(badges)
      browser.content = html
      browser.page.command("Emulation.setEmulatedMedia", media: "print")
      ready = browser.evaluate_async(<<~JS, 30)
        const done = arguments[0];
        Promise.all([document.fonts.ready, ...Array.from(document.images, image => image.decode())])
          .then(() => done(true), () => done(false));
      JS
      raise Selection::Invalid, "Badge artwork could not be loaded. Review the print preview before trying again." unless ready
      layout = browser.evaluate(<<~JS)
        ({count: document.querySelectorAll('.conference-badge').length, invalid: Array.from(document.querySelectorAll('.conference-badge')).flatMap((card, index) => {
          const box = card.getBoundingClientRect();
          const mm = 96 / 25.4;
          const rows = [18, 6, 22, 19, 8, 34, 4];
          const invalid = Array.from(card.children).some((element, row) => {
            const rect = element.getBoundingClientRect();
            return rect.height > rows[row] * mm + 0.5 || rect.left < box.left + 4 * mm - 0.5 ||
              rect.right > box.right - 4 * mm + 0.5 || rect.top < box.top + 4 * mm - 0.5 || rect.bottom > box.bottom - 4 * mm + 0.5;
          });
          return invalid ? [index] : [];
        })})
      JS
      unless layout.fetch("count") == badges.length && badges.any?
        raise Selection::Invalid, "Badge layout could not be verified. Review the print preview before trying again."
      end
      if layout.fetch("invalid").any?
        badge = badges.fetch(layout.fetch("invalid").first)
        raise Selection::Invalid, "#{badge.sample ? 'Sample badge' : "Pass #{badge.ticket_id}"} does not fit the 90 × 120 mm insert. Review its attendee name or print-only company text."
      end
      yield browser, html
    ensure
      browser&.quit
    end
    private_class_method :with_browser
  end
end
