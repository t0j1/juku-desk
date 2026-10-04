# 塾日報ステーション (juku-desk)

## モノレポ構成

- ルート … Rails 本体（このアプリ）
- `apps/schedule-web/` … 旧 sekigaku-schedule（静的サイト + Supabase。履歴ごと git subtree で取り込み済み）。DB は Rails=Neon / schedule-web=Supabase のまま変更しない

```bash
make setup   # bundle install + db:prepare + Node 版チェック
make dev     # Rails(:3000) と schedule-web(:8000) を並行起動
make test    # bin/rails test + schedule-web の node --test
```

`apps/schedule-web` の使い方は `apps/schedule-web/README.md`。

## ローカル開発（Docker不使用）

```bash
mise install            # Ruby 3.4.5 / Node 24（.mise.toml）
bundle install
bin/rails db:prepare    # primary / cache / queue / cable を作成
bin/dev                 # web + css + worker
```

- Ruby のバージョンは `.ruby-version` が唯一の真実。`Dockerfile` の `ARG RUBY_VERSION` と必ず一致させる。
- `.env` はコミットしない（`.env.example` を参照）。

## テスト・静的解析

```bash
bin/rails test
bin/rubocop
bin/brakeman --no-pager
```
