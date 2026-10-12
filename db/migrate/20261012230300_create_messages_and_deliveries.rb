class CreateMessagesAndDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :event, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :subject
      t.text :body
      t.json :channels, null: false, default: [ "email" ]
      t.json :audience, null: false, default: {}
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_for
      t.datetime :dispatched_at
      t.integer :recipients_count, null: false, default: 0

      t.timestamps
    end
    add_index :messages, [ :event_id, :idempotency_key ], unique: true
    add_index :messages, [ :status, :scheduled_for ]

    create_table :deliveries do |t|
      t.references :message, null: false, foreign_key: true
      t.references :guest, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "queued"
      t.string :recipient, null: false
      t.string :provider
      t.string :provider_message_id
      t.string :error_message
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :sent_at

      t.timestamps
    end
    add_index :deliveries, [ :message_id, :guest_id, :channel ], unique: true
    add_index :deliveries, :status
  end
end
