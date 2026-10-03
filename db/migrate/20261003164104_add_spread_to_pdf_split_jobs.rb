class AddSpreadToPdfSplitJobs < ActiveRecord::Migration[8.1]
  def change
    # 見開き（横長）ページの扱い。spread_pages は元PDFで横長だったページ番号
    add_column :pdf_split_jobs, :spread_state, :integer, default: 0, null: false
    add_column :pdf_split_jobs, :spread_pages, :jsonb, default: [], null: false
    add_column :pdf_split_jobs, :binding, :string, default: "left", null: false
    # 分けたあとの各ページが元PDFのどこから来たか: [[元ページ, "L"|"R"|nil], ...]
    add_column :pdf_split_jobs, :page_map, :jsonb, default: [], null: false
  end
end
