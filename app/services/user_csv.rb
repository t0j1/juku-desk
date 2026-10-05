require "csv"

# ユーザーの CSV 一括登録・一括停止の読み取りと検証。DB は書き換えない（プレビュー用）。
class UserCsv
  MAX_BYTES = 200.kilobytes
  MAX_ROWS = 500
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  HEADERS = { "email_address" => :email, "メールアドレス" => :email, "name" => :name, "氏名" => :name, "role" => :role, "権限" => :role }.freeze
  ROLE_ALIASES = { "staff" => "staff", "スタッフ" => "staff", "viewer" => "viewer", "閲覧のみ" => "viewer",
                   "system_admin" => "system_admin", "システム管理者" => "system_admin" }.freeze

  Row = Struct.new(:line, :email, :name, :role, :errors, keyword_init: true) do
    def valid? = errors.empty?
  end

  class Invalid < StandardError; end

  # 一括登録: email_address,name,role（role は省略すると staff）
  def self.parse_import(text)
    rows = read(text)
    seen = {}
    existing = User.where(email_address: rows.filter_map { |r| normalize(r[:email]).presence }).pluck(:email_address).to_set
    rows.each_with_index.map do |raw, i|
      email = normalize(raw[:email])
      role = raw[:role].to_s.strip.presence ? ROLE_ALIASES[raw[:role].to_s.strip.downcase] || ROLE_ALIASES[raw[:role].to_s.strip] : "staff"
      errors = []
      errors << "メールアドレスの形式が正しくありません" unless email.match?(EMAIL_FORMAT)
      errors << "氏名がありません" if raw[:name].to_s.strip.empty?
      errors << "権限が不正です（staff / viewer / system_admin）" if role.nil?
      errors << "すでに登録されています" if existing.include?(email)
      errors << "ファイル内で重複しています（#{seen[email]}行目と同じ）" if seen.key?(email)
      seen[email] ||= i + 2
      Row.new(line: i + 2, email: email, name: raw[:name].to_s.strip, role: role, errors: errors)
    end
  end

  # 一括停止: メールアドレスの列（email_address 列がある CSV、または 1 行 1 アドレス）
  def self.parse_suspend(text, current_user:)
    emails = read_emails(text)
    users = User.where(email_address: emails.map { |e| normalize(e) }).index_by(&:email_address)
    seen = Set.new
    emails.each_with_index.map do |raw, i|
      email = normalize(raw)
      user = users[email]
      errors = []
      errors << "登録されていません" unless user
      errors << "自分自身は停止できません" if user && user == current_user
      errors << "すでに停止中です" if user&.suspended?
      errors << "ファイル内で重複しています" unless seen.add?(email)
      Row.new(line: i + 2, email: email, name: user&.name.to_s, role: user&.role, errors: errors)
    end
  end

  def self.normalize(email) = email.to_s.strip.downcase

  def self.clean(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    raise Invalid, "UTF-8 の CSV を選んでください" unless text.valid_encoding?
    raise Invalid, "ファイルが大きすぎます（#{MAX_BYTES / 1024}KB まで）" if text.bytesize > MAX_BYTES
    raise Invalid, "ファイルが空です" if text.strip.empty?

    text
  end
  private_class_method :clean

  def self.read(text)
    table = CSV.parse(clean(text), headers: true)
    columns = table.headers.compact.to_h { |h| [ HEADERS[h.strip], h ] }
    raise Invalid, "ヘッダー行に email_address と name の列が必要です" unless columns[:email] && columns[:name]
    raise Invalid, "行数が多すぎます（#{MAX_ROWS}行まで）" if table.size > MAX_ROWS

    table.map { |row| { email: row[columns[:email]], name: row[columns[:name]], role: columns[:role] && row[columns[:role]] } }
  rescue CSV::MalformedCSVError => e
    raise Invalid, "CSV を読み取れません（#{e.message}）"
  end
  private_class_method :read

  def self.read_emails(text)
    text = clean(text)
    table = CSV.parse(text, headers: false)
    header = table.first&.map { |c| HEADERS[c.to_s.strip] }
    if header&.include?(:email)
      idx = header.index(:email)
      emails = table.drop(1).map { |r| r[idx] }
    else
      emails = table.map(&:first)
    end
    emails = emails.map(&:to_s).reject { |e| e.strip.empty? }
    raise Invalid, "行数が多すぎます（#{MAX_ROWS}行まで）" if emails.size > MAX_ROWS

    emails
  rescue CSV::MalformedCSVError => e
    raise Invalid, "CSV を読み取れません（#{e.message}）"
  end
  private_class_method :read_emails
end
