# 管理画面で編集できるメール文面（パスワードリセット・招待）。行が無ければ DEFAULTS を使う。
# 差し込みは {{name}} {{url}} {{expires}} だけ。ERB などは実行しない（値を順に置き換えるだけ）。
class MailTemplate < ApplicationRecord
  PLACEHOLDERS = {
    "name" => "宛先の氏名",
    "url" => "設定・再設定のリンク",
    "expires" => "リンクの有効期間"
  }.freeze

  DEFAULTS = {
    "invitation" => {
      label: "招待メール",
      subject: "【塾日報ステーション】アカウントの招待",
      body: <<~TEXT
        {{name}} さん

        塾日報ステーションに招待されました。
        次のリンクから初期パスワードを設定してください（{{expires}}有効）。

        {{url}}

        心当たりがない場合は、このメールを破棄してください。
      TEXT
    },
    "password_reset" => {
      label: "パスワードリセット",
      subject: "【塾日報ステーション】パスワードの再設定",
      body: <<~TEXT
        {{name}} さん

        パスワードの再設定を受け付けました。
        次のリンクから新しいパスワードを設定してください（{{expires}}有効）。

        {{url}}

        心当たりがない場合は、このメールを破棄してください。パスワードは変わりません。
      TEXT
    }
  }.freeze

  KEYS = DEFAULTS.keys.freeze
  PLACEHOLDER_PATTERN = /\{\{\s*(\w+)\s*\}\}/

  Rendered = Struct.new(:subject, :body, keyword_init: true)

  belongs_to :updated_by, class_name: "User", optional: true

  validates :key, inclusion: { in: KEYS }, uniqueness: true
  validates :subject, presence: true, length: { maximum: 200 }
  validates :body, presence: true, length: { maximum: 5000 }
  validate :placeholders_known
  validate :link_included

  # 保存されていれば保存された内容、無ければ初期値
  def self.for(key)
    find_by(key: key) || new(key: key, subject: DEFAULTS.fetch(key)[:subject], body: DEFAULTS.fetch(key)[:body])
  end

  def self.label(key) = DEFAULTS.fetch(key)[:label]

  def label = self.class.label(key)

  def customized? = persisted?

  # 初期値に戻す（保存した行を消す）
  def self.reset!(key)
    where(key: key).destroy_all
  end

  # 差し込みを置き換える。値の中の {{...}} は再度置き換えない。件名は 1 行にする（ヘッダー注入の防止）。
  def render(vars)
    Rendered.new(subject: substitute(subject, vars).gsub(/[\r\n]+/, " ").strip, body: substitute(body, vars))
  end

  def sample_vars
    { "name" => "山田 太郎", "url" => "https://example.com/invitations/SAMPLE/edit", "expires" => (key == "invitation" ? "7日間" : "15分間") }
  end

  private
    def substitute(text, vars)
      text.to_s.gsub(PLACEHOLDER_PATTERN) { vars.fetch(Regexp.last_match(1)) { Regexp.last_match(0) }.to_s }
    end

    def used_placeholders
      "#{subject}\n#{body}".scan(PLACEHOLDER_PATTERN).flatten.uniq
    end

    def placeholders_known
      unknown = used_placeholders - PLACEHOLDERS.keys
      errors.add(:base, "使えない差し込みがあります：#{unknown.map { |u| "{{#{u}}}" }.join('、')}") if unknown.any?
    end

    def link_included
      errors.add(:body, "には {{url}}（リンク）を入れてください") unless body.to_s.match?(/\{\{\s*url\s*\}\}/)
    end
end
