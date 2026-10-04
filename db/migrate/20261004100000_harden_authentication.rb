class HardenAuthentication < ActiveRecord::Migration[8.1]
  # users.role: 旧 0=instructor / 1=manager / 2=admin → 新 1=staff / 2=system_admin / 3=viewer
  # 既存ユーザーは全員 staff。system_admin にするのは SYSTEM_ADMIN_EMAIL のアカウントだけ。
  # SYSTEM_ADMIN_EMAIL が未設定のときだけ、安全側（締め出さない）として旧 admin を system_admin に引き継ぐ。
  def up
    add_column :users, :failed_attempts, :integer, null: false, default: 0
    add_column :users, :locked_until, :datetime

    email = ENV["SYSTEM_ADMIN_EMAIL"].to_s.strip.downcase
    if email.present?
      execute sanitize_sql([ "UPDATE users SET role = CASE WHEN email_address = ? THEN 2 ELSE 1 END", email ])
    else
      execute "UPDATE users SET role = CASE WHEN role = 2 THEN 2 ELSE 1 END"
    end
    change_column_default :users, :role, from: 0, to: 1

    create_table :password_histories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :password_digest, null: false
      t.timestamps
    end
    # 今のパスワードも「直近 5 回分」に数える
    execute <<~SQL
      INSERT INTO password_histories (user_id, password_digest, created_at, updated_at)
      SELECT id, password_digest, NOW(), NOW() FROM users
    SQL

    create_table :login_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :email_address, null: false
      t.string :ip_address
      t.string :user_agent
      t.boolean :success, null: false, default: false
      t.string :reason
      t.datetime :created_at, null: false
    end
    add_index :login_events, :created_at
    add_index :login_events, :email_address
  end

  def down
    drop_table :login_events
    drop_table :password_histories
    execute "UPDATE users SET role = CASE WHEN role = 2 THEN 2 ELSE 0 END"
    change_column_default :users, :role, from: 1, to: 0
    remove_column :users, :locked_until
    remove_column :users, :failed_attempts
  end

  private
    def sanitize_sql(args)
      ActiveRecord::Base.sanitize_sql_array(args)
    end
end
