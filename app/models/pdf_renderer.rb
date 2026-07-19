class PdfRenderer
  RETRYABLE_ERRORS = [ Ferrum::ProcessTimeoutError, Ferrum::TimeoutError, Ferrum::DeadBrowserError ].freeze
  OPTIONS = {
    invoice: { format: :A4 },
    ticket: { format: :A5, landscape: true }
  }.freeze

  def self.render(record, template:)
    html = ApplicationController.render(template: "pdfs/#{template}", locals: { template => record }, layout: false)
    browser_options = { process_timeout: ENV.fetch("FERRUM_PROCESS_TIMEOUT", 30).to_i, timeout: 30 }
    browser_options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
    if ENV["CHROME_NO_SANDBOX"] == "1"
      browser_options[:browser_options] = {
        "no-sandbox" => nil,
        "disable-gpu" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-setuid-sandbox" => nil,
        "no-zygote" => nil,
        "single-process" => nil
      }
    end
    3.times do |attempt|
      browser = nil
      begin
        browser = Ferrum::Browser.new(**browser_options)
        browser.content = html
        return browser.pdf(**OPTIONS.fetch(template), encoding: :binary, print_background: true)
      rescue *RETRYABLE_ERRORS
        raise if attempt == 2
      ensure
        browser&.quit
      end
    end
  end
end
