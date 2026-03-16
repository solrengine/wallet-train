Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get  "login",       to: "sessions#new",     as: :login
  get  "auth/nonce",  to: "sessions#nonce",   as: :auth_nonce
  post "auth/verify", to: "sessions#create",  as: :auth_verify
  delete "logout",    to: "sessions#destroy",  as: :logout

  # Dashboard
  get "dashboard", to: "dashboard#show", as: :dashboard

  # Transfers
  resources :transfers, only: [ :new, :create, :show, :update ] do
    member do
      get :status
    end
  end

  # Network switching
  patch "network", to: "networks#update", as: :network

  root "sessions#new"
end
