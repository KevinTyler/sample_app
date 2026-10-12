# Loads @event for host-side controllers. Events outside the user's access raise 404
# (we don't reveal that they exist); events the user can see but not change raise 403.
module EventScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_event
    helper_method :policy
    rescue_from EventPolicy::NotAuthorized, with: :forbidden
  end

  private
    def set_event
      @event = current_user.accessible_events.find(params[:event_id] || params[:id])
    end

    def policy
      @policy ||= EventPolicy.new(current_user, @event)
    end

    def authorize!(permission)
      policy.authorize!(permission)
    end

    def forbidden(error)
      respond_to do |format|
        format.html { redirect_to event_path(@event), alert: error.message, status: :see_other }
        format.any { head :forbidden }
      end
    end
end
