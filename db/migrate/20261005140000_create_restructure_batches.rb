# 「取り込み済みの問題をまとめて再構造化」の 1 回分。進み具合（n 件中 m 件）を出すために、対象の領域を覚えておく。
class CreateRestructureBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :restructure_batches do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.bigint :region_ids, array: true, default: [], null: false
      t.timestamps
    end
  end
end
