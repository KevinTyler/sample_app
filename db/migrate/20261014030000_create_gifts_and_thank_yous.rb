class CreateGiftsAndThankYous < ActiveRecord::Migration[8.1]
  def change
    # What each guest brought. Kept private to the hosts.
    create_table :gifts do |t|
      t.references :event, null: false, foreign_key: true
      t.references :guest, foreign_key: { on_delete: :nullify }
      t.string :giver_name, null: false
      t.string :description, null: false
      t.text :notes
      t.timestamps
    end

    # A thank-you for a guest (usually for a gift): a photo or video and/or a written note,
    # opened through its own private link (the token), sent by text or email or shared by hand.
    create_table :thank_yous do |t|
      t.references :event, null: false, foreign_key: true
      t.references :guest, foreign_key: { on_delete: :nullify }
      t.references :gift, foreign_key: { on_delete: :nullify }, index: { unique: true, where: "gift_id IS NOT NULL" }
      t.string :recipient_name, null: false
      t.string :recipient_email
      t.string :recipient_phone
      t.text :message
      t.string :signed, limit: 80
      t.string :token_key, null: false, index: { unique: true }
      t.datetime :sent_at
      t.string :sent_via
      t.datetime :viewed_at
      t.datetime :hearted_at
      t.timestamps
    end
  end
end
