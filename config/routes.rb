Rails.application.routes.draw do
  root "cases#index"

  resource :session
  resources :passwords, param: :token
  post "locale", to: "locales#update", as: :locale

  resources :cases do
    member do
      post :transition
      post :assign
    end
    resources :messages, only: :create
  end
  resources :contacts
  resources :organisations
  resources :queues, controller: "case_queues", as: :case_queues, except: :show
  resources :categories, except: :show
  resources :sla_policies, except: :show
  resources :macros, except: :show

  namespace :admin do
    resources :users do
      member do
        post :activate
        post :deactivate
      end
    end
    get "activity", to: "activity#index", as: :activity
    get "audit", to: "audit#show", as: :audit
  end

  namespace :portal do
    root to: "cases#new"
    resources :cases, only: %i[new create]
    get "track", to: "tracking#new", as: :track
    post "track", to: "tracking#show", as: :track_lookup
    post "track/reply", to: "tracking#reply", as: :track_reply
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
