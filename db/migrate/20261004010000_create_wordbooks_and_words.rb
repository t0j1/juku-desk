class CreateWordbooksAndWords < ActiveRecord::Migration[8.1]
  def change
    create_table :wordbooks do |t|
      t.string :name, null: false
      t.integer :words_count, null: false, default: 0
      t.timestamps
    end
    add_index :wordbooks, :name, unique: true

    create_table :words do |t|
      t.references :wordbook, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :term, null: false
      t.text :meaning, null: false
      t.timestamps
    end
    add_index :words, %i[wordbook_id number], unique: true
  end
end
