class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    # A host's address book, reused across events. Private to the host who owns it.
    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :household
      t.text :notes
      t.datetime :last_invited_at
      t.timestamps
    end
    add_index :contacts, %i[user_id email], unique: true, where: "email IS NOT NULL"
    add_index :contacts, %i[user_id name]
  end
end
