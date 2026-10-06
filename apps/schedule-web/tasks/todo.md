# 現在の作業

計画の詳細は `docs/pickup-plan.md`（送迎予約）と `docs/absence-plan.md`（欠席連絡・振替授業）。

## 完了（開発用 Supabase で確認済み・ブランチ `feature/pickup`）
- [x] 送迎予約：DB・Edge Function `pickup-api`・生徒の画面・管理画面（承認・通知・相乗り・人数・日付ごとの時間調整）
- [x] 管理画面のデザイン刷新（サイドバー・カード・送迎予約のダッシュボード）
- [x] 欠席連絡・振替授業：DB・生徒の画面・管理画面（承認待ち・日ごと・生徒ごと・設定）・通知

## 完了（マージ済み PR #5 #6 #7 #9 #10 #11 #14 #15 #16 に対応）
- [x] 生徒への通知（送迎の承認・却下・相乗りの打診、振替の承認・却下）：開発はメール（Resend）、本番は LINE
- [x] LINE 対応：LIFF での本人確認、Messaging API のプッシュ通知、LINE のボタンでの回答（`line-webhook`：相乗り打診の承諾・辞退は実装済み。振替は生徒側の承諾・辞退の仕組みが未定）
- [x] 送迎・欠席・振替のデータの暗号化バックアップ（読み取り専用のバックアップ用ユーザー＋age）

## 残り（人間の作業）
- [ ] 本番への反映：SQL（`pickup.sql` → `absence.sql`）→ Edge Function（`APP_ENV=prod`・`ALLOWED_ORIGINS`）→ 画面（`main` へのマージ）
