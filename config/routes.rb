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
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

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
