module Assistant
  # The texting assistant's tools for Claude: thin, typed wrappers around Assistant::Actions.
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
      doc "A one-time link that signs the host into the web app on that page (to fine-tune the design, see the guest list, preview...)."
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

    ALL = [ CreateAccount, ListEvents, SwitchEvent, CreateEvent, UpdateEvent, SetDesign, AddGuests, RemoveGuest,
            AddQuestion, AddLink, Status, Publish, SendInvitations, WebLink, LogGift, SaveThankYou, SendThankYou ].freeze

    def self.build(actions)
      ALL.map { |tool| tool.new(actions) }
    end
  end
end
