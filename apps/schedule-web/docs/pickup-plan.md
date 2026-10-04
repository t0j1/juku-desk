# 送迎予約管理システム 実装計画

既存の「碩学館 年間スケジュール」（Cloudflare Pages ＋ Supabase、ビルドなしの静的 HTML/JS）に、送迎予約の機能を追加する計画です。

## 前提（決定事項）

| 項目 | 決定 | 設計への影響 |
|---|---|---|
| 送迎の向き | **勝瑞駅 → 碩学館のみ**（帰りはなし） | 予約に「行き／帰り」は持たない |
| 乗車場所 | **勝瑞駅のみ** | 場所の入力欄は作らない。画面と通知に「乗車場所：勝瑞駅」と固定で表示（`pickup_settings.pickup_place`） |
| 車両 | **1台のみ・1便 約15分** | 時間の重なる便を**DBの制約で作れない**ようにする（2.3）。フォームでも重なる時刻は出さない |
| 利用者 | **在籍生のみ。LINE を使うのは生徒本人** | 生徒名簿（`students`）を作り、管理者が発行する**登録コード**（1回だけ使える）で生徒本人のLINEと結び付ける。予約は結び付けたアカウントからだけできる |
| 通知 | **開発時はメール、本番はLINE**（LINE公式アカウントは既存。予約は1日2〜4件） | 通知の送り先を切り替えられる作りにする（開発＝Resend のメール、本番＝LINE Messaging API のプッシュ通知） |
| 受付期限 | **送迎の10分前まで** | `min_lead_minutes = 10`。予約・キャンセルとも10分前まで。管理者への通知はすぐ届く方法にする（5.3）。**承認されないまま送迎時刻を過ぎた予約は、自動で「却下（期限切れ）」にする** |
| データ | **削除せずに残し、バックアップも取る** | 削除の仕組みは作らない。送迎のデータは個人情報を含むので、既存の公開用バックアップとは分け、**暗号化して**保存する（6章） |

## 0. 当初の要件から変えた点（理由つき）

この章と、以下の各章の提案は**すべて採用が決定**しています。

| # | 要件 | 変更案 | 理由 |
|---|---|---|---|
| 1 | 予約に名前・メール・電話を毎回入力 | 予約は `student_id` を持つだけにする。名前・電話は生徒名簿で管理者が管理する | 在籍生に限るため。本番ではLINEで本人確認ができるので、毎回の入力は不要 |
| 2 | フォームから予約テーブルに直接書き込む | anon には**どのテーブルの権限も与えない**。利用者の操作は Edge Function `pickup-api` を通し、その中で本人確認（LINE／登録コード）をしてから、DB関数を呼ぶ | 公開キーでテーブルを開けると、全員分の個人情報が読めてしまう。本人確認はブラウザ側では信用できない |
| 3 | 承認済み予約を「送迎」種別で `events` に登録 | `events` には**書き込まず**、管理画面の「予定」タブで送迎を**読み取り専用の行として重ねて表示**する | `events` は閲覧ページ・公開用の週次バックアップの元データ。生徒名が入ると外に出る。`event_types` に「送迎」を足すと閲覧ページの凡例にも出る |
| 4 | `pickup_groups.current_capacity` を列で持つ | 持たずに、その都度数える | キャンセルなどのたびに数がずれる原因になる |
| 5 | 相乗りの打診も予約の `status` で表す | 新テーブル `pickup_proposals` に、予約ごとの回答を持たせる（画面では「調整中」） | 打診は、一人ひとりの回答を記録する必要がある |
| 6 | 打診メールのリンクで承認／却下 | 本番：LINEのボタン（postback）で回答。開発：メールのリンク先は**回答ページ**にし、ページ上のボタンで確定する | メールのセキュリティスキャナがリンクを自動で開くので、開いただけで確定すると勝手に「承認」になる。LINEの postback は本人が押したときだけ届く |

---

## 1. 全体構成

