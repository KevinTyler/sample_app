# Bringing people over from somewhere else — a Paperless Post guest-list spreadsheet, a Google,
# Outlook or phone contacts export, any spreadsheet, or a pasted list — in two steps: read and
# preview (what each column means, who's in it, duplicates, replies already given), then apply on
# the host's say-so. People land in the host's contacts (details filled in, never overwritten) and,
# optionally, on a guest list: a recreated event that keeps everyone's replies, or an existing one.
# The file's contents are erased once the import is applied or discarded (and after a day if neither).
class ContactImport < ApplicationRecord
  STALE_AFTER = 1.day
  MODES = %w[contacts new_event event].freeze

  belongs_to :user
  belongs_to :event, optional: true

  validates :status, inclusion: { in: %w[pending completed discarded] }

  scope :pending, -> { where(status: "pending") }
  scope :stale, -> { pending.where(created_at: ...STALE_AFTER.ago) }

  # Reads the file and saves a pending import, or raises Imports::Reader::Unreadable with a friendly reason.
  def self.read!(user, data, filename: nil)
    user.contact_imports.stale.update_all(status: "discarded", sheet: nil)
    sheet = Imports::Reader.read(data, filename: filename)
    import = user.contact_imports.new(filename: filename.to_s.first(200).presence, file_format: sheet.format.to_s,
      sheet: { "rows" => sheet.rows, "title_hint" => sheet.title_hint })
    raise Imports::Reader::Unreadable, "We couldn't find anyone in that file." if import.people.people.empty?
    raise Imports::Reader::Unreadable, "That list has more than #{Imports::Reader::MAX_ROWS} people — please split it up." if import.people.people.size > Imports::Reader::MAX_ROWS

    import.mapping = import.people.mapping.transform_keys(&:to_s)
    import.save!
    import
  end

  def pending? = status == "pending"

  def people
    @people ||= Imports::People.new(
      Imports::Reader::Sheet.new(rows: Array(sheet&.dig("rows")), format: file_format.to_s.to_sym, title_hint: sheet&.dig("title_hint")),
      mapping: mapping.presence, country_code: user.effective_phone_country_code
    )
  end

  # The host corrected what a column means (from the preview's pickers).
  def remap!(new_mapping)
    raise ActiveRecord::RecordInvalid, self unless pending?

    self.mapping = new_mapping.to_h.transform_keys(&:to_s).compact_blank
    @people = nil
    self.mapping = people.mapping.transform_keys(&:to_s)
    save!
  end

  def suggested_title
    people.title_hint.presence || "Imported guest list"
  end

  # One line for the agent and the preview header.
  def description
    c = people.counts
    parts = [ "#{c['people']} #{'person'.pluralize(c['people'])}", "#{c['emails']} with email", "#{c['phones']} with a mobile" ]
    parts << "#{c['addresses']} with a mailing address" if c["addresses"].positive?
    parts << "#{c['groups']} #{'group'.pluralize(c['groups'])} (#{people.groups.first(3).join(', ')})" if c["groups"].positive?
    parts << "replies: #{c['yes']} yes, #{c['no']} no#{", #{c['maybe']} maybe" if c['maybe'].positive?}, #{c['pending']} not yet" if people.has_replies?
    parts << "#{c['merged']} duplicate #{'row'.pluralize(c['merged'])} merged" if c["merged"].positive?
    "#{people.source_label}: #{parts.join('; ')}."
  end

  # mode: "contacts" (address book only), "new_event" (also recreate the event as a draft, with
  # everyone's replies), or "event" (also add everyone to `event`'s guest list). Returns the summary.
  def apply!(mode: "contacts", event: nil, title: nil, by: user)
    raise ActiveRecord::RecordInvalid, self unless pending?
    raise ArgumentError, "unknown import mode #{mode}" unless mode.in?(MODES)
    raise ArgumentError, "an event is required" if mode == "event" && event.nil?

    result = Hash.new(0)
    transaction do
      save_contacts!(result)
      target = mode == "new_event" ? recreate_event!(title, by) : (event if mode == "event")
      add_guests!(target, result, by) if target
      update!(status: "completed", sheet: nil, summary: result.merge("people" => people.people.size), event: target)
    end
    summary
  end

  def discard!
    update!(status: "discarded", sheet: nil) if pending?
  end

  private
    def save_contacts!(result)
      by_email = user.contacts.where.not(email: nil).index_by(&:email)
      by_phone = user.contacts.where.not(phone: nil).index_by(&:phone)
      people.people.each do |person|
        attrs = person.contact_attributes
        existing = (person.email && by_email[person.email]) || (person.phone && by_phone[person.phone])
        if existing
          missing = attrs.except(:name).select { |field, _| existing[field].blank? }
          missing.any? && existing.update(missing) ? result["contacts_updated"] += 1 : result["contacts_unchanged"] += 1
        elsif (contact = salvage(user.contacts.new(attrs)))
          by_email[contact.email] = contact if contact.email
          by_phone[contact.phone] = contact if contact.phone
          result["contacts_added"] += 1
        else
          result["contacts_skipped"] += 1
        end
      end
    end

    # Saves the record; if only its email or phone is unusable, saves it without them.
    def salvage(record)
      return record if record.save
      return unless (record.errors.attribute_names - %i[email phone]).empty?

      record.email = nil if record.errors.include?(:email)
      record.phone = nil if record.errors.include?(:phone)
      record if record.save
    end

    def recreate_event!(title, by)
      kids = people.people.any? { |p| p.kids.to_i.positive? }
      created = user.owned_events.create!(user.event_defaults.merge(title: (title.presence || suggested_title).first(120), track_kids: kids || user.default_track_kids))
      Activity.record(event: created, user: by, action: "event_created")
      created
    end

    def add_guests!(target, result, by)
      emails = target.guests.where.not(email: nil).pluck(:email).to_set
      phones = target.guests.where.not(phone: nil).pluck(:phone).to_set
      people.people.each do |person|
        if (person.email && emails.include?(person.email)) || (person.phone && phones.include?(person.phone))
          result["guests_already_listed"] += 1
          next
        end

        party = person.rsvp == "no" ? 0 : [ person.party_size || 1, 1 ].max
        allowed = [ person.plus_ones || target.default_plus_ones, party - 1 ].max.clamp(0, Guest::MAX_PLUS_ONES)
        guest = target.guests.new(name: person.name, email: person.email, phone: person.phone, group_name: person.group,
          plus_ones_allowed: allowed, source: "import", rsvp_status: person.rsvp, party_size: person.replied? ? party : 1,
          kids_count: person.rsvp == "no" ? 0 : person.kids.to_i, guest_note: (person.notes if person.replied?),
          responded_at: (Time.current if person.replied?))
        if salvage(guest)
          emails << guest.email if guest.email
          phones << guest.phone if guest.phone
          result["guests_added"] += 1
          result["replies_kept"] += 1 if person.replied?
        else
          result["guests_skipped"] += 1
        end
      end
      Activity.record(event: target, user: by, action: "guests_imported",
        data: { "created" => result["guests_added"], "updated" => 0, "skipped" => result["guests_skipped"] + result["guests_already_listed"] })
    end
end
