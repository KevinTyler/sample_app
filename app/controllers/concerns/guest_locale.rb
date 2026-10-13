# Guest-facing pages speak the event's language (Event#locale). A guest can pick another with
# ?lang=xx; the choice is remembered in a cookie.
module GuestLocale
  extend ActiveSupport::Concern

  private
    def with_guest_locale(&)
      I18n.with_locale(guest_locale, &)
    end

    def guest_locale
      requested = params[:lang].to_s
      if Event::LOCALES.key?(requested)
        cookies[:guest_lang] = { value: requested, expires: 1.year, same_site: :lax }
        return requested
      end
      remembered = cookies[:guest_lang].to_s
      return remembered if Event::LOCALES.key?(remembered)

      @event&.locale.presence || I18n.default_locale
    end
end
