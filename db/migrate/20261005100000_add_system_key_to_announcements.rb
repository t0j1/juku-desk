class AddSystemKeyToAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :system_key, :string
    add_index :announcements, :system_key, unique: true
  end
end
