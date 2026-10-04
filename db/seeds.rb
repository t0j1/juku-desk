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
  { "instructor@example.com" => [ "講師（開発）", :instructor ],
    "manager@example.com" => [ "上長（開発）", :manager ],
    "admin@example.com" => [ "管理者（開発）", :admin ] }.each do |email, (name, role)|
    User.find_or_create_by!(email_address: email) { |u| u.name = name; u.role = role; u.password = "password" }
  end
elsif ENV["SEED_ADMIN_EMAIL"].present? && ENV["SEED_ADMIN_PASSWORD"].present?
  User.find_or_create_by!(email_address: ENV["SEED_ADMIN_EMAIL"]) do |u|
    u.name = ENV.fetch("SEED_ADMIN_NAME", "管理者")
    u.role = :admin
    u.password = ENV["SEED_ADMIN_PASSWORD"]
  end
end

# 小テスト用の単語帳（CSV は WORDBOOK_SEED_PATH / WORDBOOK_SEED_URL で渡す。無ければスキップ、登録済みなら何もしない）
require Rails.root.join("db/seeds/wordbook_seed")
WordbookSeed.run
