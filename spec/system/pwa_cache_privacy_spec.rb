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
end
