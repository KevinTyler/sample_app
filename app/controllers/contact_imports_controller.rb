# Bring contacts in from a spreadsheet (CSV) or a phone/Google/Outlook export (vCard .vcf).
# People already in the book (same email) get missing details filled in; nothing is overwritten.
class ContactImportsController < ApplicationController
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { Current.user.id },
    with: -> { redirect_to contacts_path, alert: "Too many imports in a short time. Please wait a bit." }

  def new
  end

  def create
    text = params[:file].respond_to?(:read) ? params[:file].read(ContactList::MAX_BYTES + 1) : params[:pasted].to_s
    list = ContactList.new(text)
    people = list.people
    return redirect_to(new_contact_import_path, alert: list.error || "We couldn't find anyone in that file.") if people.empty?

    added = updated = skipped = 0
    existing = Current.user.contacts.where.not(email: nil).index_by(&:email)
    Contact.transaction do
      people.each do |person|
        email = person[:email].to_s.strip.downcase.presence
        if email && (contact = existing[email])
          missing = person.slice(:phone, :household, :notes).select { |key, value| value.present? && contact[key].blank? }
          missing.any? && contact.update(missing) ? updated += 1 : skipped += 1
        elsif (contact = Current.user.contacts.new(person)).save
          existing[contact.email] = contact if contact.email
          added += 1
        else
          skipped += 1
        end
      end
    end
    redirect_to contacts_path, notice: "Contacts imported: #{added} added, #{updated} updated, #{skipped} skipped."
  end
end
