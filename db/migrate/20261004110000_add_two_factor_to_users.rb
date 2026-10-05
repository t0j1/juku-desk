class AddTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_secret_ciphertext, :string
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_step, :bigint
    # 管理者に 2FA をリセットされた人は、次のログインで再設定を求める
    add_column :users, :otp_setup_required, :boolean, null: false, default: false

    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :recovery_codes, %i[user_id code_digest], unique: true
  end
end
