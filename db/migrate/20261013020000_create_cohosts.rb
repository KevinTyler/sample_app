class CreateCohosts < ActiveRecord::Migration[8.1]
  def change
    create_table :event_memberships do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end
    add_index :event_memberships, [ :event_id, :user_id ], unique: true

    create_table :cohost_invitations do |t|
      t.references :event, null: false, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false
      # Only a SHA-256 digest of the invitation token is stored.
      t.string :token_digest, null: false
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end
    add_index :cohost_invitations, :token_digest, unique: true
    add_index :cohost_invitations, [ :event_id, :email ]
  end
end
