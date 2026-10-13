# Bring people in from anywhere — a Paperless Post guest-list spreadsheet, Google/Outlook/phone
# contacts, any spreadsheet, or a pasted list. Upload → preview (fix what columns mean, choose where
# people go) → apply. Nothing is sent to anyone.
class ContactImportsController < ApplicationController
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { Current.user.id },
    with: -> { redirect_to new_contact_import_path, alert: "Too many imports in a short time. Please wait a bit." }

  before_action :set_import, only: %i[show update apply destroy]

  def new
  end

  def create
    file = params[:file]
    data = file.respond_to?(:read) ? file.read(Imports::Reader::MAX_BYTES + 1) : params[:pasted].to_s
    @import = ContactImport.read!(Current.user, data, filename: (file.original_filename if file.respond_to?(:original_filename)))
    redirect_to contact_import_path(@import, from: params[:from].presence_in(%w[switch]))
  rescue Imports::Reader::Unreadable => e
    redirect_to (params[:from] == "switch" ? switch_path : new_contact_import_path), alert: e.message
  end

  def show
    return redirect_to(contacts_path, notice: "That import is already done.") unless @import.pending?

    @events = Current.user.accessible_events.where.not(status: "cancelled").order(created_at: :desc).select { |e| EventPolicy.new(Current.user, e).can?(:manage_guests) }
  end

  # The host changed what a column means.
  def update
    columns = (0...Imports::Reader::MAX_COLUMNS).map(&:to_s)
    @import.remap!(params.fetch(:mapping, {}).permit(*columns).to_h.transform_values { |field| field.presence_in(Imports::People::FIELDS.keys) })
    redirect_to contact_import_path(@import, from: params[:from].presence_in(%w[switch]))
  end

  def apply
    return redirect_to(contacts_path, notice: "That import is already done.") unless @import.pending?

    mode = params[:mode].presence_in(ContactImport::MODES) || "contacts"
    event = nil
    if mode == "event"
      event = Current.user.accessible_events.find_by(id: params[:event_id])
      return redirect_to(contact_import_path(@import), alert: "Choose an event to add them to.") unless event && EventPolicy.new(Current.user, event).can?(:manage_guests)
    end
    Current.user.update!(switched_from: "paperless_post") if params[:from] == "switch" && Current.user.switched_from.blank?

    summary = @import.apply!(mode: mode, event: event, title: params[:title])
    notice = import_notice(summary)
    if params[:from] == "agent"
      tell_agent(notice)
      redirect_to agent_path(anchor: "latest"), status: :see_other
    elsif @import.event
      redirect_to event_path(@import.event), notice: notice
    else
      redirect_to (params[:from] == "switch" ? switch_path : contacts_path), notice: notice
    end
  end

  def destroy
    @import.discard!
    redirect_to (params[:from] == "switch" ? switch_path : new_contact_import_path), notice: "Import discarded — nothing was saved."
  end

  private
    def set_import
      @import = Current.user.contact_imports.find(params[:id])
    end

    # The host applied an import from a card in the conversation: the agent reports back there.
    def tell_agent(notice)
      conversation = AssistantConversation.for_web(Current.user)
      cards = [ { "type" => "import", "import_id" => @import.id } ]
      text = notice
      if @import.event
        conversation.update!(event: @import.event)
        cards << { "type" => "event", "event_id" => @import.event.id }
        text += " #{@import.event.title} is a draft — when is it, and where? Or paste the wording from your old invitation and I'll fill in the details."
      end
      conversation.reply!(text, cards: cards)
    end

    def import_notice(summary)
      parts = [ "#{summary['contacts_added'].to_i} added to contacts" ]
      parts << "#{summary['contacts_updated']} updated" if summary["contacts_updated"].to_i.positive?
      parts << "#{summary['guests_added']} on the guest list" if summary["guests_added"].to_i.positive?
      parts << "#{summary['replies_kept']} replies kept" if summary["replies_kept"].to_i.positive?
      skipped = summary["contacts_skipped"].to_i + summary["guests_skipped"].to_i
      parts << "#{skipped} skipped" if skipped.positive?
      "Brought in #{summary['people']} #{'person'.pluralize(summary['people'].to_i)}: #{parts.join(', ')}."
    end
end
