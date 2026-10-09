require "rails_helper"

RSpec.describe "Order polling lifecycle", type: :system do
  around do |example|
    original_app = Capybara.app
    @observer = OrderPollObserver.new(original_app)
    Capybara.app = @observer
    example.run
  ensure
    Capybara.reset_sessions!
    Capybara.app = original_app
  end

  before do
    driven_by :order_polling
    Rails.cache.clear
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
  end

  def observe_for(milliseconds)
    page.execute_script(<<~JS, milliseconds)
      document.body.removeAttribute("data-poll-observation-complete");
      window.setTimeout(() => document.body.dataset.pollObservationComplete = "true", arguments[0]);
    JS
    expect(page).to have_css("body[data-poll-observation-complete='true']", wait: milliseconds / 1000.0 + 5)
  end

  def expect_no_late_requests(request_count, state)
    if page.has_css?("#order_status .turbo-frame-error", wait: 0)
      puts "Observed no-click #{state}: #{@observer.requests.map { |request| request[:status] }.inspect} with missing order_status"
      page.save_screenshot("order-polling-#{state}-content-missing.png", full: true)
    end
    expect(@observer.requests.size).to eq(request_count)
    expect(@observer.requests).to all(include(status: 200, contains_frame: true))
    expect(page).to have_no_content("Content missing")
    page.save_screenshot("order-polling-#{state}-stable.png", full: true)
  end

  it "stops polling after payment and keeps the frame intact beyond thirty seconds without a click" do
    order = create(:order)
    create(:ticket, order:)
    visit order_path(order.code)
    expect(page).to have_content("Confirming your payment")
    page.execute_script("document.body.dataset.originalDocument = 'retained'")

    order.update!(status: :paid)

    expect(page).to have_content("Your tickets are confirmed", wait: 12)
    count = @observer.requests.size
    observe_for(35_000)

    expect_no_late_requests(count, "paid")
    expect(page).to have_content("Your tickets are confirmed")
    expect(page.evaluate_script("document.body.dataset.originalDocument")).to eq("retained")
  end

  { expired: "This order expired", canceled: "This order was canceled" }.each do |state, heading|
    it "stops polling when a pending order becomes #{state}" do
      order = create(:order)
      visit order_path(order.code)
      expect(page).to have_content("Confirming your payment")

      order.update!(status: state)

      expect(page).to have_content(heading, wait: 12)
      count = @observer.requests.size
      observe_for(17_000)

      expect_no_late_requests(count, state)
      expect(page).to have_content(heading)
    end
  end

  it "keeps genuinely pending updates below the unchanged rate limit for over a minute" do
    order = create(:order)
    visit order_path(order.code)
    expect(page).to have_content("Confirming your payment")
    create(:payment_event, order:, kind: "payment.failed")
    expect(page).to have_content("The payment failed.", wait: 12)
    observe_for(65_000)

    requests = @observer.requests
    expect(requests.size).to be_between(8, 10)
    requests.each do |request|
      expect(requests.count { |other| other[:at] >= request[:at] && other[:at] < request[:at] + 60 }).to be <= 10
    end
    expect(requests).to all(include(status: 200, contains_frame: true))
    expect(requests.drop(1)).to all(include(frame: "order_status"))
    expect(order.reload).to be_pending
    expect(page).to have_content("Confirming your payment")
    expect(page).to have_no_content("Content missing")
    page.save_screenshot("order-polling-pending-over-minute.png", full: true)
  end

  it "clears timers during repeated connections, removal and navigation and skips a busy frame" do
    order = create(:order)
    visit order_path(order.code)
    expect(page).to have_css(".status-card[data-controller='poll']")
    page.execute_script(<<~JS)
      const element = document.querySelector(".status-card[data-controller='poll']");
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "poll");
      const originalSet = window.setInterval.bind(window);
      const originalClear = window.clearInterval.bind(window);
      window.pollIntervals = new Set([controller.timer]);
      window.setInterval = (...args) => {
        const timer = originalSet(...args);
        window.pollIntervals.add(timer);
        document.body.dataset.pollTimers = String(window.pollIntervals.size);
        return timer;
      };
      window.clearInterval = (timer) => {
        originalClear(timer);
        window.pollIntervals.delete(timer);
        document.body.dataset.pollTimers = String(window.pollIntervals.size);
      };
      controller.connect();
      controller.connect();
      const frame = element.closest("turbo-frame");
      frame.setAttribute("busy", "");
      controller.reload();
      window.pollBusySource = frame.getAttribute("src");
      frame.removeAttribute("busy");
      window.detachedPollCard = element;
      element.remove();
    JS
    expect(page).to have_css("body[data-poll-timers='0']")
    expect(page.evaluate_script("window.pollBusySource")).to be_nil
    expect(@observer.requests.size).to eq(1)

    page.execute_script("document.querySelector('#order_status').appendChild(window.detachedPollCard)")
    expect(page).to have_css("body[data-poll-timers='1']")
    click_link "Get Your Pass"
    expect(page).to have_content("Choose your pass")
    expect(page.evaluate_script("window.pollIntervals.size")).to eq(0)
    page.execute_script("history.back()")
    expect(page).to have_content("Confirming your payment")
    expect(page).to have_css("body[data-poll-timers='1']")

    order.update!(status: :paid)
    expect(page).to have_content("Your tickets are confirmed", wait: 12)
    expect(page).to have_css("body[data-poll-timers='0']")
  end
end
