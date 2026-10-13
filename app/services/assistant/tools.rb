module Assistant
  # The Cordially agent's tools for Claude: thin, typed wrappers around Assistant::Actions.
  # Input schemas are declared with the Anthropic SDK's input-schema models; the SDK's tool runner
  # validates each call against them. Errors raised here go back to Claude as tool errors.
  module Tools
    TEMPLATE_KEYS = InvitationTemplate.all.map { |t| t.key.to_sym }.freeze
    PALETTE_NAMES = DesignsHelper::PALETTES.map { |p| p[:name].to_sym }.freeze

    class Base < Anthropic::BaseTool
      def initialize(actions)
        super()
        @actions = actions
      end

      private
        attr_reader :actions

        def args(input)
          input.to_h.compact.transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
        end
    end

    class EmptyInput < Anthropic::BaseModel; end

    class CreateAccountInput < Anthropic::BaseModel
      required :name, String, doc: "The host's full name"
      required :email, String, doc: "The host's email address (for their account and reply notifications)"
    end

    class CreateAccount < Base
      doc "Create a Cordially account for the person texting, linked to this phone. Use once, after asking their name and email."
      input_schema CreateAccountInput
      def call(input) = actions.create_account(name: input.name, email: input.email)
    end

    class ListEvents < Base
      doc "List the host's events (id, title, status, date). The current one is marked."
      input_schema EmptyInput
      def call(_input) = actions.list_events
    end

    class SwitchEventInput < Anthropic::BaseModel
      required :event_id, Integer
    end

    class SwitchEvent < Base
      doc "Make another of the host's events the one this conversation works on."
      input_schema SwitchEventInput
      def call(input) = actions.switch_event(event_id: input.event_id)
    end

    class EventFields < Anthropic::BaseModel
      optional :title, String, doc: "Event name as guests will see it, e.g. \"Jonah's 5th Birthday\""
      optional :host_name, String, doc: "Hosted by (as shown to guests)"
      optional :description, String, doc: "Details for guests: dress code, parking, what to bring"
      optional :starts_at, String, doc: "Local start time at the event, format YYYY-MM-DDTHH:MM"
      optional :ends_at, String, doc: "Local end time, format YYYY-MM-DDTHH:MM"
      optional :time_zone, String, doc: "IANA time zone of the event, e.g. America/Chicago"
      optional :location_name, String, doc: "Venue name"
      optional :address, String, doc: "Street address"
      optional :video_url, String, doc: "Video call link for online events"
      optional :rsvp_deadline, String, doc: "Local reply deadline, format YYYY-MM-DDTHH:MM"
      optional :card_type, Anthropic::EnumOf[:invitation, :save_the_date, :announcement]
      optional :capacity, Integer
      optional :default_plus_ones, Integer, doc: "Extra people each guest may bring"
      optional :track_kids, Anthropic::Boolean, doc: "Ask guests for adults and kids separately"
      optional :ask_plus_one_names, Anthropic::Boolean
      optional :allow_maybe, Anthropic::Boolean
    end

    class CreateEventInput < EventFields
      required :title, String, doc: "Event name as guests will see it"
    end

    class CreateEvent < Base
      doc "Create a new draft event (invitation, save-the-date or announcement) and make it the current one."
      input_schema CreateEventInput
      def call(input)
        fields = args(input)
        actions.create_event(title: fields.delete(:title), **fields)
      end
    end

    class UpdateEvent < Base
      doc "Change details of the current event. Only pass fields that change."
      input_schema EventFields
      def call(input) = actions.update_event(**args(input))
    end

    class SetDesignInput < Anthropic::BaseModel
      optional :template, Anthropic::EnumOf[*TEMPLATE_KEYS], doc: "Design template key"
      optional :headline, String, doc: "Line above the title, e.g. \"Let's celebrate!\""
      optional :tagline, String, doc: "Small capitals line at the top, e.g. \"You're invited\""
      optional :message, String, doc: "Short message on the card"
      optional :palette, Anthropic::EnumOf[*PALETTE_NAMES], doc: "A ready-made color palette"
      optional :background_color, String, doc: "Hex like #FFF8F0"
      optional :text_color, String, doc: "Hex like #2D2A4A"
      optional :accent_color, String, doc: "Hex like #FF6B6B"
      optional :layout, Anthropic::EnumOf[*InvitationDesign::LAYOUTS.keys.map(&:to_sym)]
      optional :envelope, Anthropic::EnumOf[*InvitationDesign::ENVELOPES.keys.map(&:to_sym)]
      optional :liner, Anthropic::EnumOf[*InvitationDesign::LINERS.keys.map(&:to_sym)]
      optional :stamp, Anthropic::EnumOf[*InvitationDesign::STAMPS.keys.map(&:to_sym)]
      optional :backdrop, Anthropic::EnumOf[*InvitationDesign::BACKDROPS.keys.map(&:to_sym)]
    end

    class SetDesign < Base
      doc "Change the current event's card design. Switching template resets colors and wording to that template's unless also given."
      input_schema SetDesignInput
      def call(input) = actions.set_design(**args(input))
    end

    class GuestInput < Anthropic::BaseModel
      required :name, String
      optional :phone, String, doc: "Mobile number, ideally with country code"
      optional :email, String
      optional :group, String, doc: "Household or group, e.g. Family"
      optional :plus_ones, Integer
    end

    class AddGuestsInput < Anthropic::BaseModel
      required :guests, Anthropic::ArrayOf[GuestInput]
    end

    class AddGuests < Base
      doc "Add people to the current event's guest list (also saved to the host's contacts). Skips duplicates."
      input_schema AddGuestsInput
      def call(input) = actions.add_guests(guests: input.guests.map { |g| args(g) })
    end

    class NameInput < Anthropic::BaseModel
      required :name, String
    end

    class RemoveGuest < Base
      doc "Remove a guest (and their reply) from the current event."
      input_schema NameInput
      def call(input) = actions.remove_guest(name: input.name)
    end

    class AddQuestionInput < Anthropic::BaseModel
      required :prompt, String, doc: "e.g. \"Dinner choice?\""
      required :kind, Anthropic::EnumOf[:short_text, :long_text, :choice]
      optional :options, Anthropic::ArrayOf[String], doc: "Choices, for kind=choice"
    end

    class AddQuestion < Base
      doc "Add a question to the reply form (meal choice, allergies, song request...)."
      input_schema AddQuestionInput
      def call(input) = actions.add_question(prompt: input.prompt, kind: input.kind.to_s, options: Array(input.options))
    end

    class AddLinkInput < Anthropic::BaseModel
      required :url, String, doc: "A full https:// address (OpenTable/Resy/Tock reservation, registry, playlist, photo album...)"
      optional :label, String, doc: "Button text, if the default isn't right"
    end

    class AddLink < Base
      doc "Add a link button to the back of the card."
      input_schema AddLinkInput
      def call(input) = actions.add_link(url: input.url, label: input.label)
    end

    class Status < Base
      doc "Current event summary: details, guest count, who has been sent the card, replies and headcount."
      input_schema EmptyInput
      def call(_input) = actions.status
    end

    class Publish < Base
      doc "Publish the current event so guest links work. Doesn't send anything."
      input_schema EmptyInput
      def call(_input) = actions.publish!
    end

    class SendInvitations < Base
      doc "Send the card to every guest not yet sent it (text/WhatsApp to mobiles, email otherwise). " \
          "Only call after the host has explicitly said to send in their latest message; otherwise it fails."
      input_schema EmptyInput
      def call(_input) = actions.send_invitations!
    end

    class WebLinkInput < Anthropic::BaseModel
      required :page, Anthropic::EnumOf[:design, :guests, :preview, :thank_yous, :overview]
    end

    class WebLink < Base
      doc "A link to that page of the web app (to fine-tune the design, see the guest list, preview...). By text it's a one-time sign-in link; on the web it shows as a button."
      input_schema WebLinkInput
      def call(input) = actions.web_link(page: input.page.to_s)
    end

    class LogGiftInput < Anthropic::BaseModel
      required :giver, String, doc: "Who gave it (a guest's name if possible)"
      required :description, String, doc: "What it was, e.g. \"Dinosaur Lego set\""
    end

    class LogGift < Base
      doc "Record a gift the host received for the current event."
      input_schema LogGiftInput
      def call(input) = actions.log_gift(giver: input.giver, description: input.description)
    end

    class SaveThankYouInput < Anthropic::BaseModel
      required :recipient, String, doc: "Who the thank-you is for"
      optional :gift, String, doc: "Which logged gift it's for (part of its description)"
      optional :message, String, doc: "The written note, in the host's or kid's words"
      optional :signed, String, doc: "Sign-off, e.g. \"Love, Jonah\""
    end

    class SaveThankYou < Base
      doc "Create or update a thank-you note. Automatically attaches the photo or video in the host's latest text, if any."
      input_schema SaveThankYouInput
      def call(input) = actions.save_thank_you(**args(input))
    end

    class SendThankYouInput < Anthropic::BaseModel
      required :recipient, String
    end

    class SendThankYou < Base
      doc "Send a saved thank-you. Only after the host has said to send it in their latest message."
      input_schema SendThankYouInput
      def call(input) = actions.send_thank_you!(recipient: input.recipient)
    end

    class ReadGuestListInput < Anthropic::BaseModel
      optional :text, String, doc: "A pasted list or spreadsheet cells, when there's no attached file"
    end

    class ReadGuestList < Base
      doc "Read the guest list or contacts file attached to the host's latest message (a Paperless Post export spreadsheet, " \
          "Excel/CSV, vCard from a phone, Google or Outlook) — or a pasted list — into a preview: who's in it, which columns " \
          "mean what, groups, mailing addresses and any replies already given. Saves nothing."
      input_schema ReadGuestListInput
      def call(input) = actions.read_guest_list(text: input.text)
    end

    class ApplyGuestListInput < Anthropic::BaseModel
      required :import_id, Integer
      required :mode, Anthropic::EnumOf[:contacts, :new_event, :current_event],
        doc: "contacts: address book only; new_event: recreate the event as a draft with everyone and their replies; current_event: add them to the current event"
      optional :title, String, doc: "Event name, for new_event"
    end

    class ApplyGuestList < Base
      doc "Bring in a previewed import once the host has said where people should go. Everyone is also saved to contacts. Contacts nobody."
      input_schema ApplyGuestListInput
      def call(input) = actions.apply_guest_list(import_id: input.import_id, mode: input.mode.to_s, title: input.title)
    end

    class FindContactsInput < Anthropic::BaseModel
      optional :query, String, doc: "Name, email or phone to search for"
      optional :group, String, doc: "Exact group / household name, e.g. Book club"
    end

    class FindContacts < Base
      doc "Search the host's contacts (by name/email/phone or group). Also lists their groups."
      input_schema FindContactsInput
      def call(input) = actions.find_contacts(query: input.query, group: input.group)
    end

    class InviteContactsInput < Anthropic::BaseModel
      optional :contact_ids, Anthropic::ArrayOf[Integer], doc: "From find_contacts"
      optional :group, String, doc: "Add everyone in this contacts group"
    end

    class InviteContacts < Base
      doc "Put people from the host's contacts on the current event's guest list (doesn't send anything)."
      input_schema InviteContactsInput
      def call(input) = actions.invite_contacts(contact_ids: Array(input.contact_ids), group: input.group)
    end

    class PreferencesInput < Anthropic::BaseModel
      optional :default_host_name, String, doc: "How \"Hosted by\" reads on new cards, e.g. The Reyes Family"
      optional :time_zone, String, doc: "IANA time zone, e.g. America/Chicago"
      optional :phone_country_code, String, doc: "Calling code for numbers given without one, e.g. 1 or 44"
      optional :default_allow_maybe, Anthropic::Boolean
      optional :default_track_kids, Anthropic::Boolean, doc: "Ask adults and kids separately"
      optional :default_plus_ones, Integer
      optional :default_auto_nudge, Anthropic::Boolean, doc: "Automatically nudge non-responders before the deadline"
      optional :default_auto_day_before, Anthropic::Boolean, doc: "Automatic day-before reminder to everyone coming"
      optional :agent_reach, Anthropic::EnumOf[:text, :email, :off], doc: "How you reach the host when something needs them"
      optional :rsvp_notifications, Anthropic::EnumOf[:instant, :daily, :off], doc: "Emails about each reply, a daily summary, or none"
    end

    class UpdatePreferences < Base
      doc "Save the host's usual settings — what every new event starts with, and how to reach them. Use when they tell you how they like things (or what they used on Paperless Post)."
      input_schema PreferencesInput
      def call(input) = actions.update_preferences(**args(input).symbolize_keys)
    end

    class ListProposals < Base
      doc "Things you've noticed that are waiting on the host's go-ahead (nudges, reminders, bounced invitations, thank-yous)."
      input_schema EmptyInput
      def call(_input) = actions.list_proposals
    end

    class ProposalInput < Anthropic::BaseModel
      required :proposal_id, Integer
    end

    class ApproveProposal < Base
      doc "Carry out a proposal. Only when the host's latest message clearly says yes to it; otherwise it fails."
      input_schema ProposalInput
      def call(input) = actions.approve_proposal(proposal_id: input.proposal_id)
    end

    class DismissProposal < Base
      doc "Drop a proposal the host said no to."
      input_schema ProposalInput
      def call(input) = actions.dismiss_proposal(proposal_id: input.proposal_id)
    end

    class ConnectPhone < Base
      doc "On the web: let the host connect their phone so you can text them (and they can text you)."
      input_schema EmptyInput
      def call(_input) = actions.connect_phone
    end

    ALL = [ CreateAccount, ListEvents, SwitchEvent, CreateEvent, UpdateEvent, SetDesign, AddGuests, RemoveGuest,
            AddQuestion, AddLink, Status, Publish, SendInvitations, WebLink, LogGift, SaveThankYou, SendThankYou,
            ReadGuestList, ApplyGuestList, FindContacts, InviteContacts, UpdatePreferences, ListProposals,
            ApproveProposal, DismissProposal, ConnectPhone ].freeze

    def self.build(actions)
      ALL.map { |tool| tool.new(actions) }
    end
  end
end
