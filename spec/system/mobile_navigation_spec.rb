require "rails_helper"

RSpec.describe "Mobile navigation text reflow", type: :system do
  [ 320, 390, 430 ].each do |width|
    [ 1, 2 ].each do |text_scale|
      it "keeps theme and menu controls usable at #{width}px with #{text_scale * 100}% text" do
        page.current_window.resize_to(width, 844)
        visit account_sign_in_path
        expect(page).to have_css('#nav-mobile-toggle[aria-label="Open menu"]')

        page.evaluate_async_script(<<~JS, text_scale)
          const scale = arguments[0], done = arguments[arguments.length - 1];
          document.fonts.ready.then(() => {
            const sizes = Array.from(document.querySelectorAll("body, body *")).map((element) => {
              const style = getComputedStyle(element);
              return [element, parseFloat(style.fontSize), style.lineHeight];
            });
            for (const [element, size, lineHeight] of sizes) {
              element.style.fontSize = `${size * scale}px`;
              if (lineHeight !== "normal") element.style.lineHeight = `${parseFloat(lineHeight) * scale}px`;
            }
            requestAnimationFrame(() => requestAnimationFrame(done));
          });
        JS

        [ "#theme-toggle", "#nav-mobile-toggle" ].each do |selector|
          bounds = page.evaluate_script(<<~JS, selector)
            ((selector) => {
              const bounds = document.querySelector(selector).getBoundingClientRect();
              return { left: bounds.left, right: bounds.right, top: bounds.top, bottom: bounds.bottom, width: innerWidth, height: innerHeight };
            })(arguments[0])
          JS
          expect(bounds.fetch("left")).to be >= 0
          expect(bounds.fetch("right")).to be <= bounds.fetch("width")
          expect(bounds.fetch("top")).to be >= 0
          expect(bounds.fetch("bottom")).to be <= bounds.fetch("height")
        end

        initial_dark = page.evaluate_script('document.documentElement.dataset.theme === "dark"')
        find("#theme-toggle").click
        expect(page.evaluate_script('document.documentElement.dataset.theme === "dark"')).to eq(!initial_dark)
        find("#nav-mobile-toggle").click
        expect(page).to have_css("#nav-mobile-menu.open")
        expect(page.evaluate_script("document.activeElement === document.querySelector('#nav-mobile-menu a')")).to be(true)
        find("#theme-toggle-mobile").send_keys(:tab)
        expect(page.evaluate_script("document.activeElement === document.querySelector('#nav-mobile-menu a')")).to be(true)
        page.driver.browser.keyboard.type(:Escape)
        expect(page).to have_no_css("#nav-mobile-menu.open")
        expect(page.evaluate_script("document.activeElement.id")).to eq("nav-mobile-toggle")
      end
    end
  end
end
