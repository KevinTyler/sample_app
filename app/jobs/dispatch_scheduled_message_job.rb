# Sends one scheduled message at its time. Enqueued with wait_until when the host schedules it;
# DispatchDueMessagesJob sweeps up anything missed (e.g. after a restart), and the atomic claim in
# Message#dispatch_scheduled! makes running both harmless.
class DispatchScheduledMessageJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    Message.find(message_id).dispatch_scheduled!
  end
end