```
public/
  pickup.html              利用者の画面（本番は LINE の LIFF アプリとして開く）
                           ：登録コードの入力／予約／自分の予約の確認・キャンセル・相乗り打診への回答
  pickup-respond.html      開発用：メールのリンクから開く回答ページ（noindex）
  admin.html               タブ追加：「送迎予約」「送迎設定」「生徒」
  js/pickup-common.js      時刻枠の計算・共通時刻の提案（ブラウザと node テストで共用）
  js/pickup.js / js/pickup-respond.js / js/admin-pickup.js
  css/pickup.css           style.css を土台にする（スマホ優先）
supabase/
  pickup.sql               送迎のテーブル・RLS・DB関数・トリガー（何度実行しても壊れない形）
  functions/
    pickup-api/            利用者向けAPI（本人確認 → DB関数）
    pickup-notify/         通知の送信（DB Webhook から呼ばれる。メール／LINE を切り替え）
    line-webhook/          LINE からのイベント（相乗り打診のボタン、友だち追加）
scripts/
  pickup.test.mjs          提案ロジック・時刻枠計算のテスト
  pickup-backup.mjs        送迎データの暗号化バックアップ（6章）
```

- 既存の `schema.sql` とは分けて `pickup.sql` にします。README に「2-b. `pickup.sql` を実行」を足します。
- `is_admin()`・`set_updated_at()`・`log_audit()` は既存のものをそのまま使います。
- **開発環境と本番環境**：Supabase の無料プランはプロジェクトを2つ作れるので、開発用と本番用に分けることをおすすめします。Edge Function の Secret `APP_ENV`（`dev` / `prod`）で、本人確認と通知の方法を切り替えます。
  | | 開発（dev） | 本番（prod） |
  |---|---|---|
  | 本人確認 | 初回に登録コードとメールアドレスを入力して結び付け、以後はメールアドレスで識別（**`APP_ENV=dev` のときだけ**有効） | LINE ログイン（LIFF の ID トークンを、Edge Function で LINE に問い合わせて確認） |
  | 通知 | Resend のメール（独自ドメインなしなら、**自分のアドレスにしか届かない**。本物の生徒に誤って送る心配がない） | LINE のプッシュ通知 |
  | 打診への回答 | メールのリンク → 回答ページ | LINE のボタン、または LIFF の「自分の予約」画面 |

---

## 2. データベース設計（`supabase/pickup.sql`）

### 2.1 テーブル

