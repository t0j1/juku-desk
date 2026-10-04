# 移行計画

| 段階 | 内容 | 状態 |
|---|---|---|
| 1 | モノレポ化: sekigaku-schedule を `apps/schedule-web/` に git subtree で取り込み（履歴保持）、Makefile / CI / ドキュメント整備 | 完了（PR #31 と段階B） |
| 2 | Cloudflare Pages / Worker / 週次バックアップの接続元を、旧リポジトリからこのリポジトリへ切替 | 時期未定 |
| 3 | Supabase → Neon | **当面やらない** |
| 4 | 技術スタックの統一 | 将来検討 |

## 方針（変えないこと）
- DB は統合しない。Rails = Neon、schedule-web = Supabase のまま。
- Rails 本体はルートに置く（`apps/rails-app/` へ移動しない）。
- このリポジトリからのデプロイ実行は、各段階の切替時に別途判断する。

## 段階2: 接続元の切替（実施時のチェックリスト）
1. Cloudflare Pages の接続リポジトリを juku-desk に変更し、Root directory を `apps/schedule-web`、output を `public` にする。プレビューで index / admin / pickup が開くことを確認。
2. `keepalive-worker` は変更なし（手元から `wrangler deploy`）。
3. このリポジトリに `SUPABASE_URL` / `SUPABASE_ANON_KEY` を登録し、`schedule-backup.yml` を手動実行して `backup` ブランチへの push を確認。その後、旧リポジトリの backup ワークフローを止める（二重取得の防止）。既存の `backup` ブランチ（旧リポジトリ）は残す。
4. 旧リポジトリは Archive（削除しない）。ロールバックは Pages の接続先を戻すだけ。
5. 旧リポジトリの未マージブランチ（`feature/pickup` など）があれば、切替前に取り込むか破棄を決める。

## 段階3: Supabase → Neon（実施する場合の論点）
今は計画しない。やるなら先に決めること:
- Supabase 固有機能への依存: Auth（管理者ログイン）、RLS、`pg_cron`（期限切れ予約の自動却下）、Edge Function `pickup-api`。Neon にはこれらが無く、認証と API を作り直す必要がある。
- 移行方式: `supabase/schema.sql` の移植 → データ移行。段階移行（二重書き込み）か一括かは、上記の作り直しの規模で決まる。ダウンタイムは一括なら切替時間分。
- 実施前に Render Free / Neon Free の容量・時間制限を再確認する。
