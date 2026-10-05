class AddUniqueIndexToPrintStationsName < ActiveRecord::Migration[8.1]
  def change
    # モデルのバリデーションだけでは、同名の同時登録を止められない
    add_index :print_stations, :name, unique: true
  end
end
