class DeliveryJob < ApplicationJob
  queue_as :default

  retry_on Delivery::TransientError, wait: :polynomially_longer, attempts: Delivery::MAX_ATTEMPTS
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    Delivery.find(delivery_id).deliver_now!
  end
end
