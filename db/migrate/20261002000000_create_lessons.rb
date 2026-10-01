class CreateLessons < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false
      t.jsonb  :value, null: false, default: {}
      t.timestamps
    end
    add_index :settings, :key, unique: true

    create_table :lessons do |t|
      t.date     :held_on, null: false
      t.integer  :weekday, null: false
      t.time     :starts_at, null: false, default: "19:20"
      t.time     :ends_at,   null: false, default: "22:00"
      t.references :instructor, null: false, foreign_key: { to_table: :users }
      t.text     :overall_memo
      t.text     :homework
      t.text     :manager_note
      t.integer  :status, null: false, default: 0
      t.datetime :finalized_at
      t.datetime :reported_at
      t.integer  :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lessons, [ :held_on, :instructor_id ], unique: true
    add_index :lessons, :status

    create_table :lesson_students do |t|
      t.references :lesson,  null: false, foreign_key: { on_delete: :cascade }
      t.references :student, null: false, foreign_key: true
      t.string  :subject
      t.integer :understanding
      t.boolean :attended, null: false, default: true
      t.text    :memo
      t.timestamps
    end
    add_index :lesson_students, [ :lesson_id, :student_id ], unique: true
  end
end
