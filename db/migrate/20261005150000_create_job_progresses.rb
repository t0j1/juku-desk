# 時間のかかる処理（PDF解析・分割、Gemini での構造化など）の進み具合を、種類を問わず 1 か所で持つ表。
class CreateJobProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :job_progresses do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :title, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.integer :status, null: false, default: 0 # queued / running / succeeded / failed / cancelled
      t.integer :total # 分からない処理は nil
      t.integer :done, null: false, default: 0
      t.string :message
      t.string :active_job_id # キューから外すときに探す
      t.datetime :cancel_requested_at
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :job_progresses, %i[ user_id status ]
    add_index :job_progresses, %i[ subject_type subject_id ]
  end
end
