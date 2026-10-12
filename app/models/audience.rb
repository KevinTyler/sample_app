# Which guests a message targets. Stored on Message#audience as JSON:
#   { "statuses" => ["pending", "maybe"], "groups" => ["Family"], "guest_ids" => [1, 2], "resend" => false }
# Empty filters mean "everyone".
class Audience
  attr_reader :event, :statuses, :groups, :guest_ids

  def initialize(event, attrs = {})
    attrs = (attrs || {}).to_h.stringify_keys
    @event = event
    @statuses = Array(attrs["statuses"]).map(&:to_s).compact_blank & Guest::RSVP_STATUSES
    @groups = Array(attrs["groups"]).map(&:to_s).compact_blank
    @guest_ids = Array(attrs["guest_ids"]).map(&:to_i).select(&:positive?)
    @resend = ActiveModel::Type::Boolean.new.cast(attrs["resend"]) || false
  end

  def resend?
    @resend
  end

  def guests
    scope = event.guests
    scope = scope.where(rsvp_status: statuses) if statuses.any?
    scope = scope.where(group_name: groups) if groups.any?
    scope = scope.where(id: guest_ids) if guest_ids.any?
    scope
  end

  def to_h
    { "statuses" => statuses, "groups" => groups, "guest_ids" => guest_ids, "resend" => resend? }
  end

  def everyone?
    statuses.empty? && groups.empty? && guest_ids.empty?
  end

  def description
    return "#{guest_ids.size} selected #{'guest'.pluralize(guest_ids.size)}" if guest_ids.any?
    return "All guests" if everyone?

    parts = []
    parts << statuses.map { |s| RsvpHelper::STATUS_LABELS.fetch(s, s) }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ") if statuses.any?
    parts << "in #{groups.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}" if groups.any?
    "Guests: #{parts.join(' ')}"
  end
end
