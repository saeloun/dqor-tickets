Rails.application.routes.draw do
  root "home#index"
  get "tickets", to: "tickets#index", as: :tickets_store

  mount_avo at: "/avo"

  resource :checkin, only: %i[show create]

  resource :checkout_preview, only: :create
  resources :orders, param: :code, only: [ :create, :show ]
  get "tickets/find", to: "ticket_access#new", as: :find_tickets
  post "tickets/find", to: "ticket_access#create"
  get "tickets/access", to: "ticket_access#show", as: :ticket_access
  get "tickets/mine", to: "ticket_access#index", as: :my_tickets
  patch "orders/:code/tickets/:id/assign", to: "ticket_assignments#update", as: :assign_order_ticket
  get "claim/:claim_token", to: "ticket_assignments#show", as: :ticket_claim
  patch "claim/:claim_token", to: "ticket_assignments#update"
  post "payments/callback", to: "payments#callback", as: :payment_callback

  namespace :webhooks do
    resource :razorpay, only: :create, controller: "razorpay"
  end

  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token

  get "auth/google_oauth2/callback", to: "account/omniauth_sessions#create"
  get "auth/failure",                to: "account/omniauth_sessions#failure"

  namespace :account do
    get    "sign_in",      to: "sessions#new",     as: :sign_in
    post   "sign_in",      to: "sessions#create"
    get    "magic/:token", to: "sessions#magic",   as: :magic
    delete "sign_out",     to: "sessions#destroy", as: :sign_out
    resource :settings, only: %i[show update]
    resource :connection_scan, only: :show
    resource :calendar, only: :show
    post   "push_subscriptions", to: "push_subscriptions#create", as: :push_subscriptions
    delete "push_subscriptions", to: "push_subscriptions#destroy"
    resources :conversations, only: %i[index show create] do
      resources :messages, only: :create
    end
    root "dashboard#show"
  end

  get    "community",             to: "community#index",     as: :community
  get    "community/:id",         to: "community#show",      as: :attendee
  post   "community/:id/connect", to: "connections#create",  as: :connect_attendee
  delete "community/:id/connect", to: "connections#destroy", as: :disconnect_attendee

  get "/hotwire-native/path-configuration", to: "hotwire_native/path_configurations#show", as: :hotwire_native_path_configuration, defaults: { format: :json }

  get  "concierge", to: "concierge#show", as: :concierge
  post "concierge", to: "concierge#create"

  get  "schedule", to: "schedule#show", as: :schedule
  get  "sponsors", to: "sponsors#index", as: :sponsors
  get  "speakers", to: "speakers#index", as: :speakers
  get  "speakers/:id", to: "speakers#show", as: :speaker
  get  "updates",  to: "announcements#index", as: :updates
  get  "faq",      to: "faqs#index", as: :faq
  get  "info", to: "info_pages#index", as: :info_pages
  get  "info/:slug", to: "info_pages#show", as: :info_page
  get  "calendar", to: "calendar#show", as: :calendar
  get  "tickets/:secret/apple-pass", to: "apple_passes#show", as: :apple_pass

  # Crawler / answer-engine files (dynamic so the host is always correct).
  get "robots.txt",  to: "seo#robots",  as: :robots
  get "sitemap.xml", to: "seo#sitemap", as: :sitemap
  get "llms.txt",    to: "seo#llms",    as: :llms

  post   "talks/:talk_id/bookmark", to: "talk_bookmarks#create", as: :talk_bookmark
  delete "talks/:talk_id/bookmark", to: "talk_bookmarks#destroy"
  post   "talks/:talk_id/feedback", to: "talk_feedbacks#create", as: :talk_feedback
  resources :talks, only: :show do
    resources :questions, only: :create, controller: "talk_questions"
  end

  # Legacy marketing-site URLs (deccanqueenonrails.com) now served by this app.
  # Keep old inbound links / bookmarks working once the apex points here.
  get "cfp(/)",              to: redirect("/#cfp")
  get "venue(/)",            to: redirect("/#venue")
  get "rails-girls(/)",      to: redirect("/#rails-girls")
  get "explore-pune-day(/)", to: redirect("/#explore-pune-day")
  get "contact(/)",          to: redirect("/#contact")
  get "waitlist(/)",         to: redirect("/#tickets")
  get "thanks(/)",           to: redirect("/")
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

if defined? ::Avo
  Avo::Engine.routes.draw do
    get "dashboard", to: "tools#dashboard", as: :dashboard
  end
end
