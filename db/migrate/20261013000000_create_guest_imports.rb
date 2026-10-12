class CreateGuestImports < ActiveRecord::Migration[8.1]
  def change
    create_table :guest_imports do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :filename
      # The raw upload is kept only until the import is confirmed or discarded, then erased.
      t.text :csv_data
      t.boolean :update_existing, null: false, default: false
      t.string :status, null: false, default: "pending"
      t.json :summary, null: false, default: {}

      t.timestamps
    end
  end
end
