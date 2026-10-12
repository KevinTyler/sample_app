require Rails.root.join("lib/mail_delivery/outbox").to_s

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :outbox, MailDelivery::Outbox
  add_delivery_method :unconfigured, MailDelivery::Unconfigured
end
