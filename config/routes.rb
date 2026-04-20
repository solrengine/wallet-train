Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # SIWS authentication — bundled controller from solrengine-auth.
  mount Solrengine::Auth::Engine => "/auth", as: :solrengine_auth

  # Dashboard
  get "dashboard", to: "dashboard#show", as: :dashboard

  # Transfers
  resources :transfers, only: [ :new, :create, :show, :update ] do
    member do
      get :status
    end
  end


  root "pages#landing"
end
