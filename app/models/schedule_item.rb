# One part of a multi-part event (e.g. the sangeet of a wedding weekend). Guests in its groups
# (or everyone, when no groups are chosen) see it on their invitation and can say which parts
# they'll attend.
class ScheduleItem < ApplicationRecord
  MAX_PER_EVENT = 12

  belongs_to :event
  has_many :replies, class_name: "ScheduleReply", dependent: :delete_all

  normalizes :name, with: ->(v) { v.to_s.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :location_name, length: { maximum: 120 }
  validates :address, length: { maximum: 300 }
  validates :description, length: { maximum: 1000 }
  validate :times_parse_and_order
  validate :within_limit, on: :create

  before_validation :resolve_local_times

  default_scope { order(:position, :starts_at, :id) }

  %w[starts_at ends_at].each do |field|
    define_method(:"#{field}_local") do
      instance_variable_defined?(:"@#{field}_local") ? instance_variable_get(:"@#{field}_local") : public_send(field)&.in_time_zone(event.zone)&.strftime("%Y-%m-%dT%H:%M")
    end

    define_method(:"#{field}_local=") { |value| instance_variable_set(:"@#{field}_local", value.to_s.strip.presence) }
  end

  def audience_groups
    Array(super).map(&:to_s).compact_blank
  end

  def audience_groups=(groups)
    super(Array(groups).map { |g| g.to_s.squish }.compact_blank.uniq.first(30))
  end

  def for_everyone?
    audience_groups.empty?
  end

  def invited?(guest)
    for_everyone? || audience_groups.include?(guest.group_name.to_s)
  end

  def guests
    for_everyone? ? event.guests : event.guests.where(group_name: audience_groups)
  end

  def headcount
    guests.where(rsvp_status: "yes", id: replies.where(attending: true).select(:guest_id)).sum(:party_size)
  end

  def where_text
    [ location_name, address ].compact_blank.join(", ").presence
  end

  private
    def resolve_local_times
      @bad_times = []
      %w[starts_at ends_at].each do |field|
        next unless instance_variable_defined?(:"@#{field}_local")

        raw = instance_variable_get(:"@#{field}_local")
        if raw.nil?
          public_send(:"#{field}=", nil)
        elsif raw.match?(Event::LOCAL_TIME_FORMAT) && event && (parsed = event.zone.parse(raw))
          public_send(:"#{field}=", parsed)
        else
          @bad_times << field
        end
      end
    end

    def times_parse_and_order
      Array(@bad_times).each { |field| errors.add(field, "is not a valid date and time") }
      errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
    end

    def within_limit
      errors.add(:base, "An event can have up to #{MAX_PER_EVENT} parts") if event && event.schedule_items.count >= MAX_PER_EVENT
    end
end
