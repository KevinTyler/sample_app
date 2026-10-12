# Development stand-in for a hosted payment page. The signed token names the payment and where to
# return; nothing here talks to a real payment provider.
class Dev::CheckoutsController < ApplicationController
  allow_unauthenticated_access
  layout "guest"
  before_action :load_checkout

  def show
  end

  def create
    if params[:outcome] == "cancel"
      redirect_to @data["cancel"], allow_other_host: true # signed by us, not user input
    else
      @payment.mark_paid!(provider_payment_id: "fake_pi_#{SecureRandom.hex(6)}")
      redirect_to @data["success"], allow_other_host: true, notice: "Payment received — thank you!"
    end
  end

  private
    def load_checkout
      return head(:not_found) unless Payments.provider == "fake"

      @data = Payments::FakeGateway.verifier.verified(params[:token])
      @payment = @data && Payment.find_by(id: @data["payment_id"])
      render plain: "This test checkout link is invalid or expired.", status: :not_found unless @payment
    end
end
