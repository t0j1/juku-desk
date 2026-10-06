# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 開発用の初期ユーザー（本番では SEED_ADMIN_* を環境変数で渡す。パスワードはコードに書かない）
if Rails.env.development?
  { "staff@example.com" => [ "スタッフ（開発）", :staff ],
    "viewer@example.com" => [ "閲覧のみ（開発）", :viewer ],
    "admin@example.com" => [ "システム管理者（開発）", :system_admin ] }.each do |email, (name, role)|
    User.find_or_create_by!(email_address: email) { |u| u.name = name; u.role = role; u.password = "password1234" }
  end
elsif ENV["SEED_ADMIN_EMAIL"].present? && ENV["SEED_ADMIN_PASSWORD"].present?
  User.find_or_create_by!(email_address: ENV["SEED_ADMIN_EMAIL"]) do |u|
    u.name = ENV.fetch("SEED_ADMIN_NAME", "管理者")
    u.role = :system_admin
    u.password = ENV["SEED_ADMIN_PASSWORD"]
  end
end

# 小テスト用の単語帳（CSV は WORDBOOK_SEED_PATH / WORDBOOK_SEED_URL で渡す。無ければスキップ、登録済みなら何もしない）
require Rails.root.join("db/seeds/wordbook_seed")
WordbookSeed.run

# プリンタープリセット（開発・テスト・本番すべてで同じ初期セット）
require Rails.root.join("db/seeds/print_preset_seed")
PrintPresetSeed.run
