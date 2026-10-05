# 大問の指示文（形式ごと）と、小テストの大問・小問の番号。
# section_templates は行が無ければ SectionTemplate::DEFAULTS を使う（編集したものだけ行を作る）。
# test_items.section / sub_position は「形式ごとに並べる」で作ったときだけ入る（従来の小テストは null のまま）。
class CreateSectionTemplatesAndSections < ActiveRecord::Migration[8.1]
  def change
    create_table :section_templates do |t|
      t.string :question_type, null: false
      t.text :instruction, null: false
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :section_templates, :question_type, unique: true

    add_column :test_items, :section, :integer
    add_column :test_items, :sub_position, :integer
    add_column :test_items, :question_type, :string
    add_check_constraint :test_items, "(section IS NULL) = (sub_position IS NULL)", name: "test_items_section_pair"
    add_index :test_items, [ :test_id, :section, :sub_position ], unique: true, where: "section IS NOT NULL"
  end
end
