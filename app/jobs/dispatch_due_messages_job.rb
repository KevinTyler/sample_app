# Recurring safety net (config/recurring.yml): dispatches scheduled messages whose time has come.
class DispatchDueMessagesJob < ApplicationJob
  queue_as :default

  def perform
    Message.due.find_each(&:dispatch_scheduled!)
  end
end
