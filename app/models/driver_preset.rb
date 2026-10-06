# プルダウンに並べるドライバー設定名。新しい名前は「新しく追加する」から（resolve）だけ増える。
class DriverPreset < ApplicationRecord
  NEW = "__new__".freeze
  NAME_MAX = 100

  validates :name, presence: true, length: { maximum: NAME_MAX }, uniqueness: true
  before_validation { self.name = name.to_s.strip }

  scope :listed, -> { order(:id) } # 先頭（最初に登録したもの）が既定の選択肢

  # フォームの値を、保存してよい設定名にする（空なら nil）。一覧にない名前は拒否する。
  # keep: いま保存されている値。一覧に無くても、そのままなら通す（既存の値を消さない）
  def self.resolve(value, new_name = nil, keep: nil)
    value = value.to_s.strip
    return nil if value.empty?
    return value if value == keep.to_s || exists?(name: value) && value != NEW
    raise ArgumentError, "ドライバーの設定名は、一覧から選ぶか「新しく追加する」で入力してください。" unless value == NEW

    name = new_name.to_s.strip
    raise ArgumentError, "追加する設定名を入力してください。" if name.empty?
    raise ArgumentError, "設定名は #{NAME_MAX} 文字以内にしてください。" if name.length > NAME_MAX
    raise ArgumentError, "「#{name}」はすでにあります。一覧から選んでください。" if exists?(name: name)

    create!(name: name).name
  end
end
