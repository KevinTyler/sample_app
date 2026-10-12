class CreateEventQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :event_questions do |t|
      t.references :event, null: false, foreign_key: true
      t.string :prompt, null: false
      t.string :kind, null: false, default: "short_text"
      t.json :options, null: false, default: []
      t.boolean :required, null: false, default: false
      t.string :applies_to, null: false, default: "attending"
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    create_table :rsvp_answers do |t|
      t.references :guest, null: false, foreign_key: true
      t.references :event_question, null: false, foreign_key: true
      t.text :value

      t.timestamps
    end
    add_index :rsvp_answers, [ :guest_id, :event_question_id ], unique: true
  end
end
