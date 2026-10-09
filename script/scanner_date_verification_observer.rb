require File.expand_path("spec/rails_helper.rb", Dir.pwd)

module ScannerDateDiagnostic
  SNAPSHOT = <<~JS
    (() => {
      const select = document.querySelector('select[name="date"]');
      const element = document.querySelector('[data-controller="checkin"]');
      const controller = element && window.Stimulus?.getControllerForElementAndIdentifier(element, 'checkin');
      return { readyState: document.readyState, cuprite: typeof window._cuprite, selectCount: document.querySelectorAll('select[name="date"]').length, selectConnected: select?.isConnected, value: select?.value, disabled: select?.disabled, options: select && Array.from(select.options).map(option => ({ value: option.value, selected: option.selected, text: option.text, connected: option.isConnected })), controller: !!controller, controllerConnected: controller?.connected, controllerBusy: controller?.busy, controllerDate: controller?.hasDateTarget ? controller.dateTarget.value : undefined, ariaBusy: element?.getAttribute('aria-busy'), loadedLabel: document.querySelector('.checkin-stat__label')?.textContent };
    })()
  JS
  class << self
    attr_accessor :active, :errors, :errors_truncated, :phase, :observation

    def error(exception, command)
      return unless active
      if errors.size >= 20
        self.errors_truncated = true
        return
      end
      message = exception.message
      known = [ "_cuprite is not defined", "Cannot find context with specified id", "Could not find node with given id", "Node is detached from document" ].find { |text| message.include?(text) }
      errors << { exception: exception.class.name, command: command.to_s, phase: phase, known_driver_message: known }
    end
  end
end

module ScannerDateNodeErrors
  def command(name, *args)
    super
  rescue StandardError => exception
    ScannerDateDiagnostic.error(exception, name)
    raise
  end
end
Capybara::Cuprite::Node.prepend(ScannerDateNodeErrors)

module ScannerDateActions
  def select(value, **options)
    if ScannerDateDiagnostic.active && ScannerDateDiagnostic.phase == "open_desk" && options[:from] == "date"
      snapshot = ScannerDateDiagnostic::SNAPSHOT
      begin
        execute_script(<<~JS, snapshot)
        if (!window.scannerDateTrace) {
          const entries = [];
          let bytes = 0;
          let truncated = false;
          const state = () => { try { return eval(arguments[0]); } catch (error) { return {diagnostic_error: error.name}; } };
          const record = (kind, event) => {
            if (truncated || entries.length >= 40 || bytes >= 16000) { truncated = true; return; }
            const serialized = JSON.stringify({kind, time: Math.round(performance.now()), trusted: event?.isTrusted, state: state()});
            const size = new TextEncoder().encode(serialized).byteLength;
            if (bytes + size <= 16000) { entries.push(JSON.parse(serialized)); bytes += size; } else { truncated = true; }
          };
          const listeners = [];
          for (const name of ['change', 'turbo:submit-start', 'turbo:submit-end', 'turbo:before-render', 'turbo:render', 'turbo:load']) {
            const listener = event => { if (name !== 'change' || event.target.matches('select[name="date"]')) record(name, event); };
            document.addEventListener(name, listener, {capture: true, passive: true});
            listeners.push([name, listener]);
          }
          window.scannerDateTrace = () => {
            listeners.forEach(([name, listener]) => document.removeEventListener(name, listener, true));
            record('collected');
            return {entries, bytes, truncated};
          };
          record('before-select');
        }
        JS
      rescue StandardError => exception
        ScannerDateDiagnostic.error(exception, "trace_install")
      end
    end
    super
  end
end
Capybara::Session.prepend(ScannerDateActions)

module ScannerDateDeskObservation
  def open_desk
    ScannerDateDiagnostic.phase = "open_desk"
    super
  ensure
    ScannerDateDiagnostic.observation = {}
    begin
      ScannerDateDiagnostic.observation[:final] = page.evaluate_script(ScannerDateDiagnostic::SNAPSHOT)
    rescue StandardError => exception
      ScannerDateDiagnostic.observation[:snapshot_error] = exception.class.name
    end
    begin
      ScannerDateDiagnostic.observation[:trace] = page.evaluate_script("window.scannerDateTrace?.() || {entries: [], bytes: 0, truncated: false}")
    rescue StandardError => exception
      ScannerDateDiagnostic.observation[:trace_error] = exception.class.name
    end
    ScannerDateDiagnostic.phase = "after_open_desk"
  end
end

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:file_path].include?("checkin_result_visibility_spec")
      example.example_group.prepend(ScannerDateDeskObservation) unless example.example_group.ancestors.include?(ScannerDateDeskObservation)
    end
  end
  config.around(:each, type: :system) do |example|
    ScannerDateDiagnostic.active = example.metadata[:file_path].include?("checkin_result_visibility_spec")
    ScannerDateDiagnostic.errors = []
    ScannerDateDiagnostic.errors_truncated = false
    ScannerDateDiagnostic.observation = {}
    example.run
  ensure
    puts "SCANNER_DATE_DIAGNOSTIC=#{ ScannerDateDiagnostic.observation.merge(errors: ScannerDateDiagnostic.errors, errors_truncated: ScannerDateDiagnostic.errors_truncated).to_json }" if ScannerDateDiagnostic.active
    ScannerDateDiagnostic.active = false
  end
end
