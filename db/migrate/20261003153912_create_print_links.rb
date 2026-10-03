class CreatePrintLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :print_links do |t|
      t.string :token, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :print_links, :token, unique: true
  end
end
