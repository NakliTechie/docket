namespace :demo do
  desc "Load the fictional demo dataset. DOCKET_SEED_SCENARIO=saas|retail|gov (default saas), on a fresh DB."
  task seed: :environment do
    load Rails.root.join("db/seeds/demo.rb")
  end
end
