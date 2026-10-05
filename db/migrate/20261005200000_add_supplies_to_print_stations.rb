class AddSuppliesToPrintStations < ActiveRecord::Migration[8.1]
  def change
    add_column :print_stations, :toner_status, :string # ok / low / empty。NULL = 不明（エージェントが取れない・古い版）
    add_column :print_stations, :paper_status, :string
  end
end
