class AddCardBackAndTypes < ActiveRecord::Migration[8.1]
  def change
    # "invitation" (with replies), "save_the_date" (no replies; the invitation follows) or
    # "announcement" (news to share: a birth, a move, an engagement).
    add_column :events, :card_type, :string, null: false, default: "invitation"
    add_column :events, :show_ride_links, :boolean, null: false, default: true

    # Buttons on the back of the card: book a table, the registry, the playlist, ...
    create_table :event_links do |t|
      t.references :event, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :label
      t.string :url, null: false, limit: 500
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
