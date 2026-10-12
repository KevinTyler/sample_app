class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :host_name
      t.text :description
      t.string :status, null: false, default: "draft"
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :time_zone, null: false, default: "America/New_York"
      t.string :location_name
      t.string :address
      t.string :video_url
      t.datetime :rsvp_deadline
      t.integer :capacity
      t.boolean :allow_maybe, null: false, default: true
      t.boolean :allow_link_rsvp, null: false, default: false
      t.boolean :show_guest_count, null: false, default: false
      t.integer :default_plus_ones, null: false, default: 0
      t.string :share_token, null: false
      t.json :design, null: false, default: {}
      t.integer :calendar_sequence, null: false, default: 0
      t.datetime :published_at
      t.datetime :cancelled_at
      t.text :cancellation_note

      t.timestamps
    end
    add_index :events, :share_token, unique: true
    add_index :events, :status
  end
end
