class CreateGuests < ActiveRecord::Migration[8.1]
  def change
    create_table :guests do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :group_name
      t.integer :plus_ones_allowed, null: false, default: 0
      t.string :token_key, null: false
      t.string :rsvp_status, null: false, default: "pending"
      t.integer :party_size, null: false, default: 0
      t.text :guest_note
      t.text :host_notes
      t.string :source, null: false, default: "manual"
      t.datetime :responded_at
      t.datetime :invited_at
      t.datetime :first_viewed_at
      t.datetime :last_viewed_at
      t.datetime :checked_in_at
      t.integer :checked_in_count, null: false, default: 0
      t.datetime :unsubscribed_at

      t.timestamps
    end
    add_index :guests, :token_key, unique: true
    add_index :guests, [ :event_id, :email ], unique: true, where: "email IS NOT NULL"
    add_index :guests, [ :event_id, :rsvp_status ]
    add_index :guests, [ :event_id, :group_name ]
  end
end
