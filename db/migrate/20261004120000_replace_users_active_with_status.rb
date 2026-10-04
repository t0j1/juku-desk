class ReplaceUsersActiveWithStatus < ActiveRecord::Migration[8.1]
  # users.active (boolean) → users.status (0=active / 1=suspended / 2=invited)
  def up
    add_column :users, :status, :integer, null: false, default: 0
    execute "UPDATE users SET status = CASE WHEN active THEN 0 ELSE 1 END"
    remove_column :users, :active
  end

  def down
    add_column :users, :active, :boolean, null: false, default: true
    execute "UPDATE users SET active = (status = 0)"
    remove_column :users, :status
  end
end
