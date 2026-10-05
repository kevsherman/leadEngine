namespace :worker do
  desc "Fail unless a Solid Queue worker has a recent heartbeat"
  task health: :environment do
    healthy = SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", 2.minutes.ago).exists?
    abort "No healthy worker. Start bin/dev or bin/jobs." unless healthy
    puts "Solid Queue worker heartbeat is healthy."
  end
end
