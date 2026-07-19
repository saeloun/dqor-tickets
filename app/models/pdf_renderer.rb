class PdfRenderer
  OPTIONS = {
    invoice: { format: :A4 },
    ticket: { format: :A5, landscape: true }
  }.freeze

  def self.render(record, template:)
    html = ApplicationController.render(template: "pdfs/#{template}", locals: { template => record }, layout: false)
    browser_options = {}
    browser_options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
    if ENV["CHROME_NO_SANDBOX"] == "1"
      browser_options[:browser_options] = {
        "no-sandbox" => nil,
        "disable-gpu" => nil,
        "disable-dev-shm-usage" => nil
      }
    end
    browser = Ferrum::Browser.new(**browser_options)
    browser.content = html
    browser.pdf(**OPTIONS.fetch(template), encoding: :binary, print_background: true)
  ensure
    browser&.quit
  end
end
