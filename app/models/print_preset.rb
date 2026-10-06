# プリンタードライバーのプリセット名を管理する。管理者が一覧をメンテし、画面ではプルダウンから選ぶ。
# 「新しく追加する」を選ぶと入力欄が出て、保存時にここに追加される。
class PrintPreset < ApplicationRecord
  MAX_NAME_LENGTH = 100

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }, uniqueness: true

  scope :ordered, -> { order(:name) }

  # プルダウン用の選択肢を返す
  # with_default: true のとき、先頭に「(既定を使う)」を置く（空欄＝ドライバーの既定）
  # current_value: 編集画面で、既存の値が一覧にない場合に「現在の値」として残すための値
  def self.for_select(with_default: false, current_value: nil)
    options = ordered.pluck(:name).map { |n| [n, n] }
    if with_default
      options.unshift(["(既定を使う)", ""])
    end
    # 既存の値が一覧にない場合、それを「現在の値」として先頭に追加
    if current_value.present? && !exists?(name: current_value)
      options.unshift(["#{current_value} （現在の値）", current_value])
    end
    options << ["新しく追加する", "__new__"]
    options
  end

  # 「新しく追加する」経由で名前を追加する（重複・空文字・100文字超は拒否）
  def self.add_new!(name)
    name = name.to_s.strip
    raise ArgumentError, "プリセット名を入力してください" if name.blank?
    raise ArgumentError, "プリセット名は #{MAX_NAME_LENGTH} 文字以内で入力してください" if name.length > MAX_NAME_LENGTH
    raise ArgumentError, "そのプリセット名はすでに存在します" if exists?(name: name)
    create!(name: name)
  end
end
