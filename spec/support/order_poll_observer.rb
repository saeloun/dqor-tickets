class OrderPollObserver
  def initialize(app)
    @app = app
    @requests = []
    @mutex = Mutex.new
  end

  def requests
    @mutex.synchronize { @requests.map(&:dup) }
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [ status, headers, body ] unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"].match?(%r{\A/orders/[^/]+\z})

    html = +""
    body.each { |part| html << part }
    body.close if body.respond_to?(:close)
    @mutex.synchronize do
      @requests << {
        at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        status:,
        frame: env["HTTP_TURBO_FRAME"],
        contains_frame: html.include?('id="order_status"'),
        location: headers["location"]
      }
    end
    [ status, headers, [ html ] ]
  end
end

Capybara.register_driver(:order_polling) do |app|
  options = { window_size: [ 1400, 1000 ], process_timeout: 30, timeout: 20, headless: true, js_errors: false }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options] = { "no-sandbox": nil, "disable-dev-shm-usage": nil } if ENV["CHROME_NO_SANDBOX"].present?
  Capybara::Cuprite::Driver.new(app, **options)
end
