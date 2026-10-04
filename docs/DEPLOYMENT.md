# 本番デプロイ手順

このリポジトリには 2 つのアプリがあり、デプロイ先は別々。連携はしていない（[ARCHITECTURE.md](ARCHITECTURE.md)）。

| | デプロイ先 | DB | 契機 |
|---|---|---|---|
| Rails（ルート） | Render Free | Neon Free | `main` で CI 成功 → `deploy.yml` が Deploy Hook を叩く |
| apps/schedule-web | Cloudflare Pages / Worker | Supabase | Cloudflare 側の設定（下記「schedule-web」） |

以降、1〜5 は Rails（Render + Neon）の手順。

## 1. Neon
1. 無料プロジェクトを作成（Region: AWS Asia Pacific (Singapore)）。
2. データベース名 `juku_production` で接続文字列を取得し、末尾に `?sslmode=require` を付ける。**直結（non-pooled）の文字列を使う**（`-pooler` ホストは db:prepare の CREATE DATABASE や Solid Queue が不安定になる）。
3. Solid Cache/Queue/Cable 用の `juku_production_cache` / `_queue` / `_cable` は、起動時の `db:prepare` が同じサーバー上に自動作成する（Neon のオーナーロールは CREATEDB 権限を持つ）。別の場所に置く場合は `CACHE_DATABASE_URL` / `QUEUE_DATABASE_URL` / `CABLE_DATABASE_URL` で上書きする。

## 2. Render（Web Service）
| 項目 | 値 |
|---|---|
| Environment | Docker（`./Dockerfile`、Docker Command は空欄） |
| Instance Type | Free |
| Region | Singapore |
| Health Check Path | `/up` |
| Auto-Deploy | **Off** |

環境変数:
```
RAILS_MASTER_KEY    = config/master.key の中身
DATABASE_URL        = Neon の接続文字列（?sslmode=require 付き）
SOLID_QUEUE_IN_PUMA = true
WEB_CONCURRENCY     = 0   # 512MB プランでは single mode（ワーカープロセスを増やさない）
RAILS_MAX_THREADS   = 3
```
Settings → Deploy Hook の URL を控える。

## 3. GitHub
Settings → Secrets and variables → Actions に `RENDER_DEPLOY_HOOK_URL` を登録する。
`main` への push で CI が成功すると `Deploy` ワークフローが Ruby バージョン整合（Dockerfile / .ruby-version / mise.toml）を確認し、Deploy Hook を叩く。CI が失敗したらデプロイしない。

## 4. 確認
- `https://<app>.onrender.com/up` が 200 を返す。
- Render → Events に各デプロイが並ぶ。**Rollback** はここから（直近のデプロイに戻せる）。

## 5. スリープ防止（cron-job.org）
- URL: `https://<app>.onrender.com/up`、間隔 10 分、**12:00〜23:00（Asia/Tokyo）のみ**。
- 24時間 ping すると 750 時間/月の上限を超えるので禁止。

## 補足
- HTTPS 強制（`force_ssl`）。`/up` だけはリダイレクト対象外。
- マイグレーションはコンテナ起動時に `bin/docker-entrypoint` の `db:prepare` が実行する。

## 6. CI / デプロイのモノレポ対応
- `ci.yml` は変更パスで判定する。`apps/schedule-web/` 以外が変わったときだけ Rails のジョブ、`apps/schedule-web/`（と Makefile / .mise.toml / ci.yml）が変わったときだけ `schedule-web` ジョブ（`node --test`、pglite は一時インストール）が走る。スキップされたジョブは必須チェックでも成功扱い。
- `deploy.yml` は、直近のコミットの変更が `apps/schedule-web/`・`docs/`・`*.md`・`schedule-backup.yml` だけなら Render を叩かない（Free は再起動で数分止まるため）。
- Rails 側の secrets: `RENDER_DEPLOY_HOOK_URL`（上記 3）。

## 7. schedule-web（Cloudflare Pages + Supabase。現行のまま）
現在の Cloudflare Pages は旧リポジトリ sekigaku-schedule に接続されている。**このリポジトリへの切替は未実施**（[MIGRATION_PLAN.md](MIGRATION_PLAN.md) 段階2）。切り替えるときの Pages 設定:
- Root directory: `apps/schedule-web`、Build command: なし、Build output directory: `public`
- Production branch: `main`、Branch control の確認は `apps/schedule-web/README.md` の「B. Cloudflare Pages の設定を確認する」
- `keepalive-worker` は `cd apps/schedule-web/keepalive-worker && npx wrangler deploy`（手元から。秘密は `wrangler secret put`）

### 週次バックアップ（`.github/workflows/schedule-backup.yml`）
毎週日曜 23:00 JST に Supabase の予定を CSV/JSON にして `backup` ブランチへ push する。
- Repository secrets に `SUPABASE_URL` と `SUPABASE_ANON_KEY`（anon のみ。service_role は入れない）を登録するまでは、通知を出して何もしない。
- 旧リポジトリの同名ワークフローが動いている間に登録すると、バックアップが二重に取られる。切替時に旧側を止めること。
- `backups/*.csv` は `backup` ブランチにだけ置く（main に入れない）。

## トラブルシューティング
- **Rails を変えていないのに Render が再デプロイされた**: `deploy.yml` の判定は直近 1 コミット（`HEAD^..HEAD`）の差分。複数コミットを 1 回で push すると最後のコミットしか見ない点に注意。
- **schedule-web だけ変えたのに Rails の CI が走る**: 同じ PR で Rails 側や `ci.yml` 以外のルートのファイルも変えていないか確認する。
- **schedule-web のテストが `import` で落ちる**: Node 24 が必要（`mise install`）。pglite 系は `npm i --no-save @electric-sql/pglite` を `apps/schedule-web` で実行してから。
- **バックアップが何もしない**: secrets 未登録。Actions のログに notice が出る。
