# 定例印刷の雛形に種別（固定PDF／日次出席名簿／単語テスト）を足す。名簿・単語テストは PDF を持たず、貸し出しの直前に作る（案A）。
class AddKindToPrintSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :print_schedules, :kind, :string, null: false, default: "fixed_pdf"
    add_column :print_schedules, :source_config, :jsonb, null: false, default: {}
    add_column :print_schedules, :layout_config, :jsonb, null: false, default: {}
    add_column :print_schedules, :copies_mode, :string, null: false, default: "fixed"
    change_column_null :print_schedules, :sha256, true
    change_column_null :print_schedules, :byte_size, true

    # 貸し出しの直前に PDF を作るジョブは、作成時点では PDF を持たない
    add_column :print_jobs, :generate_on_lease, :boolean, null: false, default: false
    change_column_null :print_jobs, :sha256, true
    change_column_null :print_jobs, :byte_size, true
  end
end
