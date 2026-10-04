# 開発ガイド

構成は [ARCHITECTURE.md](ARCHITECTURE.md)、デプロイは [DEPLOYMENT.md](DEPLOYMENT.md)。

## セットアップ
```bash
mise install    # Ruby 3.4.5 / Node 24（.mise.toml）。mise を使わない場合は同じバージョンを入れる
make setup      # bundle install + bin/rails db:prepare + Node 版チェック
make dev        # Rails :3000 と schedule-web :8000 を並行起動（Ctrl+C で両方止まる）
make test       # bin/rails test + schedule-web の node --test
```
片方だけ: `make dev-rails` / `make dev-web`、`make test-rails` / `make test-web`。ポートは `make dev SCHEDULE_PORT=8001`。

## Rails（ルート）
- 詳細はルートの [README.md](../README.md)。`bin/rails test`、`bin/rails test:system`、`bin/rubocop`、`bin/brakeman --no-pager`。
- 512MB 制限のため、PDF 全体を Ruby に載せない（ページ／チャンクごとに qpdf + 一時ファイル）。

### 単語帳（小テスト用）
- 市販の単語帳はリポジトリに置かない。`db:seed` は `WORDBOOK_SEED_PATH`（ローカルの CSV）か `WORDBOOK_SEED_URL`（非公開ストレージの https URL）から取り込み、どちらも無ければスキップする。名前は `WORDBOOK_SEED_NAME`（省略時「LEAP 改訂版」）。同名の単語帳があれば何もしない。
- 開発では架空 10 語のサンプルで足りる: `WORDBOOK_SEED_PATH=db/seeds/sample_wordbook.csv bin/rails db:seed`。本物の CSV を手元に持っている場合はリポジトリ外に置いてそのパスを渡す（`db/seeds/` にコピーしない）。
- 単語帳だけ入れ直すときは `bin/rails wordbook:seed`。テストは `db/seeds/sample_wordbook.csv` と fixture だけを使う。

## apps/schedule-web
- 静的サイト。`make dev-web` は `python3 -m http.server -d apps/schedule-web/public`。
- `package.json` は無く依存ゼロ。テストは Node 組み込み:
  ```bash
  cd apps/schedule-web
  node --test scripts/backup.test.mjs scripts/pickup-api.test.mjs scripts/pickup-common.test.mjs   # = make test-web
  npm i --no-save @electric-sql/pglite && node --test scripts/*.test.mjs                            # DB テストも（CI と同じ）
  ```
- 通しテスト（`scripts/*-e2e.mjs`）は開発用 Supabase に接続する。`apps/schedule-web/.env.dev` に `ADMIN_EMAIL` / `ADMIN_PASSWORD` を書く（Git 無視。コミットしない）。
- 手元で開くと開発用 Supabase、`?db=prod` を付けると本番に繋がる（`public/js/config.js`）。**本番に繋いだ状態でデータを壊す操作をしない。**
- 詳しい手順・Supabase の準備は `apps/schedule-web/README.md` と `apps/schedule-web/CLAUDE.md`。

## 同時に見るときの Tips
- 2 つのアプリは連携していないので、片方の変更でもう片方が壊れることはない。ログは `make dev` の端末に混ざるため、見づらければ `make dev-rails` と `make dev-web` を別の端末で起動する。
- Rails は `.env`、schedule-web は `.env.dev` / `.env.line`（どちらも Git 無視）。

## 変更の流れ
作業ブランチ → PR → レビュー → マージ。CI は変更パスで Rails 側 / schedule-web 側が出し分けられる（[DEPLOYMENT.md](DEPLOYMENT.md) 6）。
