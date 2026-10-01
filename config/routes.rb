Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resources :passwords, param: :token, only: %i[ new create edit update ]

  resources :students do
    resources :student_weekdays, only: %i[ create destroy ]
  end

  namespace :tools do
    namespace :pdf_splitter do
      resources :jobs, only: %i[ index show create destroy ] do
        member do
          post  :analyze
          post  :split
          match :update_boundaries, via: %i[ patch post ]
          patch :update_names
          get   :print
          get   :print_bundle
          get   :download_zip
          get   :thumbnail
        end
        resources :outputs, only: [] do
          member do
            get :print
            get :download
          end
        end
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Phase 2 で lessons#index に変更する
  root "home#index"
end
