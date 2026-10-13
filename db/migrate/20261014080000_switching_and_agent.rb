class SwitchingAndAgent < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :mailing_address, :text

    change_table :users, bulk: true do |t|
      # Defaults for new events ("your usual settings", e.g. brought over from another service)
      t.string :default_host_name
      t.string :time_zone
      t.string :phone_country_code
      t.boolean :default_allow_maybe, null: false, default: true
      t.boolean :default_track_kids, null: false, default: false
      t.integer :default_plus_ones, null: false, default: 0
      t.boolean :default_auto_nudge, null: false, default: false
      t.boolean :default_auto_day_before, null: false, default: false
      t.string :switched_from
      # How the agent reaches the host with things that need them: text (linked phone), email, or off
      t.string :agent_reach, null: false, default: "email"
      t.string :phone_link_code_digest
      t.datetime :phone_link_expires_at
    end

    create_table :contact_imports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "pending"
      t.string :filename
      t.string :file_format
      t.json :sheet # rows of cells; erased once applied or discarded
      t.json :mapping, null: false, default: {}
      t.json :summary, null: false, default: {}
      t.references :event, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    add_column :assistant_messages, :cards, :json, null: false, default: []

    create_table :agent_proposals do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :event, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :dedupe_key, null: false
      t.string :title, null: false
      t.text :body
      t.string :action_label
      t.json :payload, null: false, default: {}
      t.text :result
      t.datetime :notified_at
      t.datetime :decided_at
      t.datetime :expires_at
      t.timestamps
      t.index %i[user_id dedupe_key], unique: true
      t.index %i[user_id status]
    end
  end
end
