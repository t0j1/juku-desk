class AddImpersonation < ActiveRecord::Migration[8.1]
  def change
    # 代理ログイン用のセッション：対象ユーザーの Session に、操作している管理者・理由・期限・元のセッションを持たせる
    add_reference :sessions, :impersonator, foreign_key: { to_table: :users, on_delete: :cascade }
    add_column :sessions, :impersonation_reason, :text
    add_column :sessions, :impersonation_expires_at, :datetime
    add_column :sessions, :origin_session_id, :bigint

    # 代理ログイン中の操作に、実際に操作した管理者の ID を残す
    add_reference :audit_logs, :impersonator, foreign_key: { to_table: :users }
  end
end
