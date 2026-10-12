require "csv"

# The host's guest-list spreadsheet: contact details, RSVP state, answers and check-in.
# Every cell goes through CsvSafety, since names, notes and answers are typed by guests.
class GuestListExport
  def initialize(event)
    @event = event
    @questions = event.questions.to_a
  end

  def to_csv
    CSV.generate do |csv|
      csv << header
      @event.guests.includes(:rsvp_answers).order(:name).each { |guest| csv << CsvSafety.row(row(guest)) }
    end
  end

  private
    def header
      [ "Name", "Email", "Phone", "Group", "Plus-ones allowed", "RSVP", "Party size", "Responded at",
        "Invited at", "Opened at", *@questions.map(&:prompt), "Note from guest", "Host notes",
        "Checked in", "Source" ]
    end

    def row(guest)
      answers = guest.rsvp_answers.index_by(&:event_question_id)
      [
        guest.name, guest.email, guest.phone, guest.group_name, guest.plus_ones_allowed,
        RsvpHelper::STATUS_LABELS.fetch(guest.rsvp_status), guest.party_size,
        time(guest.responded_at), time(guest.invited_at), time(guest.first_viewed_at),
        *@questions.map { |q| answers[q.id]&.value },
        guest.guest_note, guest.host_notes, guest.checked_in_count.positive? ? guest.checked_in_count : nil, guest.source
      ]
    end

    def time(value)
      value && @event.local(value).strftime("%Y-%m-%d %H:%M")
    end
end
