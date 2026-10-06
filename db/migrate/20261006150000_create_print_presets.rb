class CreatePrintPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :print_presets do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :print_presets, :name, unique: true
  end
end