```sql
-- 設定（1行だけ）
create table if not exists public.pickup_settings (
  id                int primary key default 1 check (id = 1),
  pickup_place      text not null default '勝瑞駅',
  slot_minutes      int  not null default 15 check (slot_minutes in (5,10,15,30)),  -- 希望時刻の刻み
  trip_minutes      int  not null default 15,  -- 1便の所要時間（勝瑞駅を出てから次の便を出せるまで）
  tolerance_minutes int  not null default 10,  -- 相乗りで許容する時刻のずれ（提案の計算用）
  min_lead_minutes  int  not null default 10,  -- 何分前まで予約・キャンセルできるか
  max_advance_days  int  not null default 60,  -- 何日先まで予約できるか
  admin_notify_email text                       -- 管理者への通知先
);

-- 生徒名簿（管理者が登録）
create table if not exists public.students (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  grade      text not null default '',          -- 高1 / 高2 / 高3
  phone      text not null default '',          -- 管理者の連絡用
  is_active  boolean not null default true,     -- 退塾したら false（データは残す）
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 登録コード（管理者が生徒ごとに発行。有効期限つき）
create table if not exists public.student_link_codes (
  code_hash  text primary key,                  -- sha256(コード)。元のコードは発行時に一度だけ画面に表示
  student_id uuid not null references public.students(id) on delete cascade,
  expires_at timestamptz not null,
  max_uses   int not null default 1,            -- 生徒本人のLINEだけなので1回
  used_count int not null default 0
);

-- 生徒と連絡先（LINE アカウント／開発用メール）の結び付け。LINE の機種変更などで作り直せるよう、別テーブルにする
create table if not exists public.student_contacts (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references public.students(id) on delete cascade,
  line_user_id text,                            -- 本番
  email        text,                            -- 開発
  display_name text not null default '',        -- LINE の表示名（管理画面での確認用）
  is_active    boolean not null default true,
  linked_at    timestamptz not null default now(),
  check (line_user_id is not null or email is not null),
  unique (student_id, line_user_id)
);

-- 送迎可能時間帯（1つの曜日に複数の時間帯も可）
create table if not exists public.pickup_availability (
  id           uuid primary key default gen_random_uuid(),
  day_of_week  smallint not null check (day_of_week between 0 and 6),
  start_time   time not null,
  end_time     time not null,
  max_capacity int  not null default 3 check (max_capacity between 1 and 8),
  is_active    boolean not null default true,
  check (end_time > start_time)
);

-- 便（＝相乗りグループ。1人だけの便も1グループ）
create table if not exists public.pickup_groups (
  id            uuid primary key default gen_random_uuid(),
  pickup_date   date not null,
  approved_time time not null,
  trip_minutes  int  not null,                  -- 作成時の設定値を写す（下の制約で使う）
  max_capacity  int  not null,
  status        text not null default 'confirmed' check (status in ('proposing','confirmed','cancelled')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 予約
create table if not exists public.pickup_reservations (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.students(id),
  contact_id    uuid references public.student_contacts(id),  -- 誰のLINEから予約したか
  pickup_date   date not null,
  pickup_time   time not null,
  approved_time time,
  status        text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  notes         text not null default '' check (char_length(notes) <= 300),
  reject_reason text not null default '',
  group_id      uuid references public.pickup_groups(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (status <> 'approved' or (approved_time is not null and group_id is not null))
);
create index if not exists pickup_res_date_idx on public.pickup_reservations (pickup_date, status);
-- 同じ生徒が同じ日に有効な予約を2件持てないようにする
create unique index if not exists pickup_res_one_per_day
  on public.pickup_reservations (student_id, pickup_date) where status in ('pending','approved');

-- 相乗り打診（予約ごとの回答）
create table if not exists public.pickup_proposals (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.pickup_groups(id) on delete cascade,
  reservation_id uuid not null references public.pickup_reservations(id) on delete cascade,
  proposed_time  time not null,
  token_hash     text unique,                   -- 開発用の回答リンク（sha256）。本番は postback なので不要
  response       text not null default 'waiting' check (response in ('waiting','accepted','declined','expired')),
  responded_at   timestamptz,
  expires_at     timestamptz not null,          -- 送迎時刻の10分前
  unique (group_id, reservation_id)
);

-- 通知の記録（送った・失敗した。再送にも使う）
create table if not exists public.pickup_notifications (
  id             bigint generated always as identity primary key,
  at             timestamptz not null default now(),
  channel        text not null check (channel in ('email','line')),
  kind           text not null,                 -- received / approved / rejected / proposal / confirmed / admin_new / admin_answer
  reservation_id uuid references public.pickup_reservations(id),
  recipient      text not null,
  ok             boolean not null,
  error          text
);
```

### 2.2 権限と RLS
- 全テーブル RLS 有効。**authenticated（管理者）にだけ**権限を与え、ポリシーは `(select public.is_admin())`（既存の `events` と同じ書き方）。
- **anon にはテーブル権限なし。** 例外として、個人情報を返さない `get_pickup_slots(date)` だけ anon に実行を許す（フォームの時刻一覧用）。
- 利用者の操作用のDB関数は `security definer` にして、**service_role にだけ**実行を許します（Edge Function `pickup-api` からだけ呼べる）。
  | DB関数 | 用途 |
  |---|---|
  | `get_pickup_slots(p_date)` | 選べる時刻と残り人数（2.4） |
  | `link_student(p_code, p_line_user_id, p_display_name)` | 登録コードで生徒とLINEを結び付ける |
  | `submit_pickup_reservation(p_contact_id, p_student_id, p_date, p_time, p_notes)` | 予約する |
  | `cancel_pickup_reservation(p_contact_id, p_reservation_id)` | キャンセル（10分前まで） |
  | `respond_pickup_proposal(p_contact_id, p_proposal_id, p_accept)` | 相乗り打診に回答 |
  | `my_pickup_reservations(p_contact_id)` | 自分の予約一覧（結び付けた生徒の分だけ） |

