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

## 日々の使い方（管理画面）

| タブ | できること |
|---|---|
| 予定 | 月ごとの一覧。追加・編集・削除、公開/下書きの切り替え |
| 繰り返し登録 | 曜日と期間を指定して一括登録（例：毎週 月・木 に高3授業を 4/1〜3/31）。除外日の指定可 |
| 期間登録 | 期間内の毎日を登録（冬期休暇・講習期間など）。日曜を除く指定可 |
| 種別の色 | 種別ごとの色を変更 |
| CSV | 全予定の書き出し（バックアップ）／読み込み（復元） |
| 変更履歴 | いつ・何が・どう変わったか（変更前後）。トリガーで自動記録 |

- 削除・一括登録・置き換えの前には確認ダイアログが出ます。
- 下書きの予定は、管理画面でしか見えません（閲覧ページには出ません）。
- 誤って消しても、変更履歴に変更前のデータが残ります。

### バックアップ（重要）
無料プランには自動バックアップがありません。**CSV タブから定期的に書き出して**保管してください。
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
