class RemoveSpreadFromPdfSplitJobs < ActiveRecord::Migration[8.1]
  # PR #21〜#23（見開き分割）を取り消したため、#21 で追加したカラムを削除する
  def change
    remove_column :pdf_split_jobs, :spread_state, :integer, default: 0, null: false, if_exists: true
    remove_column :pdf_split_jobs, :spread_pages, :jsonb, default: [], null: false, if_exists: true
    remove_column :pdf_split_jobs, :binding, :string, default: "left", null: false, if_exists: true
    remove_column :pdf_split_jobs, :page_map, :jsonb, default: [], null: false, if_exists: true
  end
end