`submit_pickup_reservation` で確認すること（満たさなければ例外。エラー文はフォームでそのまま表示できる日本語にする）:
1. その連絡先が、その生徒に結び付いていて、生徒が在籍中（`is_active`）。
2. 送迎の日時が「今（日本時間）＋10分」より後で、`max_advance_days` 以内。日本時間は `now() at time zone 'Asia/Tokyo'` で求める。
3. 時刻が `get_pickup_slots` の返す、選べる時刻のどれかである（2.4 の条件を DB 側でもう一度確かめる）。
4. 同時に送信されても定員を超えないよう、`pg_advisory_xact_lock` でその日の予約処理を1件ずつにする。
5. その日に公開済みの「休暇」「休講」の予定があれば受け付けない（既存の `events` を参照）。

### 2.3 車1台の制約
便どうしの時間が重ならないことを、**DBの排他制約**で保証します（画面のチェックだけに頼らない）:

```sql
alter table public.pickup_groups add constraint pickup_groups_no_overlap
  exclude using gist (
    tsrange(pickup_date + approved_time,
            pickup_date + approved_time + make_interval(mins => trip_minutes)) with &&
  ) where (status <> 'cancelled');
```
承認（1人の便を作る）でも、相乗り調整（便の時刻を決める）でも、重なる場合は「17:00 の便と重なります」というエラーになります。

### 2.4 選べる時刻（`get_pickup_slots`）
その曜日の有効な時間帯を `slot_minutes` 刻みにした各時刻について:
- **すでに確定した便の時刻と同じ** → 「相乗り便・残り N 名」として表示（満席なら選べない）。
- **確定した便の走行中の時間と重なる** → 出さない（車が空いていない）。
- それ以外 → その時刻の未承認の予約数が定員未満なら選べる。
- 今から10分以内の時刻は出さない。

未承認の予約どうしが重なることはありえますが、それは管理者が「承認」か「相乗り調整」で解決します（どちらでも 2.3 の制約が効きます）。

### 2.5 トリガー
- `updated_at` の自動更新、変更履歴（`log_audit()` を送迎・生徒の各テーブルに付ける）。
- 状態遷移のチェック：`pending→approved/rejected/cancelled`、`approved→cancelled` 以外は拒否。
- 打診の確定：同じ便の打診が全員 `accepted` になったら、全員の予約を `approved`（`approved_time = proposed_time`）にし、便を `confirmed` にする。1人でも `declined` なら便は `proposing` のまま残し、管理画面で「要対応」と表示。期限（10分前）を過ぎた `waiting` は `expired` 扱い。
- 通知の起点：予約・打診の変更で `pickup-notify` を呼ぶ（Database Webhook）。
- 期限切れ：`pg_cron` で5分ごとに `expire_pickups()` を実行し、送迎時刻を過ぎた `pending` を `rejected`（`reject_reason = '期限切れ'`）にする。期限を過ぎた打診は `expired` にする。

---

## 3. 利用者の画面（`pickup.html`）

### 3.1 初回の登録（本番）
1. 管理者が「生徒」タブで生徒を登録し、**登録コード**（8桁、有効期限14日、1回だけ使える）を発行して、紙やLINEで生徒に渡す。
2. 生徒が碩学館の LINE 公式アカウントを友だち追加 → リッチメニューの「送迎予約」を押す → LIFF で `pickup.html` が開く。
3. 結び付いた生徒がいなければ、登録コードの入力画面が出る → 入力すると、そのLINEアカウントとその生徒が結び付く。

