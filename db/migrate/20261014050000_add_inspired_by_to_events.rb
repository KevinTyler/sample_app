class AddInspiredByToEvents < ActiveRecord::Migration[8.1]
  def change
    # "Make one like this": which event's card a new host started from (growth analytics).
    add_reference :events, :inspired_by_event, foreign_key: { to_table: :events, on_delete: :nullify }
  end
end
