class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.string :title, null: false
      t.text :body
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :announcements, %i[starts_at ends_at]

    create_table :announcement_reads do |t|
      t.references :announcement, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
    end
    add_index :announcement_reads, %i[announcement_id user_id], unique: true
  end
end