開発時は、LINE ログインの代わりに、初回だけ登録コードとメールアドレスを入力して結び付け、以後はメールアドレスで使います（本番では無効）。

### 3.2 予約
1. **日付**：`<input type="date">`。送迎のない曜日を選んだら「この日は送迎がありません」と表示。
2. **時刻**：`get_pickup_slots` の結果をボタンで並べる（例：`17:00 相乗り便・残り1`、`17:30`）。
3. **備考**（任意）。乗車場所は「勝瑞駅」と固定で表示。
4. **確認** →「この内容で予約する」→「予約を受け付けました。管理者の承認をお待ちください」。
   送信時に埋まっていた場合は「その時刻は埋まりました」と出して時刻を読み直す。

### 3.3 自分の予約
今後の予約の一覧（状態つき）。10分前までは「キャンセル」できる。相乗りの打診が来ていれば、ここにも「17:10 に変更してよい／できない」のボタンを出す。

---

## 4. 管理画面

### 4.1 「送迎予約」タブ
- 絞り込み：日付（1日 または 期間）、ステータス。タブ名に未承認の件数（例：`送迎予約 (3)`）。10分前が期限なので、開いている間は **Supabase Realtime** で新しい予約をすぐ反映し、音か画面表示で知らせる。
- 一覧：チェック／日付／希望時刻／確定時刻／生徒名（学年）／電話／備考／ステータス／操作。
  - ステータスの色：未承認＝黄、調整中＝青、承認＝緑、却下＝灰、キャンセル＝赤（文字でも表示する）。
  - 「承認」：希望時刻のまま、または時刻を直して承認 → 1人の便を作る。**すでにある便に入れる**こともできる（同じ時刻・空きありなら確認なしで承認）。
  - 「却下」：理由を選ぶ（例：満席、時間外、その他）→ 利用者に通知。
- 複数選択：既存の「予定」タブの選択バーの作りを流用。**同じ日付の予約だけ**選べる。選択バーに「相乗り調整」ボタン。
- その日の便の一覧を、上部に時間軸で表示（便の所要時間の帯つき）。空いている時間がひと目で分かるようにする。

### 4.2 相乗り調整ダイアログ
- 選んだ予約の一覧（名前・希望時刻・電話）、`定員 3 名中 2 名`。定員を超えると提案できない。
- **共通時刻の提案**（`pickup-common.js` の `suggestTime`）:
  - 候補の範囲 ＝ `[一番遅い希望 − 許容]` 〜 `[一番早い希望 ＋ 許容]` を、送迎時間帯の中に収め、ほかの便と重ならない時刻だけに絞り、5分刻みにする。
  - 例：17:00 と 17:15、許容10分 → **17:05〜17:10**。初期値は範囲の中央を5分に丸めた 17:10。
  - 範囲が空なら「許容10分以内の共通時刻がありません」と表示し、手動入力だけにする。
- 時刻を決めて「提案を送る」→ 便（`proposing`）と、予約ごとの打診を作る。希望時刻と同じ人は最初から `accepted`。
- 送迎まで時間がないときは、回答を待たず「電話で確認済みとして確定」もできるようにする（10分前まで受け付けるため）。
- 辞退があった場合は「時刻を変えて再提案」「辞退した人を外して確定」「調整を取りやめる」を選べる。

### 4.3 「送迎設定」タブ
- 曜日ごとの時間帯（追加・編集・有効/無効。「月〜金に 16:00-21:00」のようにまとめて入力するボタン）。
- 定員、時刻の刻み、1便の所要時間、許容のずれ、受付期限、何日先まで、管理者への通知先。

### 4.4 「生徒」タブ
- 生徒の登録・編集・在籍/退塾の切り替え（退塾してもデータは消さない）。
- 登録コードの発行（その場で一度だけ表示。再発行すると前のコードは使えなくなる）。
- 結び付いている LINE アカウント（表示名）の一覧と、結び付けの解除。

