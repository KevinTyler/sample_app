# What a signed-in user may do with an event. Roles come from Event#role_for.
class EventPolicy
  PERMISSIONS = {
    "owner" => %i[view edit publish cancel destroy manage_guests view_contacts send_messages manage_cohosts check_in],
    "editor" => %i[view edit publish manage_guests view_contacts send_messages check_in],
    "checkin" => %i[view check_in]
  }.freeze

  class NotAuthorized < StandardError; end

  attr_reader :user, :event, :role

  def initialize(user, event)
    @user = user
    @event = event
    @role = event.role_for(user)
  end

  def can?(permission)
    PERMISSIONS.fetch(role, []).include?(permission)
  end

  def authorize!(permission)
    can?(permission) || raise(NotAuthorized, "You don't have permission to do that for this event.")
  end
end
