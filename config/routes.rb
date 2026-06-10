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

  namespace :admin do
    resources :users do
      member do
        post :activate
        post :deactivate
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
