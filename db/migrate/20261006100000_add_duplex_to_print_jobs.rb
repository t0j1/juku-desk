class AddDuplexToPrintJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :print_jobs, :duplex, :string # long（長辺とじ）/ short（短辺とじ）/ NULL（指定なし＝従来どおり）
  end
end
