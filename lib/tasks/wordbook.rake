namespace :wordbook do
  desc "WORDBOOK_SEED_PATH / WORDBOOK_SEED_URL の CSV から単語帳を取り込む（登録済みなら何もしない）"
  task seed: :environment do
    require Rails.root.join("db/seeds/wordbook_seed")
    WordbookSeed.run
  end
end
