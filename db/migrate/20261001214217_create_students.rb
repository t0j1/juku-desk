class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.string :name, null: false
      t.string :grade
      t.date :enrolled_on
      t.date :left_on
      t.text :note
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :students, :name

    create_table :student_weekdays do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :weekday, null: false
      t.timestamps
    end
    add_index :student_weekdays, [ :student_id, :weekday ], unique: true
  end
end
