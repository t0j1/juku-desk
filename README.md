# 碩学館 年間スケジュール

Cloudflare Pages（静的サイト）＋ Supabase（DB・ログイン）で動く、年間スケジュールの閲覧サイトです。
閲覧は誰でも可能、編集できるのは管理者1人だけです。自前サーバーは使いません。

```
public/                 ← Cloudflare Pages で公開するフォルダ
  index.html            閲覧ページ
  admin.html            管理画面
  css/  js/             （js/config.js に URL と anon キーを設定）
supabase/
  schema.sql            テーブル・RLS・トリガー（全部入り）
  seed.sql              初期データ（2027年1月＋冬期休暇）
keepalive-worker/       Supabase の自動停止を防ぐ cron Worker
scripts/backup.mjs      自動バックアップ本体（検証つき）／backup-lib.mjs 検証ロジック／backup.test.mjs テスト
.github/workflows/      週1回の自動バックアップ（GitHub Actions）
```

> ⚠ **service_role キーは絶対に** `config.js` や Git に入れないでください。
> フロントに置くのは Project URL と **anon（公開）キー**だけです。
> データの保護は、anon キーが公開されても大丈夫なように RLS（`schema.sql`）で行っています。

---

## 手動セットアップ手順（この順番で）

### 1. Supabase プロジェクトを作る
1. <https://supabase.com> にログインし「New project」。
2. 名前・DB パスワード・リージョン（Tokyo 推奨）を決めて作成（数分かかります）。

### 2. `schema.sql` を実行する
1. 左メニュー **SQL Editor** →「New query」。
2. `supabase/schema.sql` の中身をすべて貼り付けて **Run**。
3. エラーが出なければ完了です（何度実行しても壊れません）。

### 2-b. 送迎予約を使う場合：`pickup.sql` を実行する
1. SQL Editor で `supabase/pickup.sql` の中身をすべて貼り付けて **Run**（`schema.sql` のあとに。何度実行しても壊れません）。
2. 期限切れの予約を自動で「却下（期限切れ）」にするため、pg_cron を使います。
   実行結果に「pg_cron の登録に失敗しました」と出た場合は、**Integrations → Cron** で有効にしてから、もう一度実行してください。
3. 設計は `docs/pickup-plan.md`。テストは次のとおりです。
   - DB だけ（手元）: `npm i --no-save @electric-sql/pglite && node scripts/pickup-db.test.mjs`
   - Edge Function の本体・共通時刻の提案（手元）: `node --test scripts/pickup-api.test.mjs scripts/pickup-common.test.mjs`
   - 通しのテスト（開発用 Supabase に対して。生徒2人の登録 → 予約 → 相乗り → 確定 → 後片付け）:
     `.env.dev` に開発用の `ADMIN_EMAIL=` と `ADMIN_PASSWORD=` を書いてから `node scripts/pickup-e2e.mjs`（`.env.dev` は Git に入りません）

### 2-c. 欠席連絡・振替授業を使う場合：`absence.sql` を実行する
1. SQL Editor で `supabase/absence.sql` の中身をすべて貼り付けて **Run**（`pickup.sql` のあとに。何度実行しても壊れません）。
2. 設計と決定事項は `docs/absence-plan.md`。テストは次のとおりです。
   - DB だけ（手元）: `npm i --no-save @electric-sql/pglite && node scripts/absence-db.test.mjs`
   - 通しのテスト（開発用 Supabase に対して。欠席 → ストック → 振替の申請 → 承認 → 取り消し → 後片付け）: `node scripts/absence-e2e.mjs`

### 3. 管理者ユーザーを作る
1. **Authentication → Users → Add user → Create new user**。
2. 自分のメールアドレスと強いパスワードを入力し、**「Auto Confirm User」にチェック**して作成。
3. 作成されたユーザーの **UID**（UUID）をコピー。
4. SQL Editor で次を実行（UID を貼り替える）:
   ```sql
   insert into public.admins (user_id) values ('ここにUID');
   ```
   `admins` に登録されたユーザーだけが編集できます。これは SQL Editor からしかできません（画面やAPIからは登録不可）。

### 4. 新規登録を無効にする（重要）
**Authentication → Sign In / Providers**（旧「Providers」）を開き、
**「Allow new users to sign up」をオフ**にして保存します。
※ 画面の文言はダッシュボードの更新で変わることがあります。「サインアップ」に関する項目を探してください。

