module Assistant
  # Everything the Cordially agent can do for a host — over text (on behalf of the host whose phone
  # this is) or on the web. Both the Claude-powered agent (as tools) and the guided step-by-step one
  # call these, and they go through the same models and validations as the web app. Each returns a
  # short plain-text result; some also add a card (an event, an import preview, a proposal) that the
  # web shows alongside the reply.
  class Actions
    include Rails.application.routes.url_helpers

    AFFIRMATIVE = /\b(send|yes|yep|yeah|yup|go ahead|do it|confirm(ed)?|ok|okay|sure|please do)\b/i
    MAX_GUESTS_PER_CALL = 200
    LOCAL_PREFIXES = %w[44 61 91 55 52 33 49 34 39 353 64 27 81 82].freeze # country codes where local numbers start with 0

    PREFERENCE_FIELDS = %i[default_host_name time_zone phone_country_code default_allow_maybe default_track_kids default_plus_ones
                           default_auto_nudge default_auto_day_before agent_reach rsvp_notifications].freeze

    attr_reader :conversation, :inbound, :cards

    def initialize(conversation, inbound: nil)
      @conversation = conversation
      @inbound = inbound
      @cards = []
    end

    def card!(type, **data)
      card = { "type" => type }.merge(data.stringify_keys)
      @cards << card unless @cards.include?(card)
    end

    def user = conversation.user

    def event
      return unless user && conversation.event

      user.accessible_events.find_by(id: conversation.event_id)
    end

    # --- Account ---------------------------------------------------------------

    def create_account(name:, email:)
      raise Error, "This phone is already connected to #{user.email_address}." if user

      email = email.to_s.strip.downcase
      if (existing = User.find_by(email_address: email))
        token = Rails.application.message_verifier(:assistant_link).generate(
          { "conversation_id" => conversation.id, "user_id" => existing.id }, expires_in: 1.hour)
        AssistantMailer.with(user: existing, url: assistant_link_url(token, **link_options)).link_phone.deliver_later
        conversation.store!(pending_email: email)
        return "That email already has a Cordially account, so I emailed #{email} a link. Tap it to connect this phone."
      end

      new_user = User.new(name: name, email_address: email, password: SecureRandom.base58(24))
      raise Error, new_user.errors.full_messages.to_sentence unless new_user.save

      conversation.update!(user: new_user)
      "Account created for #{new_user.name} (#{new_user.email_address}). They can sign in on the web any time with a link from you, or reset the password from that email."
    end

    # --- Events ----------------------------------------------------------------

    def list_events
      require_user!
      events = user.accessible_events.order(Arel.sql("starts_at IS NULL, starts_at DESC")).limit(10)
      return "No events yet." if events.empty?

      events.map { |e| "#{e.id}: #{e.title} (#{e.status}#{", #{event_date(e)}" if e.starts_at})#{' ← current' if e.id == conversation.event_id}" }.join("\n")
    end

    def switch_event(event_id:)
      require_user!
      found = user.accessible_events.find_by(id: event_id)
      raise Error, "No event with id #{event_id}. Use list_events." unless found

      conversation.update!(event: found)
      "Now working on: #{summary(found)}"
    end

    EVENT_FIELDS = %i[title host_name description starts_at ends_at time_zone location_name address video_url rsvp_deadline
                      card_type capacity default_plus_ones track_kids ask_plus_one_names allow_maybe].freeze

    def create_event(title:, **attrs)
      require_user!
      new_event = user.owned_events.new(user.event_defaults.merge(title: title, time_zone: attrs[:time_zone].presence || default_time_zone))
      assign_event(new_event, attrs.except(:time_zone))
      new_event.design = { "tagline" => "Save the date" } if new_event.save_the_date?
      raise Error, new_event.errors.full_messages.to_sentence unless new_event.save

      Activity.record(event: new_event, user: user, action: "event_created")
      conversation.update!(event: new_event)
      conversation.store!(time_zone: new_event.time_zone)
      card!("event", event_id: new_event.id)
      "Created a draft: #{summary(new_event)}"
    end

    def update_event(**attrs)
      current = require_event!(:edit)
      assign_event(current, attrs)
      raise Error, current.errors.full_messages.to_sentence unless current.save

      current.touch_calendar! if current.published? && current.calendar_details_changed?
      card!("event", event_id: current.id)
      "Updated: #{summary(current)}"
    end

    def set_design(**attrs)
      current = require_event!(:edit)
      params = attrs.compact.transform_keys(&:to_s)
      if (name = params.delete("palette"))
        palette = DesignsHelper::PALETTES.find { |p| p[:name].casecmp?(name) } || raise(Error, "Unknown palette #{name}.")
        params.merge!("background_color" => palette[:bg], "text_color" => palette[:ink], "accent_color" => palette[:accent])
      end
      design = InvitationDesign.from_params(current, params)
      raise Error, design.errors.full_messages.to_sentence unless design.valid?

      current.update!(design: design.to_storage)
      card!("event", event_id: current.id)
      template = design.template_record
      "Design set: #{template.name}#{" with #{design.accent_color} accent" if params.key?('accent_color')}#{", envelope #{design.envelope}" if params.key?('envelope')}."
    end

    def add_guests(guests:)
      current = require_event!(:manage_guests)
      raise Error, "That's a lot at once — send up to #{MAX_GUESTS_PER_CALL} at a time." if guests.size > MAX_GUESTS_PER_CALL

      added, problems = [], []
      emails = current.guests.where.not(email: nil).pluck(:email).to_set
      phones = current.guests.where.not(phone: nil).pluck(:phone).to_set
      guests.each do |person|
        person = person.to_h.symbolize_keys
        guest = current.guests.new(name: person[:name], email: person[:email].presence, phone: with_country_code(person[:phone]),
          group_name: person[:group].presence, plus_ones_allowed: person[:plus_ones] || current.default_plus_ones, source: "manual")
        if (guest.email && emails.include?(guest.email)) || (guest.phone && phones.include?(guest.phone))
          problems << "#{guest.name} is already on the list"
        elsif guest.save
          added << guest.name
          emails << guest.email if guest.email
          phones << guest.phone if guest.phone
          Contact.remember!(user, name: guest.name, email: guest.email, phone: guest.phone, household: guest.group_name)
        else
          problems << "#{person[:name].presence || 'someone'}: #{guest.errors.full_messages.to_sentence}"
        end
      end
      Activity.record(event: current, user: user, action: "guests_imported", data: { created: added.size }) if added.any?
      [ "Added #{added.size} (#{current.guests.count} on the list now).", (problems.any? ? "Skipped: #{problems.join('; ')}." : nil) ].compact.join(" ")
    end

    def remove_guest(name:)
      current = require_event!(:manage_guests)
      guest = find_guest!(current, name)
      guest.destroy!
      "Removed #{guest.name}."
    end

    def add_question(prompt:, kind: "short_text", options: [])
      current = require_event!(:edit)
      question = current.questions.new(prompt: prompt, kind: kind, options_text: Array(options).join("\n"))
      raise Error, question.errors.full_messages.to_sentence unless question.save

      "Added question: #{question.prompt}"
    end

    def add_link(url:, label: nil)
      current = require_event!(:edit)
      link = current.links.new(url: url, label: label)
      raise Error, link.errors.full_messages.to_sentence unless link.save

      "Added to the back of the card: #{link.button_text}."
    end

    def status
      current = require_event!(:view)
      card!("event", event_id: current.id)
      s = current.rsvp_summary
      [ summary(current),
        "Guests: #{s[:invited]} (#{s[:sent]} sent, #{s[:viewed]} opened). Replies: #{s[:yes]} yes, #{s[:maybe]} maybe, #{s[:no]} no, #{s[:pending]} waiting. Headcount: #{s[:attending]}.",
        ("Reachable by text: #{current.guests.where.not(phone: nil).count}, by email only: #{current.guests.where(phone: nil).where.not(email: nil).count}, no contact: #{current.guests.where(phone: nil, email: nil).count}." if s[:invited].positive?) ].compact.join("\n")
    end

    def publish!
      current = require_event!(:publish)
      return "Already published." unless current.draft?
      raise Error, "Before publishing: #{current.errors.full_messages.to_sentence}" unless current.publish

      Activity.record(event: current, user: user, action: "event_published")
      "Published. Share link: #{public_event_url(current.share_token, **link_options)}"
    end

    # Sends the card to everyone not yet sent it: by text (or WhatsApp, matching this thread) to
    # guests with a mobile number, by email to the rest. Needs the host's go-ahead in their latest text.
    def send_invitations!
      current = require_event!(:send_messages)
      require_confirmation!("send the #{current.card_type_name.downcase.pluralize}")
      publish! if current.draft?
      current.reload

      text_channel = conversation.channel == "whatsapp" && Messaging.whatsapp_enabled? ? "whatsapp" : ("sms" if Messaging.sms_enabled?)
      with_phone = text_channel ? current.guests.where.not(phone: nil).ids : []
      rest = current.guests.where.not(id: with_phone).ids
      total = 0
      { text_channel => with_phone, "email" => rest }.each do |channel, ids|
        next if channel.nil? || ids.empty?

        message = current.messages.idempotent_create!(idempotency_key: "assistant-#{inbound&.id || SecureRandom.hex(6)}-#{channel}",
          kind: current.card_type, author: user, channels: [ channel ], audience: { "guest_ids" => ids })
        message.dispatch! unless message.status == "dispatched"
        total += message.recipients_count
      end
      skipped = current.guests.where(phone: nil, email: nil).count
      card!("event", event_id: current.id)
      "Sending #{total} #{current.card_type_name.downcase.pluralize(total)}.#{" #{skipped} guest(s) have no phone or email — share their link from the guest list." if skipped.positive?}"
    end

    # --- Bringing people over (Paperless Post exports, contacts files, pasted lists) -------------

    # Reads the spreadsheet or contacts file attached to the host's latest message — or a pasted
    # list — into a preview. Nothing is saved until apply_guest_list.
    def read_guest_list(text: nil)
      require_user!
      file = inbound&.import_files&.first
      import = if file
        data, = Media.fetch(file["url"], content_type: file["content_type"], max_bytes: Imports::Reader::MAX_BYTES)
        ContactImport.read!(user, data, filename: file["filename"])
      elsif text.present?
        ContactImport.read!(user, text)
      else
        raise Error, "There's no file on the latest message. Ask them to attach the spreadsheet or contacts file, or paste the list."
      end
      card!("import", import_id: import.id)
      skipped = import.people.skipped_columns
      [ "Import #{import.id} is ready to review (nothing saved yet). #{import.description}",
        "Suggested event name: #{import.suggested_title}.",
        ("Columns not used: #{skipped.first(8).join(', ')}." if skipped.any?) ].compact.join(" ")
    rescue Imports::Reader::Unreadable => e
      raise Error, e.message
    end

    # mode: contacts (address book only), new_event (recreate the event as a draft, replies and
    # all), or current_event (add them to the event this conversation is working on).
    def apply_guest_list(import_id:, mode: "contacts", title: nil)
      require_user!
      import = user.contact_imports.pending.find_by(id: import_id) || raise(Error, "Import #{import_id} isn't waiting any more — read the file again.")
      target = mode.to_s == "current_event" ? require_event!(:manage_guests) : nil
      summary = import.apply!(mode: target ? "event" : mode.to_s.presence_in(%w[contacts new_event]) || "contacts", event: target, title: title)
      if import.event
        conversation.update!(event: import.event)
        card!("event", event_id: import.event.id)
      end
      parts = [ "#{summary['contacts_added'].to_i} new in contacts", ("#{summary['contacts_updated']} updated" if summary["contacts_updated"].to_i.positive?),
                ("#{summary['guests_added']} on the guest list of #{import.event.title}" if import.event),
                ("#{summary['replies_kept']} replies kept" if summary["replies_kept"].to_i.positive?) ].compact
      "Brought in #{summary['people']} #{'person'.pluralize(summary['people'].to_i)}: #{parts.join(', ')}. Nobody was contacted."
    end

    # --- Contacts --------------------------------------------------------------

    def find_contacts(query: nil, group: nil)
      require_user!
      scope = user.contacts.alphabetical
      scope = scope.where("LOWER(contacts.household) = ?", group.to_s.downcase.squish) if group.present?
      scope = scope.search(query) if query.present?
      found = scope.limit(25).to_a
      groups = user.contacts.where.not(household: nil).group(:household).order(Arel.sql("COUNT(*) DESC")).limit(15).count
      lines = found.map { |c| "#{c.id}: #{c.name}#{" (#{c.household})" if c.household}#{' · email' if c.email}#{' · mobile' if c.phone}" }
      lines.unshift(found.empty? ? "No matching contacts." : "#{scope.count} matching#{' (first 25)' if scope.count > 25}:")
      lines << "Groups: #{groups.map { |name, n| "#{name} (#{n})" }.join(', ')}" if groups.any?
      lines << "Contacts in total: #{user.contacts.count}."
      lines.join("\n")
    end

    # Puts people from the host's contacts on the current event's guest list.
    def invite_contacts(contact_ids: [], group: nil)
      current = require_event!(:manage_guests)
      people = user.contacts.where(id: Array(contact_ids)).to_a
      people |= user.contacts.where("LOWER(contacts.household) = ?", group.to_s.downcase.squish).to_a if group.present?
      raise Error, "No matching contacts — use find_contacts." if people.empty?

      added, already = [], []
      emails = current.guests.where.not(email: nil).pluck(:email).to_set
      phones = current.guests.where.not(phone: nil).pluck(:phone).to_set
      people.each do |contact|
        if (contact.email && emails.include?(contact.email)) || (contact.phone && phones.include?(contact.phone))
          already << contact.name
        elsif current.guests.create(contact.guest_attributes.merge(source: "manual", plus_ones_allowed: current.default_plus_ones)).persisted?
          added << contact.name
          emails << contact.email if contact.email
          phones << contact.phone if contact.phone
        end
      end
      Activity.record(event: current, user: user, action: "guests_imported", data: { created: added.size }) if added.any?
      card!("event", event_id: current.id)
      "Added #{added.size} to #{current.title}#{": #{added.first(8).to_sentence}" if added.any?}#{" (#{already.size} already on the list)" if already.any?}. Not sent yet."
    end

    # --- The host's usual settings -------------------------------------------------

    def update_preferences(**prefs)
      require_user!
      raise Error, user.errors.full_messages.to_sentence unless user.update(prefs.slice(*PREFERENCE_FIELDS))

      "Saved. #{preferences_summary}"
    end

    def preferences_summary
      return "" unless user

      d = user.event_defaults
      [ "New events: hosted by #{d[:host_name]}", "time zone #{d[:time_zone]}", ("adults and kids counted separately" if d[:track_kids]),
        (d[:allow_maybe] ? "Maybe allowed" : "no Maybe"), ("#{d[:default_plus_ones]} extra guests each" if d[:default_plus_ones].positive?),
        ("auto-nudge non-responders" if d[:auto_nudge]), ("day-before reminder" if d[:auto_day_before]),
        "reach the host by #{user.agent_reach}" ].compact.join(", ") + "."
    end

    # --- Things that need the host ---------------------------------------------------

    def list_proposals
      require_user!
      pending = user.agent_proposals.pending.recent_first.limit(10).to_a
      return "Nothing needs the host right now." if pending.empty?

      pending.map { |p| "#{p.id}: #{p.pitch}#{p.actionable? ? " [approve to: #{p.action_label.downcase}]" : ''}" }.join("\n")
    end

    def approve_proposal(proposal_id:)
      require_user!
      proposal = user.agent_proposals.pending.find_by(id: proposal_id) || raise(Error, "That one isn't waiting any more.")
      require_confirmation!(proposal.action_label.to_s.downcase.presence || "go ahead") if proposal.actionable?
      outcome = proposal.approve!(by: user)
      card!("proposal", proposal_id: proposal.id)
      outcome
    end

    def dismiss_proposal(proposal_id:)
      require_user!
      proposal = user.agent_proposals.pending.find_by(id: proposal_id) || raise(Error, "That one isn't waiting any more.")
      proposal.dismiss!
      card!("proposal", proposal_id: proposal.id)
      "Okay, I'll leave that."
    end

    # On the web: offer to connect the host's phone so the agent can text them (the code is shown
    # by the page, never put in the conversation).
    def connect_phone
      require_user!
      return "This phone is already connected to #{user.name}'s account." unless conversation.web?
      raise Error, "Texting isn't set up on this Cordially yet." unless Assistant.texting_number

      card!("connect_phone")
      "Tap “Connect my phone” and text the code it shows to #{Assistant.texting_number}. From then on I'll text you when something needs you, and you can text me anything."
    end

    # A link that signs the host into the web app at the right page (single use, 30 minutes).
    def web_link(page: "design")
      require_user!
      current = event
      path = case page
      when "design" then current ? edit_event_design_path(current) : new_event_path
      when "guests" then current ? event_guests_path(current) : events_path
      when "preview" then current ? preview_event_path(current) : events_path
      when "thank_yous" then current ? event_thank_yous_path(current) : events_path
      else current ? event_path(current) : events_path
      end
      if conversation.web?
        card!("link", url: path, label: { "design" => "Open the design studio", "guests" => "Open the guest list", "preview" => "Preview the card",
          "thank_yous" => "Open thank-yous" }.fetch(page, current ? "Open #{current.title}" : "Open your events"))
        return "Linked below: #{path}"
      end
      "#{sign_in_link_url(SignInLink.issue!(user, path), **link_options)} (works once, for 30 minutes)"
    end

    # --- Thank-yous ------------------------------------------------------------

    def log_gift(giver:, description:)
      current = require_event!(:manage_guests)
      guest = match_guest(current, giver)
      gift = current.gifts.new(guest: guest, giver_name: guest ? nil : giver, description: description)
      raise Error, gift.errors.full_messages.to_sentence unless gift.save

      "Logged: #{gift.description} from #{gift.giver_name}#{' (on the guest list)' if guest}."
    end

    # Creates or updates the thank-you for a guest (and gift), attaching the photo/video from the
    # host's latest text if there is one.
    def save_thank_you(recipient:, gift: nil, message: nil, signed: nil)
      current = require_event!(:manage_guests)
      gift_record = gift.present? ? current.gifts.where("LOWER(description) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(gift.downcase)}%").first : nil
      guest = gift_record&.guest || match_guest(current, recipient)
      thank_you = gift_record&.thank_you || (guest && current.thank_yous.find_by(guest: guest, gift_id: gift_record&.id)) ||
        current.thank_yous.new(gift: gift_record, guest: guest, recipient_name: guest&.name || recipient)
      thank_you.message = message if message.present?
      thank_you.signed = signed if signed.present?
      attached = attach_inbound_media(thank_you)
      raise Error, thank_you.errors.full_messages.to_sentence unless thank_you.save

      reach = thank_you.recipient_phone || thank_you.recipient_email || "no phone or email on file"
      "Saved the thank-you for #{thank_you.recipient_name}#{" (#{attached})" if attached} — ready to send to #{reach}."
    end

    def send_thank_you!(recipient:)
      current = require_event!(:send_messages)
      require_confirmation!("send the thank-you")
      thank_you = current.thank_yous.where(sent_at: nil).detect { |t| t.recipient_name.downcase.include?(recipient.to_s.downcase) } ||
        raise(Error, "No unsent thank-you for #{recipient}.")
      channel = ThankYouSender.channel_for(thank_you) || raise(Error, "#{thank_you.recipient_name} has no phone or email on file.")
      ThankYouSender.new(thank_you, channel: channel).deliver!
      "Sent #{thank_you.recipient_name}'s thank-you by #{channel == 'sms' ? 'text' : 'email'}."
    rescue ThankYouSender::Unavailable => e
      raise Error, e.message
    end

    def summary(e = event)
      return "No event selected." unless e

      design = InvitationDesign.for(e)
      parts = [ "\"#{e.title}\" (#{e.card_type_name.downcase}, #{e.status})" ]
      parts << event_date(e) if e.starts_at
      parts << [ e.location_name, e.address ].compact_blank.join(", ") if e.location_name.present? || e.address.present?
      parts << "design #{design.template_record.name}"
      parts << "#{e.guests.count} guests"
      parts.join(" · ")
    end

    private
      def link_options = Messaging.url_options

      def require_user!
        raise Error, "No account yet — ask for their name and email, then create_account." unless user
      end

      def require_event!(permission)
        require_user!
        current = event || raise(Error, "No event selected — create_event or switch_event first.")
        raise Error, "You don't have permission to do that for this event." unless EventPolicy.new(user, current).can?(permission)

        current
      end

      def require_confirmation!(what)
        return if inbound&.body.to_s.match?(AFFIRMATIVE)

        raise Error, "Not confirmed. Ask the host to reply SEND (or yes) to #{what}, then try again."
      end

      # Numbers texted without a country code are taken to be in the host's own country.
      def with_country_code(phone)
        return if phone.blank?

        PhoneNumber.with_country(phone, country_code) || phone
      end

      def country_code
        return "1" if conversation.address.to_s.start_with?("+1")

        LOCAL_PREFIXES.find { |c| conversation.address.to_s.start_with?("+#{c}") } || user&.effective_phone_country_code
      end

      def default_time_zone
        conversation.data_value(:time_zone).presence || user&.time_zone.presence || "America/New_York"
      end

      def assign_event(record, attrs)
        attrs = attrs.to_h.symbolize_keys.slice(*EVENT_FIELDS).compact
        %i[starts_at ends_at rsvp_deadline].each do |field|
          next unless attrs.key?(field)

          record.public_send(:"#{field}_local=", attrs.delete(field).to_s.strip.first(16))
        end
        record.assign_attributes(attrs)
      end

      def event_date(e)
        local = e.local(e.starts_at)
        "#{local.strftime('%a %b %-d, %Y')} at #{local.min.zero? ? local.strftime('%-l %p') : local.strftime('%-l:%M %p')} #{local.strftime('%Z')}"
      end

      def match_guest(scope_event, name)
        return if name.blank?

        matches = scope_event.guests.where("LOWER(name) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(name.to_s.downcase.strip)}%").limit(5).to_a
        matches.size == 1 ? matches.first : matches.find { |g| g.name.casecmp?(name.to_s.strip) }
      end

      def find_guest!(scope_event, name)
        match_guest(scope_event, name) || raise(Error, "Couldn't find exactly one guest named #{name}.")
      end

      def attach_inbound_media(thank_you)
        item = inbound&.media&.find { |m| m["content_type"].to_s.start_with?("image/", "video/") }
        return unless item

        data, type = Assistant::Media.fetch(item["url"], content_type: item["content_type"])
        thank_you.media.attach(io: StringIO.new(data), filename: "thank-you.#{Rack::Mime::MIME_TYPES.invert[type]&.delete('.') || 'bin'}", content_type: type)
        type.start_with?("video/") ? "video attached" : "photo attached"
      end
  end
end
