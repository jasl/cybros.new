Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
  mount ActionCable.server => "/cable"

  namespace :agent_api do
    resources :registrations, only: :create
    resources :heartbeats, only: :create
    resource :health, only: :show, controller: :health
    resource :capabilities, only: [:show, :create], controller: :capabilities
    resources :conversation_transcripts, only: :index
    resources :conversation_diagnostics, only: [] do
      collection do
        get "show"
        get "turns"
      end
    end
    resources :conversation_variables, only: [] do
      collection do
        get "get"
        post "mget"
        get "exists"
        get "list_keys"
        get "resolve"
        post "set"
        post "delete"
        post "promote"
      end
    end
    resources :workspace_variables, only: :index do
      collection do
        get "get", action: :show_value
        post "mget", action: :bulk_show
        post "write"
      end
    end
    resources :human_interactions, only: :create
    resources :tool_invocations, only: :create
    resources :command_runs, only: :create do
      post :activate, on: :member
    end
    resources :process_runs, only: :create
    post "control/poll", to: "control#poll"
    post "control/report", to: "control#report"
  end

  if Rails.env.development? || Rails.env.test?
    namespace :mock_llm do
      namespace :v1 do
        post "chat/completions", to: "chat_completions#create"
        get "models", to: "models#index"
      end
    end
  end
end