これで、外部の人がアカウントを作ることはできません。仮に作られても `admins` に無いユーザーは何もできない設計です。

### 5. 初期データを入れる（任意）
SQL Editor で `supabase/seed.sql` を実行します。**1回だけ**実行してください（2回だと重複します）。
2027年1月の授業（高3=月木、高1=火金、高2=水土）、1/29・30 の休講、12/29〜1/4 の冬期休暇が入ります。
授業時間 18:30〜21:40 は仮の値です。管理画面で修正してください。

### 6. `public/js/config.js` を設定する
**Project Settings → API** から次の2つをコピーして書き換えます。

```js
const SUPABASE_URL = "https://xxxxxxxx.supabase.co";   // Project URL
const SUPABASE_ANON_KEY = "eyJ...";                    // anon / public キー
```
**service_role キーは使わない・書かない**でください。

### 7. 動作確認（ローカル）
```
python -m http.server 8000 -d public
```
- <http://localhost:8000/> … 予定が見えること
- <http://localhost:8000/admin.html> … 作成したメール／パスワードでログインできること

### 8. Cloudflare Pages にデプロイする
**GitHub 連携の場合**
1. このフォルダを GitHub にプッシュ。
2. Cloudflare ダッシュボード **Workers & Pages → Create → Pages → Connect to Git**。
3. ビルド設定: **Framework preset: None / Build command: 空 / Build output directory: `public`**。
4. 「Save and Deploy」。

**直接アップロードの場合**: 「Upload assets」で `public` フォルダをドラッグ＆ドロップ。

デプロイ後、公開 URL の `/admin.html` でログインできることを確認してください。

### 9. アクセス制限の確認（推奨）
ブラウザの開発者ツール、または次の `curl` で、未ログインでは書き込めないことを確認します。
```
curl -X POST "https://xxxxxxxx.supabase.co/rest/v1/events" \
  -H "apikey: <anon キー>" -H "Authorization: Bearer <anon キー>" \
  -H "Content-Type: application/json" \
  -d '{"event_date":"2027-01-01","type":"休講"}'
```
`new row violates row-level security policy`（または 401/403）が返れば正常です。

### 10. キープアライブ Worker をデプロイする
Supabase の無料プランは、約1週間アクセスがないとプロジェクトが停止します。
3日おきに `events` を1件読む Worker で、これを防ぎます。

```
cd keepalive-worker
# wrangler.toml の SUPABASE_URL を自分の Project URL に書き換える
npx wrangler login
npx wrangler secret put SUPABASE_ANON_KEY     # プロンプトに anon キーを貼り付け
npx wrangler deploy
```
- cron は `wrangler.toml` の `crons = ["0 3 */3 * *"]`（3日おき 03:00 UTC）。
- デプロイ後、Cloudflare ダッシュボード → Workers → `sekigaku-keepalive` → **Logs** で `keepalive: 200` を確認できます。
  Worker の URL を開いても `{"ok":true,"status":200}` が返れば成功です。
- 手元での試験: `npx wrangler dev --test-scheduled` → `curl "http://localhost:8787/__scheduled"`

---

## 自動バックアップ（GitHub Actions）

毎週日曜 23:00（日本時間）に、`events` と `event_types` を読み出して、このリポジトリの **`backup` ブランチ**の `backups/` に保存します。
手動実行もできます。使うのは `SUPABASE_URL` と **anon キーだけ**です（service_role は使いません）。

- 保存ファイル（直近12回分を残し、古いものは自動削除）
  - `backup-YYYY-MM-DD.csv` … 予定。**管理画面の CSV 読み込みでそのまま使える形式**
  - `backup-YYYY-MM-DD.json` … 予定と種別（色）の両方
  - `backup-YYYY-MM-DD.event_types.csv` … 種別と色
