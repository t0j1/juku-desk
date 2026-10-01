# key/value の運用設定。value は jsonb
class Setting < ApplicationRecord
  DEFAULTS = {
    "lesson_time" => { "starts_at" => "19:20", "ends_at" => "22:00" }
  }.freeze

  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key.to_s)&.value || DEFAULTS[key.to_s]
  end

  def self.set(key, value)
    find_or_initialize_by(key: key.to_s).tap { |s| s.update!(value:) }
  end

  def self.lesson_time
    DEFAULTS["lesson_time"].merge(get(:lesson_time).to_h)
  end
end
