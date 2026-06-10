namespace :demo do
  desc "Load the fictional demo dataset (Directorate of Public Grievances + bank branch)"
  task seed: :environment do
    load Rails.root.join("db/seeds/demo.rb")
  end
end
