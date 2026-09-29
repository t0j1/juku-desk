# このプロジェクトでの注意点

## DB の変更と反映の順番
- DB（`supabase/*.sql`）は、管理者が Supabase の SQL Editor に貼って実行する方式。CLI のマイグレーションは使っていない。
- 反映は **SQL → Edge Function → 画面** の順。先に新しい画面を開くと `Could not find the function ...` や `column ... does not exist` になる（実際に2回起きた）。
- 実行してもらったら、公開キーで確かめる：`permission denied` なら関数・表はある、`PGRST202` / `PGRST205` なら無い（まだ反映されていない）。
- SQL を貼ってもらう直前に、もう一度 `pbcopy` し直す（クリップボードが別のもので上書きされていたことがある）。
- `create or replace function` は戻り値の形を変えられない。引数・戻り値を変えるときは、先に `drop function if exists`（古い形を残すと PostgREST が迷う）。

## テスト
- 手元の Postgres は壊れているので、DB のテストは PGlite（`npm i --no-save @electric-sql/pglite`）で行う。
- PGlite は `date` を JavaScript の `Date` で返す。比べるときは文字列にする。
- テストの SQL を管理者（authenticated）として流すとき、`pickup_now()` などの内部の関数は権限を剥がしてあるので呼べない（日付はテスト側で計算する）。
- 送迎の時刻は `slot_minutes`（15分）刻み。刻みに合わない時刻は正しく拒否される。
- 開発用 Supabase への通しのテスト（`scripts/*-e2e.mjs`）は、`.env.dev` の管理者で動き、作ったデータを最後に消す。

## 画面の確認
- Chrome の拡張は使わない。Playwright（スクラッチパッドに入れる）で撮って確かめる。
- `background-attachment: fixed` のページを全体撮影すると、下のほうが白く写るが、実際の画面では問題ない。

## シェル
- この環境の `rm` は確認つき（対話式）になっていて、スクリプトの途中で止まる。シンボリックリンクは `unlink` で消す。