### 4.5 スケジュール画面との連携（「予定」タブ）
- `refreshEvents()` で、その月の確定した便も読み、日付・時刻順に**読み取り専用の行**として混ぜて表示する。
  - 種別の欄：「🚗 送迎」チップ（色は admin.css に固定。`event_types` には追加しない）。
  - 内容：`送迎 田中さん, 鈴木さん（2名）`、時間：`17:10–17:40`（便の所要時間）。
  - チェックボックスは出さない（一括操作・CSV の対象外）。操作は「送迎予約で開く」だけ。
- `$("ev-list")._rows` には入れないので、既存の一括操作のコードには影響しません。

---

## 5. 通知

### 5.1 仕組み
```
[DB] 予約・打診の INSERT / UPDATE
  └→ Database Webhook → Edge Function pickup-notify
       ├ APP_ENV=dev  → Resend でメール（開発者のアドレスにだけ届く）
       └ APP_ENV=prod → LINE Messaging API でプッシュ通知（その生徒に結び付いた全LINEに送る）
[LINE] ボタンを押す／友だち追加 → Edge Function line-webhook（署名 X-Line-Signature を確認）
```
- LINE のチャネルシークレット・アクセストークン・Resend の API キー・service_role キーは、**Edge Function の Secret にだけ**置きます（`config.js` や Git には入れない。既存の方針どおり）。
- **LINE ログイン（LIFF）のチャネルと Messaging API のチャネルは、LINE Developers の同じプロバイダーの下に作ってください。** プロバイダーが違うと、同じ人でもユーザーIDが別になり、通知が送れません。

### 5.2 利用者への通知

| きっかけ | 内容 |
|---|---|
| 予約の送信 | 送らない（画面に表示するため。通数の節約） |
| 承認 | 「ご予約が承認されました。1/5（月）17:10 勝瑞駅」 |
| 却下 | お断りと理由 |
| 期限切れ | 「承認が間に合いませんでした」と、直接の連絡のお願い |
| 相乗り打診 | 「ほかの生徒との相乗りのため、17:10 に変更できますか？」＋［変更してよい］［できない］ボタン |
| 相乗りの確定 | 確定した時刻 |
| 管理者によるキャンセル | 取り消しの連絡 |

**LINE の通数**：無料プラン（コミュニケーションプラン）は**月200通まで**です。予約が1日2〜4件（月およそ50〜100件）の場合の目安:

| 通知 | 月の通数（目安） |
|---|---|
| 承認・却下・期限切れ（1予約に1通） | 50〜100 |
| 相乗りの打診と確定（相乗りが2割、1組2人として） | 20〜40 |
| **合計** | **70〜140** |

無料枠に収まる見込みですが、忙しい月は近づきます。そこで:
- ボタンへの応答（「回答を受け付けました」）は無料の返信（reply）で送る。打診に最後に回答した人への確定の連絡も reply にする。
- 管理画面の「送迎設定」に**今月の送信数**（LINE の API で取得できる）を表示し、180通を超えたら警告する。
- 超えそうな月が続くようなら、有料プラン（ライトプラン：月5,000通）に切り替える。
- 無料枠を超えるとプッシュ通知が送れなくなる（エラーになる）ので、`pickup_notifications` に失敗として残し、管理画面に「未送信の通知があります」と出す。

### 5.3 管理者への通知
新しい予約（10分前まで来る）・打診への回答・利用者のキャンセルを、**すぐ**知らせます。
- 管理画面を開いている間：Realtime で画面に表示（4.1）。
- 閉じているとき：管理者のメールに送る（Resend。独自ドメインが無くても、Resend に登録した自分のアドレスには届く）。LINE で受けたい場合は、管理者のLINEも1つ結び付ければ送れますが、月200通の枠を使います。

---

## 6. バックアップ（送迎データ）

