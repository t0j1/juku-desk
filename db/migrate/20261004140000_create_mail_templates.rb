class CreateMailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_templates do |t|
      t.string :key, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :mail_templates, :key, unique: true
  end
end
