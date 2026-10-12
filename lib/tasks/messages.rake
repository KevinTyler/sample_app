namespace :messages do
  desc "Dispatch scheduled guest messages whose send time has passed (production runs this every minute via Solid Queue)"
  task dispatch_due: :environment do
    count = Message.due.count
    DispatchDueMessagesJob.perform_now
    puts "Dispatched #{count} scheduled #{'message'.pluralize(count)}."
  end
end
