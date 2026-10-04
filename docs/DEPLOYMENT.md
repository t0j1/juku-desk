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

## 単語帳（小テスト用）の投入
- 単語帳 CSV は著作権のためリポジトリに含めない。本番にすでに「LEAP 改訂版」があれば何もしなくてよい（seed は登録済みなら何もしない）。
- 新しい環境に入れるとき: CSV を非公開ストレージ（R2 の非公開バケットなど）に置き、期限付きの署名付き URL を発行して、Render の Shell で一度だけ実行する:
  ```
  WORDBOOK_SEED_URL='<署名付き URL>' bin/rails wordbook:seed
  ```
  URL は Render の環境変数に常設しない（使い終わったら期限切れにする）。代わりに管理画面の CSV 取り込みからアップロードしてもよい。
- 環境変数が無い場合、`db:seed` は単語帳をスキップする（エラーにならない）。

## Neon compute の予算
Neon Free は月 100 CU-hours で、5 分間アクセスがないと compute が停止する。**消費量 ≒ compute サイズ × Neon が起きている時間**。

- compute を **0.25 CU 固定**にする（オートスケールを切る）と、100 CU-hours ÷ 0.25 CU ＝ 月 **400 時間**まで起きていられる。
- Neon が起きている時間は、ほぼ「Render が起きている時間」。Solid Queue がワーカーで DB をポーリングするため、Render が動いている間は Neon も起きっぱなしになる。
- そのため、ポーリング間隔を伸ばし（Solid Queue 2 秒。Solid Cable は使わず `async` アダプタ＝DB を触らない）、keepalive は塾で実際に使う時間帯だけに絞る。例: 12:00〜23:00 JST は 11 時間 × 30 日 ＝ 330 時間 ＝ 82.5 CU-hours（0.25 CU 固定の場合）。使う時間帯がもっと短ければ、その分だけ余裕が増える。
- PDF 分割のジョブの開始は、ポーリング間隔が 2 秒になったので最大 1 秒遅くなる。
- Action Cable（ブロードキャスト）は使っていない。使うようになったら `config/cable.yml` を `solid_cable` に戻す必要がある（`database.yml` の cable 設定はそのために残してある）。

### 毎月の確認手順（人間）
1. Neon の Usage 画面で、今月の CU-hours とストレージを見る。月の途中で 70 CU-hours を超えていたら、keepalive の時間帯を短くする。
2. Neon の compute が 0.25 CU 固定のままか確認する（オートスケールが入っていないこと）。
3. cron-job.org の keepalive が、塾で実際に使う時間帯だけになっているか確認する。

## 6. CI / デプロイのモノレポ対応
- `ci.yml` は変更パスで判定する。`apps/schedule-web/` 以外が変わったときだけ Rails のジョブ、`apps/schedule-web/`（と Makefile / .mise.toml / ci.yml）が変わったときだけ `schedule-web` ジョブ（`node --test`、pglite は一時インストール）が走る。スキップされたジョブは必須チェックでも成功扱い。
- `deploy.yml` は、直近に成功した Deploy 実行の `head_sha` から今回までの差分が `apps/schedule-web/`・`docs/`・`*.md` だけなら Render を叩かない。起点が取れないときは必ずデプロイする（Free は再起動で数分止まるため）。
- Rails 側の secrets: `RENDER_DEPLOY_HOOK_URL`（上記 3）。

## 7. schedule-web（Cloudflare Pages + Supabase。現行のまま）
現在の Cloudflare Pages は旧リポジトリ sekigaku-schedule に接続されている。**このリポジトリへの切替は未実施**（[MIGRATION_PLAN.md](MIGRATION_PLAN.md) 段階2）。切り替えるときの Pages 設定:
- Root directory: `apps/schedule-web`、Build command: なし、Build output directory: `public`
- Production branch: `main`、Branch control の確認は `apps/schedule-web/README.md` の「B. Cloudflare Pages の設定を確認する」
- `keepalive-worker` は `cd apps/schedule-web/keepalive-worker && npx wrangler deploy`（手元から。秘密は `wrangler secret put`）

### 週次バックアップ（旧リポジトリで継続）
`apps/schedule-web/.github/workflows/backup.yml` は、このリポジトリでは動かない位置にある（GitHub はルートの `.github/workflows` しか読まない）。**意図的にそのままにしている。**
- バックアップは Supabase の予約・生徒関連データを CSV にして `backup` ブランチへ push する。このリポジトリは **public**、旧 sekigaku-schedule は **private**。ここに移すと個人情報が公開される。
- よって、バックアップは旧 private リポジトリで動かし続ける。このリポジトリに `SUPABASE_URL` / `SUPABASE_ANON_KEY` を登録しない。
- `backups/*.csv` を public リポジトリの Git に入れない。移すなら push 先を private にするか、暗号化した成果物にすること。

### 全体バックアップ（旧リポジトリ・週次）
旧 private リポジトリ sekigaku-schedule の `.github/workflows/backup-full.yml` が、Supabase の DB 全体を `pg_dump` で取得する。上の CSV バックアップとは別に動き、CSV バックアップの側は変えていない。
- 保存先: 世代ごとに orphan ブランチ `backup-full-YYYYMMDD-HHMMSS` を 1 本作り、コミットは 1 つだけにする。最新 8 本を残し、9 本目以降は `git push --delete` で消す。force push は使わない。
- 消したブランチのオブジェクトは GitHub 上ですぐには GC されない。暗号化済みの古いダンプは、しばらくリポジトリに残る。
- ダンプは暗号化の前に検証する（`pg_restore --list` と必須テーブルの確認）。検証に失敗したら push しない。平文のファイルは毎回削除する。
- `pg_dump` は PGDG から入れる。サーバーのメジャーバージョンより古ければジョブは失敗する。
- Secrets が未登録のときは notice を出してスキップし、ジョブは成功扱いになる。
- **人間の作業（必須）**: マージ後に一度手動で実行して緑になることを確認し、手元でダンプを復号して復元できるか確かめる。それまではこのバックアップを完成扱いにしない。このリポジトリに DB 接続文字列を登録しないこと。

## トラブルシューティング
- **Rails を変えていないのに Render が再デプロイされた**: `deploy.yml` は前回成功した Deploy 実行からの差分で判定する。前回の実行履歴が取れないとき（初回など）は安全側でデプロイする。
- **schedule-web だけ変えたのに Rails の CI が走る**: 同じ PR で Rails 側や `ci.yml` 以外のルートのファイルも変えていないか確認する。
- **schedule-web のテストが `import` で落ちる**: Node 24 が必要（`mise install`）。pglite 系は `npm i --no-save @electric-sql/pglite` を `apps/schedule-web` で実行してから。
- **バックアップが動かない**: 旧 private リポジトリ側の Actions を確認する（このリポジトリでは動かさない）。
