module Messaging
  module EmailGateway
    module_function

    def configured?
      true
    end

    def deliver(delivery)
      mail = GuestMailer.with(delivery: delivery).notice.deliver_now
      Receipt.new(provider: ActionMailer::Base.delivery_method.to_s, message_id: mail.message_id)
    end
  end
end