既存の週次バックアップは anon キーで**公開分だけ**を読む仕組みなので、送迎データ（生徒名・電話・LINE ID）は含まれません。含めてしまうと、既存の「公開分だけだから見られても問題ない」という前提が崩れるため、**別の仕組み**にします。

- **読み取り専用のバックアップ用ユーザー**を Supabase Auth に作り、`backup_readers` テーブルに登録したユーザーだけが送迎・生徒のテーブルを select できる RLS ポリシーを足す。
  → GitHub Actions はこのユーザーでログインして読む。**service_role キーは使わない**（既存の方針どおり）。
- 取り出した JSON を **age で暗号化**してから、`backup` ブランチの `backups/pickup/` に保存する。暗号化の公開鍵はリポジトリに置き、復号用の秘密鍵は管理者が手元（パスワードマネージャーなど）にだけ保管する。
  （リポジトリは非公開のようですが、共同作業者やフォークからの漏れを防ぐため、暗号化をおすすめします）
- 保存前の検証は、既存の `backup-lib.mjs` と同じ考え方（件数の一致、急減チェック）で行う。こちらは件数が減らないはずなので、減ったら失敗にする。
- データは削除しないので、年数とともに増えますが、1件数百バイトなので、無料枠（DB 500MB）を気にする必要はありません。

---

## 7. フェーズごとの作業と完了の確認

| フェーズ | 作業 | 完了の確認 |
|---|---|---|
| **1. テーブル・RLS** | `pickup.sql`（2章すべて）、README の手順 | anon で送迎・生徒のテーブルが読めない／書けない。便を重ねて作ると排他制約のエラーになる。禁止した状態遷移が拒否される |
| **2. 生徒名簿・予約フォーム（開発モード）** | 「生徒」タブ、`pickup-api`（登録コードでの本人確認）、`pickup.html` の予約と自分の予約 | 在籍していない生徒・期限切れのコードでは予約できない。10分前を過ぎた時刻は出ない。2つのブラウザから最後の1席を取ると、片方だけ成功する |
| **3. 予約一覧・承認** | 「送迎予約」「送迎設定」タブ、未承認バッジ、Realtime | 承認・却下・キャンセルができ、変更履歴に残る。重なる便は承認できない |
| **4. スケジュール反映** | 「予定」タブの読み取り専用行 | 閲覧ページ・CSV書き出し・公開用バックアップに送迎が**出ない** |
| **5. 相乗り調整** | ダイアログ、`suggestTime`、打診と確定のトリガー、回答画面 | `pickup.test.mjs`：17:00＋17:15 → 17:05〜17:10、範囲が空、時間帯の端、ほかの便と重なる場合。全員承認で自動確定する |
| **6a. 通知（開発：メール）** | `pickup-notify`、Webhook、Resend、`pickup-respond.html`、通知の記録と再送 | 各通知が開発者のアドレスに届く。リンクを開いただけでは回答が確定しない |
| **6b. 通知（本番：LINE）** | LINE 公式アカウント・LIFF・Messaging API の設定、LIFF での本人確認、`line-webhook`、プッシュ通知 | 登録コードでLINEと結び付く。LINEのボタンで回答できる。署名のないWebhookが拒否される。`APP_ENV=prod` では登録コードだけの予約が拒否される |
| **7. 送迎データのバックアップ** | バックアップ用ユーザー、暗号化バックアップ、検証とテスト、README に復号と復元の手順 | 暗号化されたファイルだけが保存され、秘密鍵で復号して件数が一致する |

---

## 8. 決定事項の記録

| 質問 | 回答 |
|---|---|
| 送迎の向き | 勝瑞駅 → 碩学館のみ |
| 1便の所要時間 | 約15分（`trip_minutes = 15`） |
| LINE を使う人 | 生徒本人 |
| LINE 公式アカウント | あり。予約は1日2〜4件 → 無料枠（月200通）で運用し、送信数を監視する |
| 期限切れの予約 | 自動で「却下（期限切れ）」にする |
| 0章・各章の提案 | すべて採用 |
