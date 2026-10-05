require "rails_helper"

RSpec.describe "PWA cache privacy", type: :system do
  it "never caches navigations or private images, honors privacy headers, and removes old caches" do
    visit account_sign_in_path
    worker = Rails.root.join("app/views/pwa/service-worker.js").read
    result = page.evaluate_async_script(<<~JS, worker)
      const source = arguments[0], done = arguments[arguments.length - 1];
      (async () => {
        const handlers = {}, stored = new Map(), removed = [], matches = [];
        let fail = false, cacheControl = "public, max-age=300";
        const cache = {
          put: async (request, response) => stored.set(request.url, response),
          delete: async (request) => stored.delete(request.url),
          addAll: async () => {}
        };
        const caches = {
          open: async () => cache,
          keys: async () => ["dqor-shell-v1", "dqor-runtime-v1", "dqor-shell-v2", "unrelated-app-cache"],
          delete: async (name) => { removed.push(name); return true; },
          match: async (request) => { matches.push(request); return new Response("Offline page"); }
        };
        const self = { location: { origin: location.origin }, clients: { claim: async () => {} },
          addEventListener: (name, handler) => { handlers[name] = handler; } };
        const fetch = async () => { if (fail) throw new Error("offline"); return new Response("private data", { headers: { "Cache-Control": cacheControl } }); };
        new Function("self", "caches", "fetch", source)(self, caches, fetch);
        let activation;
        handlers.activate({ waitUntil: (promise) => { activation = promise; } });
        await activation;
        const request = async (path, mode, destination) => {
          let response;
          handlers.fetch({ request: { url: location.origin + path, method: "GET", mode, destination },
            respondWith: (promise) => { response = promise; } });
          if (response) await response;
          return !!response;
        };
        await request("/free/tickets", "navigate", "document");
        await request("/organizer/organizations/1/events", "navigate", "document");
        const navigationsStored = stored.size;
        const imageIntercepted = await request("/rails/active_storage/blobs/private/avatar.png", "cors", "image");
        cacheControl = "private, no-store";
        await request("/assets/private.css", "cors", "style");
        const privateStored = stored.size;
        cacheControl = "public, max-age=300";
        await request("/assets/public.css", "cors", "style");
        const publicStored = stored.size;
        cacheControl = "no-store";
        await request("/assets/public.css", "cors", "style");
        const revokedStored = stored.size;
        fail = true;
        await request("/free/tickets", "navigate", "document");
        return { removed, navigationsStored, imageIntercepted, privateStored, publicStored, revokedStored, matches };
      })().then(done).catch((error) => done({ error: String(error) }));
    JS
    expect(result).to include("navigationsStored" => 0, "imageIntercepted" => false,
      "privateStored" => 0, "publicStored" => 1, "revokedStored" => 0)
    expect(result.fetch("removed")).to contain_exactly("dqor-shell-v1", "dqor-runtime-v1")
    expect(result.fetch("matches")).to eq([ "/offline.html" ])
  end

  it "activates a real worker, purges old private caches, and does not recover a ticket after logout offline" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    user = create(:user_for_free_pilot, name: "PRIVATE_OFFLINE_ATTENDEE")
    org = Organization.create!(name: "Offline test", slug: "offline-test")
    event = org.events.create!(title: "Offline test event", slug: "meetup", status: :published, starts_at: Time.current, ends_at: 1.day.from_now)
    type = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 2, free_published_at: Time.current)
    FreeEvents::Register.call(user: user, event_id: event.id, ticket_type_id: type.id)
    private_path = free_event_ticket_path(org.slug, event.slug)

    # Ferrum pauses newly attached targets but only resumes pages/iframes.
    # Let the genuine service worker execute its install/activate handlers.
    page.driver.browser.command("Target.setAutoAttach", autoAttach: true, waitForDebuggerOnStart: false, flatten: true)
    visit "/offline.html"
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      navigator.serviceWorker.getRegistrations().then((items) => Promise.all(items.map((item) => item.unregister()))).then(() => done(true)).catch((error) => done({ error: String(error) }));
    JS
    visit "/offline.html"
    activated = page.evaluate_async_script(<<~JS, private_path)
      const privatePath = arguments[0], done = arguments[arguments.length - 1];
      (async () => {
        for (const name of ["dqor-shell-v1", "dqor-runtime-v1"]) {
          const cache = await caches.open(name);
          await cache.put(privatePath, new Response("PRIVATE_STALE_TICKET"));
        }
        await caches.open("synthetic-unrelated-cache");
        await navigator.serviceWorker.register("/service-worker.js", { scope: "/" });
        await navigator.serviceWorker.ready;
        if (!navigator.serviceWorker.controller) {
          await new Promise((resolve) => navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true }));
        }
        return { keys: await caches.keys(), controlled: !!navigator.serviceWorker.controller };
      })().then(done).catch((error) => done({ error: String(error) }));
    JS
    expect(activated.fetch("controlled")).to be(true)
    expect(activated.fetch("keys")).to include("dqor-shell-v2", "synthetic-unrelated-cache")
    expect(activated.fetch("keys")).not_to include("dqor-shell-v1", "dqor-runtime-v1")

    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    visit private_path
    expect(page).to have_content("PRIVATE_OFFLINE_ATTENDEE")
    expect(page.evaluate_async_script(<<~JS, private_path)).to be(false)
      const path = arguments[0], done = arguments[arguments.length - 1];
      caches.match(path).then((response) => done(!!response));
    JS
    expect(page.evaluate_async_script(<<~JS)).to be(true)
      const done = arguments[arguments.length - 1];
      fetch("/account/sign_out", { method: "POST", body: new URLSearchParams({ _method: "delete" }), headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" } }).then((response) => done(response.ok));
    JS
    visit "/offline.html"
    # A service worker has its own network target; page-only offline emulation
    # does not stop its fetches. Put both genuine targets offline.
    browser = page.driver.browser
    worker_sessions = browser.command("Target.getTargets").fetch("targetInfos")
      .select { |target| target["type"] == "service_worker" && target["url"].include?("/service-worker.js") }
      .map do |target|
        id = browser.command("Target.attachToTarget", targetId: target.fetch("targetId"), flatten: true).fetch("sessionId")
        worker = browser.client.session(id)
        worker.command("Network.enable")
        worker.command("Network.emulateNetworkConditions", offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0)
        worker
      end
    expect(worker_sessions).not_to be_empty
    browser.network.offline_mode
    page.go_back
    expect(page).to have_content("You're offline")
    expect(page).not_to have_content("PRIVATE_OFFLINE_ATTENDEE")
    expect(page).not_to have_content("PRIVATE_STALE_TICKET")
    expect(page).to have_content("Private tickets and account pages need a connection")
    page.save_screenshot(Rails.root.join("tmp/free-pilot-offline-logout.png"))
  ensure
    Array(worker_sessions).each do |worker|
      worker.command("Network.emulateNetworkConditions", offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
    end
    page.driver.browser.network.emulate_network_conditions(offline: false)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      Promise.all([
        navigator.serviceWorker.getRegistrations().then((items) => Promise.all(items.map((item) => item.unregister()))),
        caches.keys().then((keys) => Promise.all(keys.filter((key) => key.startsWith("dqor-") || key === "synthetic-unrelated-cache").map((key) => caches.delete(key))))
      ]).then(() => done(true)).catch((error) => done({ error: String(error) }));
    JS
    page.driver.browser.command("Target.setAutoAttach", autoAttach: true, waitForDebuggerOnStart: true, flatten: true)
  end
end