- `backup` ブランチは `main` と履歴が別で、`public/` を含みません。サイトとして公開されることはありません。
- **保存前に自動検証し、1つでも問題があれば、何も保存せず失敗として終了**します。失敗すると GitHub から通知メールが届きます。
  既存のバックアップは、失敗時に1バイトも変わりません（検証を通ったものだけを `backups/` に移す方式）。
  1. **件数**: DB へ別クエリで問い合わせた総数 ＝ 取得件数 ＝ JSON の件数 ＝ CSV の行数
  2. **CSV の往復**: 書き出した CSV を、管理画面と同じ解析関数（`public/js/common.js`）で読み直し、全行が元データと一致するか
  3. **形式**: 日付・時刻の形式、終了が開始より前でないか、`events.type` が `event_types` に存在するか、色の形式
  4. **急減**: 直前のバックアップの件数の**半分以下**に減っていたら失敗（0 件や API エラーもここで失敗）
- 検証の仕組み自体もテストしています（`scripts/backup.test.mjs`）。ワークフローの最初にこのテストが走り、通らなければバックアップは実行されません。
  手元で試すには: `node --test scripts/backup.test.mjs`
- 意図してデータを大きく減らした（例：年度替わりで予定を整理した）後は、急減チェックで失敗することがあります。その場合は、`backup` ブランチの `backups/` から直近の古い日付のファイルを削除するか、件数が回復してから再実行してください。
- ⚠ **下書きはバックアップされません。** anon キーで読めるのは「公開」の予定だけだからです。下書きも残したいときは、管理画面の CSV タブから手動で書き出してください（下書きも含まれます）。
- ⚠ リポジトリが Public の場合、`backup` ブランチも誰でも見られます。中身は公開サイトに表示されている内容と同じ（公開分のみ）です。

### A. GitHub Secrets を登録する
1. GitHub のリポジトリ → **Settings → Secrets and variables → Actions → New repository secret**。
2. 次の2つを登録します。
   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | Project URL（例 `https://xxxx.supabase.co`。末尾に `/rest/v1` は付けない） |
   | `SUPABASE_ANON_KEY` | anon（publishable）キー。**service_role は入れない** |

### B. Cloudflare Pages の設定を確認する（重要）
`backup` ブランチがプレビューとして公開・ビルドされないようにします。
Cloudflare → 該当の Pages プロジェクト → **Settings → Builds → Branch control** で、
Production branch を `main` にし、**Preview branches は「None」**（または `main` だけ）にしてください。
（`backup` に `public/` は無いので、ビルドしても公開はされず、失敗通知が出るだけです。それを避けるための設定です。）

### C. 初回の手動実行と確認
1. GitHub → **Actions** タブ → 左の **Weekly backup** → **Run workflow** → `main` を選んで実行。
   （初回に「ワークフローを有効にする」ボタンが出たら押します。）
2. 1分ほどで緑のチェックになれば成功です。赤なら、実行をクリックして、どの手順で失敗したかを確認します。
   - `SUPABASE_URL` / `SUPABASE_ANON_KEY を設定してください` … Secrets の名前や登録漏れ
   - `HTTP 401` … anon キーの間違い
   - `検証エラー …` … 検証に失敗（上の 1〜4 のどれか。メッセージに内容が出ます）。既存のバックアップは無傷です
   - `0 件` … 公開の予定が1件もない（意図通りの停止です）
3. リポジトリのブランチ切り替えで **`backup`** を選び、`backups/` に `backup-日付.csv / .json / .event_types.csv` があることを確認します。
   件数はログの `backup-日付: events=N, event_types=M` でも見られます。

### D. バックアップからの復元
1. GitHub の `backup` ブランチ → `backups/` → 戻したい日付の **`backup-YYYY-MM-DD.csv`** を開き、**Download raw file**（またはダウンロードボタン）で保存します。
2. 管理画面（`/admin.html`）にログイン → **CSV** タブ。
3. **先に、いまのデータを「全予定をCSVで書き出す」で保存**しておきます（念のため）。
4. 「CSV の読み込み」で、保存したファイルを選びます。
   - 予定をまるごと戻す → **「既存の予定をすべて削除して置き換える」にチェック** → 「読み込む」→ 確認で「全削除」と入力。
   - 足りない分だけ追加する → チェックなしで「読み込む」（同じ予定が重複しないよう注意）。
5. **予定はすべて「公開」として復元されます**（バックアップが公開分のみのため）。下書きにしたいものは、管理画面で切り替えてください。
6. 種別の色を戻したい場合は、`backup-YYYY-MM-DD.json`（または `.event_types.csv`）の色を見て、管理画面の **「種別の色」** タブで設定します。
   （種別そのものを消してしまった場合は、`supabase/schema.sql` の最後の `insert` を再実行すると初期の8種別が戻ります。）

