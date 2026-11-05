Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  resources :agents, except: %i[destroy] do
    collection do
      get :bulk_new
      post :bulk_create
      post :bulk_move
    end
    member do
      patch :deactivate
      patch :reactivate
      post :override_status
    end
  end

  resources :teams do
    resources :team_accesses, only: %i[create destroy]
  end

  resources :statuses, only: %i[index new create edit update] do
    collection { patch :reorder }
  end

  resources :audit_logs, only: :index

  get "board", to: "board#show", as: :board

  # Super User: webhook URL, API key, and fixing phone events we couldn't place.
  resource :integration, only: :show do
    post :regenerate_key
    post :map_code
    post :link_agent
  end

  # The phone system's webhook (section 5).
  namespace :api do
    namespace :v1 do
      resources :status_events, only: :create
    end
  end

  root "home#show"
end
