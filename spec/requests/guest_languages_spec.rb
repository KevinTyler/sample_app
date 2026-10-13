require "rails_helper"

RSpec.describe "Guest pages in other languages", type: :request do
  let(:event) { create(:event, :published, title: "Fiesta de Ana", locale: "es", allow_maybe: false) }
  let(:guest) { create(:guest, event: event, name: "Lucía Pérez", phone: "+15550102000") }

  it "shows the invitation in the event's language" do
    get guest_invitation_path(guest.access_token)
    expect(page_text).to include('<html lang="es">', "Enviar mi respuesta", "¿Asistirás?")
    expect(page_text).not_to include("Send my RSVP")
  end

  it "lets a guest switch language and remembers the choice" do
    get guest_invitation_path(guest.access_token, lang: "en")
    expect(page_text).to include('<html lang="en">', "Send my RSVP")

    get guest_invitation_path(guest.access_token)
    expect(page_text).to include("Send my RSVP")
  end

  it "ignores languages it doesn't have" do
    get guest_invitation_path(guest.access_token, lang: "xx")
    expect(page_text).to include("Enviar mi respuesta")
  end

  it "explains RSVP problems and confirms in the guest's language" do
    patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "maybe" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("Corrige lo siguiente", "no se puede responder «tal vez»")

    patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } }
    follow_redirect!
    expect(page_text).to include("¡Genial, estás en la lista!")
  end

  it "doesn't leak the guest's language into the host's pages" do
    get guest_invitation_path(guest.access_token)
    sign_in(event.owner)
    get event_path(event)
    expect(page_text).to include('<html lang="en">')
  end

  it "writes emails and texts in the event's language" do
    message = event.messages.create!(kind: "invitation", channels: %w[email sms], idempotency_key: "es-1", audience: {})
    email = GuestMailer.with(delivery: message.deliveries.create!(guest: guest, channel: "email", recipient: guest.email)).notice
    expect(email.subject).to eq("Estás invitado: Fiesta de Ana")
    expect(email.text_part.decoded).to include("Hola, Lucía:", "Tu invitación:")
    expect(email.html_part.decoded).to include("Ver invitación y responder")

    sms = Messaging::SmsComposer.new(message.deliveries.create!(guest: guest, channel: "sms", recipient: guest.phone)).body
    expect(sms).to include("te invitó a Fiesta de Ana", "Responde STOP")
    expect(I18n.locale).to eq(:en)
  end

  it "has every guest string in every language" do
    english = flat_keys(I18n.t("guest", locale: :en))
    Event::LOCALES.each_key do |locale|
      expect(flat_keys(I18n.t("guest", locale: locale))).to eq(english), "#{locale} is missing or has extra keys"
    end
  end

  def flat_keys(hash, prefix = nil)
    hash.flat_map { |key, value| value.is_a?(Hash) ? flat_keys(value, "#{prefix}#{key}.") : [ "#{prefix}#{key}" ] }.sort
  end
end