### keepalive-worker との関係（役割が重なります）
どちらも Supabase に読み取りアクセスを行うため、**バックアップ自体が「アクセスあり」として、自動停止（約1週間アクセスなしで停止）の防止にも働きます**。ただし、次の理由で `keepalive-worker` は残すことをおすすめします。

| | keepalive-worker | 自動バックアップ |
|---|---|---|
| 目的 | Supabase の自動停止を防ぐ | データの保管 |
| 頻度 | 3日おき | 週1回 |
| 停止の余裕 | 十分 | 週1回だと余裕が少ない。Actions が遅れる・失敗すると間に合わない |

- GitHub の仕様で、リポジトリに動きがない状態が **60日**続くと、定期実行が自動で無効になることがあります。Actions タブに「無効になった」表示が出たら、再度有効にしてください。
- 定期実行は、混雑時に数十分遅れることがあります。

---

## 日々の使い方（管理画面）

| タブ | できること |
|---|---|
| 予定 | 月ごとの一覧。追加・編集・削除、公開/下書きの切り替え。**複数選択して一括編集・一括の公開/下書き切り替え・一括削除**（下記） |
| 繰り返し登録 | 曜日と期間を指定して一括登録（例：毎週 月・木 に高3授業を 4/1〜3/31）。除外日の指定可 |
| 期間登録 | 期間内の毎日を登録（冬期休暇・講習期間など）。日曜を除く指定可 |
| 種別の色 | 種別ごとの色を変更 |
| CSV | 全予定の書き出し（バックアップ）／読み込み（復元） |
| 変更履歴 | いつ・何が・どう変わったか（変更前後）。トリガーで自動記録 |

- **複数選択と一括操作**（「予定」タブ）
  - 各行の左端のチェックで選択します。見出しのチェックで、その月を全部選択・解除できます。
  - 種別のチップ（色付きの部分）をクリックすると、その月の同じ種別の予定をまとめて選択します（もう一度押すと解除）。
  - 選択すると、上に「選択中: X件」のバーが出ます。
    - **一括編集**: 同じ種別だけ編集できます（種別が混ざっているとエラー）。開始時刻・終了時刻・内容・備考・公開状態のうち、「変更する」にチェックした項目だけが反映されます。
    - **公開/下書き切り替え**: 下書きが1件でも混じっていれば全部「公開」に、全部公開なら全部「下書き」に揃えます。
    - **一括削除**: 元に戻せません（変更履歴には残ります）。
  - 月を切り替えると選択は解除されます。すべての操作の前に確認が出て、終わると件数が表示されます。
- 削除・一括登録・置き換えの前には確認ダイアログが出ます。
- 下書きの予定は、管理画面でしか見えません（閲覧ページには出ません）。
- 誤って消しても、変更履歴に変更前のデータが残ります。

### バックアップ（重要）
週1回の自動バックアップ（上の「自動バックアップ」）は**公開分のみ**です。下書きも含めて残したいときは、**CSV タブから書き出して**保管してください。
復元は「CSV の読み込み」で「既存の予定をすべて削除して置き換える」を使います
（実行前に現在のデータが自動でCSVとして書き出されます）。
書き出されるのは予定のみです。種別の色は `schema.sql` の初期値に戻せば再現できます。

### CSV の形式
```
日付,種別,内容,開始時刻,終了時刻,備考,公開
2027/1/5,高1授業,高1授業,18:30,21:40,,公開
```
種別は 高1授業／高2授業／高3授業／自習／日曜自習室／講習／休講／休暇 のいずれか。
1行でも不正があると、何も変更せずにエラーを表示します。

## セキュリティの仕組み（要点）
- 全テーブルで RLS 有効。未ログイン（anon）は公開済みの予定と種別の読み取りのみ。
- 編集は `admins` テーブルの user_id だけ（`is_admin()`）。`admins` への登録は SQL Editor のみ。
- `audit_log` は管理者のみ閲覧可、書き込みはトリガー専用（誰も直接書けません）。
- 管理画面のログインチェックは見た目のもので、本当の防御は DB 側の RLS です。
