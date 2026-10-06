# 1日のスケジュールの「印刷する」タスクに、印刷時のドライバー設定（トレイ・ホチキス等）の名前を持たせる。
# 用紙トレイは SumatraPDF のコマンドラインでは選べず、Windows のプリンタープリセット（印刷設定の保存名）で決まる。
# そのため、トレイの指定は PrintSchedule と同じく driver_preset（プリセット名）で表す。
class AddDriverPresetToDailyScheduleTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_schedule_tasks, :driver_preset, :string
  end
end
