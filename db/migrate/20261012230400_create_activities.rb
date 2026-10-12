class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :event, null: false, foreign_key: true
      t.references :guest, foreign_key: { on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.json :data, null: false, default: {}

      t.datetime :created_at, null: false
    end
    add_index :activities, [ :event_id, :created_at ]
  end
end
