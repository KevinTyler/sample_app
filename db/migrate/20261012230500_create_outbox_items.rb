# Local development "outbox": stores emails and SMS messages instead of sending them,
# so the full invite → RSVP flow can be exercised without provider credentials.
class CreateOutboxItems < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_items do |t|
      t.string :channel, null: false
      t.string :recipient, null: false
      t.string :subject
      t.text :text_body
      t.text :html_body
      t.json :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end
  end
end
