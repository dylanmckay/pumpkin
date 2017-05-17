Rails.application.routes.draw do
  root 'static#index'

  resources :occurrences, only: [:create]
  resources :environments, only: [:index]
  resources :bugs, only: [:index, :show] do
    member do
      post :close
      post :create_issue
    end

    resources :occurrences, only: [:index]
  end

  get '/monitoring/heartbeat', to: 'heartbeat#index'
end
