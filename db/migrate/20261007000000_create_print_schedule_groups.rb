# 定例印刷のセット（グループ）。同じ時刻に始め、セット内の雛形を順番に、間隔を空けて刷る。
# 雛形（print_schedules）は 0 または 1 つのセットに入る。セット無しは従来どおり。
class CreatePrintScheduleGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :print_schedule_groups do |t|
      t.string :name, null: false
      t.references :print_station, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.integer :weekdays, array: true, default: [], null: false
      t.string :start_time, null: false
      t.integer :interval_minutes, default: 2, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_reference :print_schedules, :print_schedule_group, foreign_key: { on_delete: :nullify }
    add_column :print_schedules, :position, :integer, default: 0, null: false
  end
end
