namespace :demo do
  desc "Load the fictional demo dataset. DOCKET_SEED_SCENARIO=saas|retail|gov (default saas), on a fresh DB."
  task seed: :environment do
    # Seed creation exercises normal model callbacks, many of which enqueue
    # asynchronous analysis/notification work. Running those jobs concurrently
    # with a large SQLite seed can hold locks and keep the one-shot rake process
    # alive indefinitely. Demo rows already contain their intended derived
    # state, so record the jobs without performing them; the booted app resumes
    # its configured adapter normally in the next process.
    ActiveJob::Base.queue_adapter = :test
    load Rails.root.join("db/seeds/demo.rb")
  end
end
