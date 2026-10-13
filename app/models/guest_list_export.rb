require "csv"

# The host's guest-list spreadsheet: contact details, RSVP state, answers and check-in.
# Every cell goes through CsvSafety, since names, notes and answers are typed by guests.
class GuestListExport
  def initialize(event)
    @event = event
    @questions = event.questions.to_a
    @items = event.schedule_items.select(&:collects_replies)
  end

  def to_csv
    CSV.generate do |csv|
      csv << header
      @event.guests.includes(:rsvp_answers, :payments, :schedule_replies).order(:name).each { |guest| csv << CsvSafety.row(row(guest)) }
    end
  end

  private
    def header
      [ "Name", "Email", "Phone", "Group", "Plus-ones allowed", "RSVP", "Party size", *([ "Adults", "Kids" ] if @event.track_kids?), "Plus-one names", "Responded at",
        "Invited at", "Opened at", *@items.map { |i| "Attending: #{i.name}" }, *@questions.map(&:prompt), "Note from guest", "Host notes",
        "Checked in", "Source", *([ "Paid", "Amount due" ] if @event.ticketed?) ]
    end

    def row(guest)
      answers = guest.rsvp_answers.index_by(&:event_question_id)
      item_replies = guest.schedule_replies.index_by(&:schedule_item_id)
      [
        guest.name, guest.email, guest.phone, guest.group_name, guest.plus_ones_allowed,
        RsvpHelper::STATUS_LABELS.fetch(guest.rsvp_status), guest.party_size,
        *(@event.track_kids? ? [ guest.adults_count, guest.kids_count ] : []), guest.plus_one_names.join("; ").presence,
        time(guest.responded_at), time(guest.invited_at), time(guest.first_viewed_at),
        *@items.map { |i| (r = item_replies[i.id]) ? (r.attending ? "Yes" : "No") : nil },
        *@questions.map { |q| answers[q.id]&.value },
        guest.guest_note, guest.host_notes, guest.checked_in_count.positive? ? guest.checked_in_count : nil, guest.source,
        *(@event.ticketed? ? [ money(guest.amount_paid_cents), money(guest.amount_due_cents) ] : [])
      ]
    end

    def money(cents)
      format("%.2f", cents / 100.0)
    end

    def time(value)
      value && @event.local(value).strftime("%Y-%m-%d %H:%M")
    end
end
