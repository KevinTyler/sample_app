class AddLocaleToEvents < ActiveRecord::Migration[8.1]
  def change
    # The language guests see (invitation pages, RSVP form, emails, texts). Hosts' pages stay in English.
    add_column :events, :locale, :string, null: false, default: "en"
  end
end
