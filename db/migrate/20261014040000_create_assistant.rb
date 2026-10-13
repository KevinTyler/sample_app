class CreateAssistant < ActiveRecord::Migration[8.1]
  def change
    # One texting thread with Cordially's assistant per phone number and channel (SMS or WhatsApp).
    create_table :assistant_conversations do |t|
      t.string :channel, null: false, default: "sms"
      t.string :address, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :event, foreign_key: { on_delete: :nullify }
      t.string :stage
      t.json :data, null: false, default: {}
      t.datetime :opted_out_at
      t.datetime :last_inbound_at
      t.timestamps
    end
    add_index :assistant_conversations, %i[channel address], unique: true

    create_table :assistant_messages do |t|
      t.references :assistant_conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :direction, null: false # "in" from the host, "out" from the assistant
      t.text :body
      t.json :media, null: false, default: []
      t.string :provider_message_id
      t.datetime :created_at, null: false
    end
    add_index :assistant_messages, :provider_message_id, unique: true, where: "provider_message_id IS NOT NULL"

    # Single-use, short-lived links that sign a texting host into the web app (e.g. to fine-tune a design).
    create_table :sign_in_links do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false, index: { unique: true }
      t.string :redirect_path, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
  end
end
