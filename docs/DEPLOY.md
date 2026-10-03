# 本番デプロイ手順（Render Free + Neon Free）

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
