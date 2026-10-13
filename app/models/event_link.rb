# A button on the back of the card: book a table, see the registry, add to the playlist, ...
# Links are plain URLs the host pastes; we recognize well-known services to label them nicely,
# but never call those services (no partner API needed).
class EventLink < ApplicationRecord
  KINDS = {
    "reservation" => { name: "Reservation", cta: "Book a table", icon: :table },
    "registry" => { name: "Registry", cta: "See the registry", icon: :gift },
    "playlist" => { name: "Playlist", cta: "Add a song", icon: :music },
    "photos" => { name: "Photo album", cta: "Share your photos", icon: :image },
    "donation" => { name: "Donation", cta: "Give", icon: :gift },
    "website" => { name: "Website", cta: "Visit the website", icon: :link },
    "other" => { name: "Other link", cta: "Open link", icon: :link }
  }.freeze

  # Host suffix → [service name, kind]. Matching is on the URL's host only.
  PROVIDERS = {
    "opentable.com" => [ "OpenTable", "reservation" ], "resy.com" => [ "Resy", "reservation" ],
    "exploretock.com" => [ "Tock", "reservation" ], "sevenrooms.com" => [ "SevenRooms", "reservation" ],
    "zola.com" => [ "Zola", "registry" ], "amazon.com" => [ "Amazon", "registry" ], "target.com" => [ "Target", "registry" ],
    "babylist.com" => [ "Babylist", "registry" ], "honeyfund.com" => [ "Honeyfund", "registry" ],
    "crateandbarrel.com" => [ "Crate & Barrel", "registry" ], "williams-sonoma.com" => [ "Williams Sonoma", "registry" ],
    "myregistry.com" => [ "MyRegistry", "registry" ], "theknot.com" => [ "The Knot", "registry" ],
    "open.spotify.com" => [ "Spotify", "playlist" ], "music.apple.com" => [ "Apple Music", "playlist" ],
    "music.youtube.com" => [ "YouTube Music", "playlist" ],
    "photos.google.com" => [ "Google Photos", "photos" ], "photos.app.goo.gl" => [ "Google Photos", "photos" ],
    "icloud.com" => [ "iCloud", "photos" ], "gofundme.com" => [ "GoFundMe", "donation" ]
  }.freeze
  MAX_PER_EVENT = 12

  belongs_to :event

  normalizes :url, with: ->(v) { v.to_s.strip }
  normalizes :label, with: ->(v) { v.to_s.squish.presence }

  validates :kind, inclusion: { in: KINDS.keys }
  validates :label, length: { maximum: 60 }
  validates :url, presence: true, length: { maximum: 500 }
  validate :url_is_web_address
  validate :within_limit, on: :create

  before_validation :guess_kind

  default_scope { order(:position, :id) }

  def provider
    host = uri&.host.to_s.downcase.delete_prefix("www.")
    PROVIDERS.find { |suffix, _| host == suffix || host.end_with?(".#{suffix}") }&.last&.first
  end

  def button_text
    label.presence || [ KINDS.dig(kind, :cta), (" on #{provider}" if provider) ].join
  end

  def icon
    KINDS.dig(kind, :icon) || :link
  end

  private
    def uri
      @uri ||= URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end

    def url_is_web_address
      return if url.blank?

      parsed = URI.parse(url)
      errors.add(:url, "must start with https:// or http://") unless parsed.is_a?(URI::HTTP) && parsed.host.present?
    rescue URI::InvalidURIError
      errors.add(:url, "isn't a valid web address")
    end

    def guess_kind
      @uri = nil
      self.kind = PROVIDERS.find { |suffix, _| uri&.host.to_s.downcase.then { |h| h.delete_prefix("www.") == suffix || h.end_with?(".#{suffix}") } }&.last&.last || "other" if kind.blank?
    end

    def within_limit
      errors.add(:base, "An event can have up to #{MAX_PER_EVENT} links") if event && event.links.count >= MAX_PER_EVENT
    end
end
