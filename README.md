# 塾日報ステーション (juku-desk)

## ローカル開発（Docker不使用）

```bash
mise install            # Ruby 3.4.5 / Node 20.18.0（.mise.toml）
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
