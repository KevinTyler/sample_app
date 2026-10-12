class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :ticket_price_cents, :integer
    add_column :events, :currency, :string, null: false, default: "usd"

    create_table :payments do |t|
      t.references :event, null: false, foreign_key: true
      # Kept (with guest nulled) if a guest is removed, so the money trail survives.
      t.references :guest, foreign_key: { on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.integer :quantity, null: false
      t.string :status, null: false, default: "pending"
      t.string :provider, null: false
      t.string :provider_session_id
      t.string :provider_payment_id
      t.string :checkout_url, limit: 2048
      t.string :idempotency_key, null: false
      t.datetime :paid_at

      t.timestamps
    end
    add_index :payments, :idempotency_key, unique: true
    add_index :payments, [ :provider, :provider_session_id ], unique: true
  end
end
