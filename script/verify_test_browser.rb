require "ferrum"

path = ENV.fetch("CHROME_PATH")
abort "CHROME_PATH must be an executable browser" unless File.file?(path) && File.executable?(path)

options = { browser_path: path, process_timeout: 30, timeout: 30 }
options[:browser_options] = { "no-sandbox" => nil, "disable-dev-shm-usage" => nil } if ENV["CHROME_NO_SANDBOX"] == "1"
browser = nil
begin
  browser = Ferrum::Browser.new(**options)
  browser.content = "<!doctype html><html><body>Browser PDF startup verification</body></html>"
  raise "Browser JavaScript verification failed" unless browser.evaluate("6 * 7") == 42
  pdf = browser.pdf(encoding: :binary)
  raise "Browser PDF verification failed" unless pdf.start_with?("%PDF-") && pdf.bytesize > 1_000

  puts "Browser JavaScript and PDF startup verification passed (#{pdf.bytesize} bytes)"
ensure
  browser&.quit
end
