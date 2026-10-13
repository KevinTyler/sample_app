class AddHostingEssentials < ActiveRecord::Migration[8.1]
  def change
    # Replies: adults vs. kids, and the names of plus-ones. party_size stays the total headcount.
    add_column :guests, :kids_count, :integer, null: false, default: 0
    add_column :guests, :plus_one_names, :json, null: false, default: []

    add_column :events, :track_kids, :boolean, null: false, default: false
    add_column :events, :ask_plus_one_names, :boolean, null: false, default: false
    add_column :events, :guestbook_enabled, :boolean, null: false, default: true
    # Automatic reminders (materialized as scheduled Messages; see AutoReminders).
    add_column :events, :auto_nudge, :boolean, null: false, default: false
    add_column :events, :nudge_days_before, :integer, null: false, default: 3
    add_column :events, :auto_day_before, :boolean, null: false, default: false

    # Host notifications: "instant", "daily" or "off".
    add_column :users, :rsvp_notifications, :string, null: false, default: "instant"
    add_column :users, :last_digest_at, :datetime

    create_table :guestbook_entries do |t|
      t.references :event, null: false, foreign_key: true
      t.references :guest, foreign_key: { on_delete: :nullify }
      t.string :author_name, null: false
      t.text :body, null: false
      t.datetime :hidden_at
      t.timestamps
    end
    add_index :guestbook_entries, %i[event_id created_at]
  end
end
