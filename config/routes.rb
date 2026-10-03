Rails.application.routes.draw do
  resource :scanner_rehearsal, only: :show
  get "free", to: "free_events/organizations#index", as: :free_organizations
  get "free/organizations/new", to: "free_events/organizations#new", as: :new_free_organization
  post "free", to: "free_events/organizations#create"
  get "free/tickets", to: "free_events/registrations#index", as: :free_tickets
  get "free/events/:organization_slug/:event_slug/ticket", to: "free_events/registrations#show", as: :free_event_ticket
  get "free/events/:organization_slug/:event_slug/register/:ticket_type_id", to: "free_events/registrations#new", as: :new_free_event_registration
  post "free/events/:organization_slug/:event_slug/register", to: "free_events/registrations#create", as: :free_event_registration
  get "free/organizations/:organization_id/events/:event_id/inventory/new", to: "free_events/inventory#new", as: :new_free_event_inventory
  post "free/organizations/:organization_id/events/:event_id/inventory", to: "free_events/inventory#create", as: :free_event_inventory
  get "free/organizations/:organization_id/events/:event_id/attendees", to: "free_events/attendees#index", as: :free_event_attendees
  post "free/organizations/:organization_id/events/:event_id/attendees", to: "free_events/attendees#create"
  get "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/window", to: "free_events/registration_windows#show", as: :free_event_window
  patch "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/window", to: "free_events/registration_windows#update"
  get "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/questions", to: "free_events/question_forms#show", as: :free_event_questions
  patch "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/questions", to: "free_events/question_forms#update"
  get "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/questions/preview", to: "free_events/question_forms#preview", as: :preview_free_event_questions
  get "free/organizations/:organization_id/events/:event_id/types/:ticket_type_id/questions/answers.csv", to: "free_events/question_forms#export", as: :export_free_event_answers
  resources :announcement_campaigns, only: [ :show ], param: :id do
    member do
      get :draft
      post :retry_failed
    end
  end
  post "announcement_campaigns/:id", to: "announcement_campaigns#create"
  patch "account/announcement_preference", to: "announcement_preferences#update", as: :account_announcement_preference
  get "announcement_unsubscribe/:token", to: "announcement_preferences#unsubscribe", as: :announcement_unsubscribe
  post "announcement_unsubscribe/:token", to: "announcement_preferences#suppress"
  get "api/public/v1/dqor/programme", to: "api/public/v1/programmes#show", defaults: { format: :json }

  resources :event_slots, only: %i[index show new create edit update] do
    member do
      post :redeem
      post :correct
    end
  end
  get "account/redemptions", to: "account/redemptions#index", as: :account_redemptions
  namespace :hiring do
    root "board#index"
    get "applications/:id/resume", to: "resumes#show", as: :resume
    post "jobs/:job_id/shares", to: "shares#create", as: :shares
    get "recruiting/:token", to: "shares#show", as: :recruiting
    post "recruiting/:token", to: "shares#confirm"
    delete "shares/:id", to: "shares#revoke", as: :revoke_share
    delete "affiliations/:id", to: "board#remove_affiliation", as: :remove_affiliation
    post "claims", to: "board#claim", as: :claims
    post "claims/:id/review", to: "board#review_claim", as: :review_claim
    post "companies/:company_id/jobs", to: "board#create_job", as: :jobs
    post "companies/:company_id/affiliation", to: "board#affiliate", as: :affiliation
    get "jobs/:id", to: "board#show", as: :job
    post "jobs/:id/apply", to: "board#apply", as: :apply
    get "jobs/:id/applicants", to: "board#applicants", as: :applicants
    delete "applications/:id", to: "board#withdraw", as: :withdraw
  end
  namespace :organizer do
    resources :organizations, only: [] do
      resources :events, except: :destroy do
        post :publish, on: :member
        patch "operations/deals/:id/commit", to: "operations#commit_deal", as: :commit_operation_deal
        get "operations", to: "operations#index", as: :operations
        post "operations/:kind", to: "operations#create", as: :operation_records
        patch "operations/tasks/:id", to: "operations#complete", as: :complete_operation_task
        get "operations/contacts/:id/draft", to: "operations#draft", as: :operation_draft
      end
    end
  end
  get "events/:organization_slug/:event_slug", to: "published_events#show", as: :published_event

  root "home#index"
  get "tickets", to: "tickets#index", as: :tickets_store

  # Singleton branding for the existing DQOR event; existing admin role only.
  namespace :organizer do
    resource :branding, only: %i[show update], controller: "event_branding" do
      get :preview
      post :publish
      post :rollback
      get "assets/:id", action: :asset, as: :asset
    end
  end

  mount_avo at: "/avo"

  resource :checkin, only: %i[show create] do
    post :batch
  end

  get "account/native/authorize", to: "account/native/authorizations#new", as: :native_attendee_authorize
  post "account/native/email", to: "account/native/authorizations#email", as: :native_attendee_email
  get "account/native/verify", to: "account/native/authorizations#verify", as: :native_attendee_verify
  get "account/native/consent", to: "account/native/authorizations#consent", as: :native_attendee_consent
  post "account/native/consent", to: "account/native/authorizations#approve"
  post "account/native/cancel", to: "account/native/authorizations#cancel", as: :native_attendee_cancel

  namespace :api do
    namespace :native do
      namespace :attendee do
        namespace :v1 do
          resource :account, only: :show
          resources :passes, only: :index
          resource :session, only: %i[show destroy]
          resource :token, only: :create
        end
      end
    end
    namespace :attendee do
      namespace :v1 do
        resource :account, only: :show
        resources :passes, only: :index
      end
    end
    namespace :staff do
      resource :session, only: %i[create show destroy]
      resources :checkins, only: :index do
        collection do
          post :resolve
          post :confirm
        end
      end
    end
  end

  namespace :finance do
    resources :documents, only: %i[index show update] do
      post :request_details, on: :member
      post :retry_document, on: :member
    end
    resources :policies, only: %i[index new create show update] do
      post :configure, on: :member
      post :approve, on: :member
      post :duplicate, on: :member
      post :reopen, on: :member
    end
  end
  resource :billing_details, only: %i[show update], controller: "billing_details"

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
  get "chat/login", to: "chat_logins#show", as: :chat_login
  post "chat/login/redeem", to: "chat_login_redemptions#create", as: :redeem_chat_login

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
  get  "tickets/:secret/google-pass", to: "google_wallet_passes#show", as: :google_wallet_pass
  get "team", to: "team#index", as: :team
  get "coc", to: "pages#code_of_conduct", as: :code_of_conduct

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
