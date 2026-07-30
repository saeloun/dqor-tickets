Rails.application.routes.draw do
  root "tickets#index"

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

  get "/login", to: "logins#show", as: :login
  get "/me", to: "me#show", as: :me

  get "/auth/github/callback", to: "users/omniauth_callbacks#github", as: :github_callback
  get "/auth/failure", to: "users/omniauth_callbacks#failure", as: :auth_failure

  get "/user/magic-link", to: "users/magic_links#new", as: :new_user_magic_link
  post "/user/magic-link", to: "users/magic_links#create", as: :user_magic_links
  get "/user/magic-link/:token", to: "users/magic_links#show", as: :user_magic_link
  delete "/user/session", to: "users/sessions#destroy", as: :user_session

  get "/hotwire-native/path-configuration", to: "hotwire_native/path_configurations#show", as: :hotwire_native_path_configuration, defaults: { format: :json }

  get "/:organizer_slug/:event_slug", to: "events#show", as: :event
  post "/:organizer_slug/:event_slug/register", to: "registrations#create", as: :event_registrations
  delete "/:organizer_slug/:event_slug/register", to: "registrations#destroy"
  get "/:organizer_slug/:event_slug/guests", to: "registrations#index", as: :event_guests

  # Define your application routes per the DSL in https://guides.ruby-rails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

if defined? ::Avo
  Avo::Engine.routes.draw do
    get "dashboard", to: "tools#dashboard", as: :dashboard
  end
end
