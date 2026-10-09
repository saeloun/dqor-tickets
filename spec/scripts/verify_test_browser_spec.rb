require "rails_helper"

RSpec.describe "Test browser startup verification" do
  let(:browser) { instance_double(Ferrum::Browser, quit: nil) }

  before do
    allow(Ferrum::Browser).to receive(:new).and_return(browser)
    allow(browser).to receive(:content=)
    allow(browser).to receive(:evaluate).with("6 * 7").and_return(42)
  end

  it "fails before RSpec when the browser cannot produce a PDF and closes it" do
    allow(browser).to receive(:pdf).with(encoding: :binary).and_return("not a PDF")

    expect { load Rails.root.join("script/verify_test_browser.rb") }.to raise_error("Browser PDF verification failed")
    expect(browser).to have_received(:quit)
  end

  it "fails when the browser cannot execute JavaScript and closes it" do
    allow(browser).to receive(:evaluate).with("6 * 7").and_return(nil)

    expect { load Rails.root.join("script/verify_test_browser.rb") }.to raise_error("Browser JavaScript verification failed")
    expect(browser).to have_received(:quit)
  end
end
