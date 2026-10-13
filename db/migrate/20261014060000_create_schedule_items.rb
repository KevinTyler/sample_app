class CreateScheduleItems < ActiveRecord::Migration[8.1]
  def change
    # Events within an event (a wedding weekend: mehndi, sangeet, ceremony, reception), each with its
    # own time, place and — optionally — its own guest groups and replies.
    create_table :schedule_items do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :location_name
      t.string :address
      t.text :description
      t.json :audience_groups, null: false, default: [] # empty = every guest
      t.boolean :collects_replies, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :schedule_replies do |t|
      t.references :schedule_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :guest, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :attending, null: false
      t.timestamps
    end
    add_index :schedule_replies, %i[schedule_item_id guest_id], unique: true
  end
end
