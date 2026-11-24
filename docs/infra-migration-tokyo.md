# Vercel + Supabase を東京に作り直す手順書

対象: Web 管理画面 `~/programs/nobilva_study_plan` (Next.js) と iOS アプリ (このリポジトリ)
目的: 別の人の組織にある Vercel / Supabase を、自分のアカウントの **Vercel hnd1 (東京) + Supabase ap-northeast-1 (東京)** に作り直す。データも移す。

> この手順書は秘密情報を含みません。`<...>` は自分で埋めるプレースホルダです。
> パスワードやキーはシェル履歴に残らないよう、`read -s` で読み込むか `.env.migration` (git 管理外) に書いてから `source` してください。

---

## 0. まず現状をつかむ (なぜ遅いのか)

分かっている事実:

- **今の Supabase はムンバイ (ap-south-1)**。`lib/supabase/env.ts` に「ap-south-1 (Mumbai) までの往復は 100〜150ms」とあり、タイムアウトを 10 秒に延ばしている。
- **本番の関数もムンバイ (bom1) で動いている** (2026-11-06 に計測)。`vercel.json` に `regions` の指定はないので、ダッシュボードで bom1 に設定されている。

```bash
curl -sI https://studyplan.nobilva.jp/login | grep -i x-vercel-id
# x-vercel-id: hnd1::bom1::...   ← 入口のエッジは東京 (hnd1)、関数はムンバイ (bom1)
```

`x-vercel-id` は「入口のエッジ::関数のリージョン::ID」の形です。

### この結果から言えること

**本番では、関数と DB はどちらもムンバイにあり、すでに近くに置かれています。** そのため DB への 1 往復は数 ms で、「クエリの往復が積み重なって数十秒」という説明は本番には当てはまりません。

- 東京に移して減るのは、**利用者 ↔ ムンバイの往復 (1 リクエストあたり約 100〜150ms)** です。体感は少し軽くなりますが、数十秒が 1 秒になるような変化は**期待できません**。
- ローカル (`next dev`) で計ったときにページのサーバー処理が 6〜26 秒かかったのは、**手元の PC (日本) → ムンバイの DB** でクエリごとに 100〜150ms かかるためです。本番の関数はムンバイにあるので、この数字は本番には当てはまりません。ただし、DB を東京に移すとローカル開発は大きく速くなります。
- 本番で「メモ・テスト登録に数十秒」かかる原因は、**距離以外にある可能性が高い**です。移行の前に、下の「本番が遅い原因を探す」を先に行うことをすすめます。

### 本番が遅い原因を探す (移行より先に)

1. **Vercel の関数ログ**: Vercel → Logs で、遅かった操作 (server action の POST) の Duration を見る。10 秒前後で止まっていれば、`supabaseFetch` の 10 秒タイムアウトか、Hobby プランの関数の時間制限に当たっている。
2. **コールドスタート**: しばらく使われていないと関数が止まり、最初の 1 回が数秒遅くなる。2 回目以降も遅いかどうかで切り分けられる。
3. **Supabase の計算資源**: Dashboard → Reports → Database で CPU・メモリ・ディスク IO を見る。Free / Nano / Micro は IO の上限に当たると急に遅くなる (Disk IO Budget を使い切ると数十秒単位で詰まることがある)。
4. **遅いクエリ**: Dashboard → Reports → Query Performance。RLS のサブクエリにインデックスがないと、データが増えるほど遅くなる。
5. **Supabase のステータス**: プロジェクトが一時停止から復帰した直後や、障害中ではないか。

原因が 3 (計算資源) なら、移行ではなくプランを上げることで直ります。

> **2026-11-06 確認: 今の compute は Nano** (Free プランの最小サイズ)。ただし下の計測で、数十秒の主な原因ではなさそうだと分かった。新しいプロジェクトは Pro プラン + Micro 以上で作ってください (手順 3)。Pro の月額に含まれる compute のクレジットで Micro はまかなえます。

### 使用量と応答時間の計測 (2026-11-06)

- 使用量 (Free プラン): DB 41MB / 500MB、月間アクティブユーザー 8 人、Egress 0.17GB。DB 全体がメモリ (0.5GB) に収まる大きさで、データ量は Nano でも十分小さい
- 手元 (日本) から旧本番の API に、DB まで届く軽いクエリ (RLS で 0 件) を送った結果:

| 送り方 | 応答時間 |
|---|---|
| 1 本ずつ 8 回 | 0.23〜0.42 秒 (ほぼムンバイまでの往復) |
| 25 本同時 | 中央値 0.57 秒、最大 1.17 秒 |
| 50 本同時 | 中央値 0.89 秒、最大 1.86 秒 |

- 同時に送ると少しずつ順番待ちになる (Nano の小ささは出ている) が、**秒単位で 10 秒を超えるような詰まりは起きない**。Nano は「少し遅くする」要因ではあっても、**数十秒の主な原因ではない**とみてよい
- 残る有力候補は、032 が入っていなかったことによる遅い経路 (1 人ずつの Auth 管理 API 呼び出しなど) と、Vercel 側 (関数のコールドスタート、保存後のページ全体の再描画)。032 を入れたあと、遅かった操作を Vercel → Logs で見て、1 回の処理時間を確かめる

### Supabase のログから分かったこと (2026-11-06 03:08〜04:05 UTC、487 行)

**本番 DB にマイグレーション 032 (`032_perf_email_and_chat_rpc.sql`) が入っていない。**

- `column profiles.email does not exist` (17 回) → 032 で足す `profiles.email` がない
- `POST /rest/v1/rpc/get_chat_unread_counts` が 404 (6 回) → 032 で作る RPC がない
- 032 は**表示を速くするためのマイグレーション**で、入っていないとコードは遅い代わりの方法 (フォールバック) で動く:
  - `getEmailMap` (`lib/actions/admin/shared.ts`): メールアドレスを `profiles` から 1 回で取れず、**ユーザー 1 人ずつ Auth の管理 API (`/auth/v1/admin/users/<id>`) を呼ぶ**。管理画面の一覧で人数分の通信が出る
  - `batchUnreadCounts` (`lib/actions/chat/shared.ts`): 未読数を RPC 1 回で取れず、**スレッドごとに件数を数えるクエリ** (`HEAD /rest/v1/chat_messages`) を出す。先生のナビを開くたびに担当生徒の人数分
  - `get_chat_last_messages` / `get_teacher_chat_threads` なども同じくフォールバックで動いている
  - 032 で作る `sync_profile_email_on_auth` トリガーもないので、`profiles.email` を前提にしたほかの処理も効いていない
- 一方で 035 (`apple_push_tokens`)、040〜042 (`teacher_memos` / `student_units` / `student_tests`) のテーブルはある。**SQL Editor で手で流したときに 032 だけ抜けた (または途中で失敗した)** と考えられる。ほかにも抜けがあるかもしれない

ほかに見つかったもの:

- `family_links?parent_id=in.(__none__)` が `invalid input syntax for type uuid` で 400 (`lib/actions/admin/parents.ts:22` など)。件数 0 のときの番兵に `"__none__"` を使っているが、uuid 列には入れられないので毎回エラーになる。結果は「0 件」と同じなので害は小さいが、無駄な往復とエラーログになる (正しくは、空なら問い合わせ自体をしない)
- エクスポートには応答時間が入っていないので、1 本ずつの遅さはこのログからは分からない。1 時間で約 420 リクエストと負荷は小さい。Postgres の checkpoint も数秒で終わっていて、ディスクが詰まっている様子はない

### どのマイグレーションが入っているか確かめる (読み取りだけ)

旧本番の SQL Editor で実行すると、マイグレーションごとに `true / false` が出ます。`false` の行が抜けているものです。

```sql
select m, ok from (values
  ('018 recovery_tokens',        to_regclass('public.recovery_tokens') is not null),
  ('019 rate_limits',            to_regclass('public.rate_limits') is not null),
  ('020 teams',                  to_regclass('public.teams') is not null),
  ('021 contract_states',        to_regclass('public.contract_states') is not null),
  ('022 sync_outbox',            to_regclass('public.sync_outbox') is not null),
  ('023 meetings',               to_regclass('public.meetings') is not null),
  ('025 tasks.scheduled_date',   exists(select 1 from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='scheduled_date')),
  ('026 must_change_password',   exists(select 1 from information_schema.columns where table_schema='public' and column_name='must_change_password')),
  ('028 tasks.notes',            exists(select 1 from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='notes')),
  ('029 student_busy_slots',     to_regclass('public.student_busy_slots') is not null),
  ('031 chat_messages.image_url',exists(select 1 from information_schema.columns where table_schema='public' and table_name='chat_messages' and column_name='image_url')),
  ('032 profiles.email',         exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='email')),
  ('032 get_chat_unread_counts', to_regproc('public.get_chat_unread_counts') is not null),
  ('032 get_teacher_chat_threads', to_regproc('public.get_teacher_chat_threads') is not null),
  ('033 password_enabled',       exists(select 1 from information_schema.columns where table_schema='public' and column_name='password_enabled')),
  ('034 plan_items.updated_at',  exists(select 1 from information_schema.columns where table_schema='public' and table_name='plan_items' and column_name='updated_at')),
  ('035 apple_push_tokens',      to_regclass('public.apple_push_tokens') is not null),
  ('036 cron meeting-notify',    exists(select 1 from cron.job where jobname='meeting-notify-5min')),
  ('037 push token per device',  exists(select 1 from pg_constraint where conname='apple_push_tokens_device_token_key')),
  ('040 teacher_memos',          to_regclass('public.teacher_memos') is not null),
  ('041 student_units',          to_regclass('public.student_units') is not null),
  ('042 student_tests',          to_regclass('public.student_tests') is not null),
  ('043 memo write policy',      exists(select 1 from pg_policies where policyname='Teachers manage linked student memos')),
  ('044 old memo policy dropped',not exists(select 1 from pg_policies where policyname='teacher_memos select linked teacher'))
) t(m, ok) order by m;
```

(001〜017 は、032 より新しいものが入っている以上まず入っているとみて省略。`cron` スキーマがないとエラーになるので、その場合は 036 の行を消して実行する)

> **2026-11-06 の判定結果 (旧本番)**: `false` は **032 (3 項目すべて) と 044** だけ。ほかはすべて `true`。

**直し方**: `false` になったマイグレーションのファイルを、番号順に SQL Editor で流す。032 は `ADD COLUMN IF NOT EXISTS` と `CREATE OR REPLACE`、`DROP TRIGGER IF EXISTS` が中心で、`profiles.email` の埋め戻しも `auth.users` から上書きするだけなので、何度流しても大丈夫な作りになっている。**移行の前でも、今の本番にすぐ入れてよい** (移行時は本番のスキーマをそのままダンプするので、先に直しておけば新しいプロジェクトにも入る)。移行で新しいプロジェクトに入れたあとにも、同じ SQL でもう一度確かめる。

### コードから見た原因の候補 (2026-11-06 調査)

メモ・テスト登録の処理 (`lib/actions/teacher-memos.ts` / `student-tests.ts`) そのものは軽く、権限確認 1〜2 本と INSERT 1 本だけです。重いのはそのあとです。

**1. 保存のたびに生徒詳細ページ全体を作り直している (確実)**

- 保存の最後に `revalidateStudentDetailPaths()` が `revalidatePath('/teacher/<id>')` を呼ぶ。server action の中で今のページを revalidate すると、Next.js は**同じレスポンスの中でページ全体を描画し直してから**返す。
- 生徒詳細ページ (`app/(teacher)/teacher/(with-sidebar)/[studentId]/page.tsx`) は描画のたびに、`Promise.all` で 12 個の関数 + 後続の 2 個を呼ぶ。中で複数回クエリする関数もあるので、**保存 1 回で Supabase への HTTP リクエストが 20〜25 本**になる。
- `MemoPanel` / `TestsPanel` は `startTransition` の中でこの全体を待つので、ページの描画が終わるまで「保存中」のまま。
- 関数と DB が近ければ、20〜25 本を並列で送っても普通は 1 秒程度で終わる。**数十秒になるのは、このうちどれかが詰まっているとき**です (次の 2)。

**2. どれかのリクエストが詰まり、10 秒単位で待たされている (有力、要確認)**

- `lib/supabase/env.ts` の `supabaseFetch` は 1 リクエスト 10 秒でタイムアウトする。さらに `withPgRetry` / `assertTeacherLinked` は 25P02 のとき 1 回やり直す。**「10 秒待つ → やり直す」が重なると 10 秒・20 秒・30 秒といった区切りのよい遅さになる**。計測した 6〜26 秒はこの形に近い。
- Supabase の API (PostgREST) は DB 接続を小さなプールで共有していて、空きがないと最大 10 秒待ってから `PGRST003` (504) を返す。小さい compute (Nano / Micro) では、1 回の描画で 20 本以上を同時に送ると、先生が 2〜3 人同時に使うだけでこのプールがあふれうる。
- コメントに残っている「pgbouncer の 25P02 (current transaction is aborted)」が API 経由で出るのも、DB 側が不安定になっているときに見られる症状です。
- 確かめ方 (どれも読み取りだけ。Supabase の SQL Editor / Logs で実行):

```sql
-- compute のサイズと接続数の上限
show max_connections;
select state, count(*) from pg_stat_activity group by state;

-- 平均が遅いクエリ (Database → Extensions で pg_stat_statements が有効なら)
select round(mean_exec_time) as ms, calls, left(query, 120) as q
  from pg_stat_statements order by mean_exec_time desc limit 15;
```

  - Logs → API (edge logs) で、ステータス 504 や `PGRST003` が出ていないか
  - Logs → Postgres で `canceling statement due to statement timeout` や `remaining connection slots are reserved` が出ていないか
  - Reports → Database で Disk IO の残り (IO Budget) が 0 に張り付いていないか
  - Settings → Compute and Disk で今のサイズ (Nano なら、Micro 以上に上げるだけで直る可能性がある)

**3. ローカルの 6〜26 秒は別の原因が混ざっている**

`next dev` は初めて開くページをその場でコンパイルするので、1 回目は数秒〜十数秒かかる。そこにムンバイまでの往復 (150ms × 直列の段数) が加わる。ローカルの数字は 2 回目以降で比べる必要がある。

### コード側でできる改善 (調査で原因が確定したら)

- **保存時にページ全体を作り直さない** (Web リポジトリのブランチ `claude/memo-tests-ux` のコミット 8c44d59 / 1ca629e / c7ddfe9 で対応済み。2026-11-06 時点では未マージ・未 push): メモ・テスト・単元の保存では `revalidatePath` をやめ、server action が保存した行を返し、パネル側の state をその場で更新する (`useOptimistic` を使えば押した瞬間に反映される)。ほかの画面は次に開いたときに新しいデータを取るので困らない。これで**保存 1 回のリクエストが 20〜25 本から 2〜3 本に減り**、プールがあふれる原因そのものも減る。
- タイムアウトで失敗したことを画面に出す (今は 10 秒待ったあと 0 件として表示されうる)。
- 移行後に関数と DB が東京にそろったら、`SUPABASE_FETCH_TIMEOUT_MS` を 3〜5 秒に戻す。東京への移行は**所有者を自分に移すついでに行う改善**として考えると、期待とずれません。

---

## 1. 依存の洗い出し (コードから確認した結果)

### Supabase に依存しているもの

| 種類 | 中身 | 移行で必要なこと |
|---|---|---|
| DB スキーマ | `supabase/migrations/001〜044` (テーブル 35 個、ポリシー 90 個、`auth.uid()` を使う箇所 99 か所) | `supabase db dump` でスキーマを丸ごと移す (本番の SQL Editor で直接変えた差分も含めるため) |
| auth.users のトリガー | `on_auth_user_created` (001/008)、`sync_profile_email_on_auth` (032) | **`auth` スキーマのトリガーはスキーマのダンプに入らない**ので、手で作り直す (手順 4-4) |
| Auth (パスワード) | `auth.users.encrypted_password` (bcrypt) | データのダンプで `auth` スキーマごと移せば**そのまま使える**。ユーザー ID も変わらない |
| Auth (パスキー) | `public.webauthn_credentials` に自前で保存 (`@simplewebauthn/server`)。ログイン時は `admin.generateLink` → `verifyOtp` でセッションを発行 | テーブルを移せばそのまま使える。**rpID は `NEXT_PUBLIC_APP_URL` のホスト名 (`studyplan.nobilva.jp`)** なので、ドメインを変えなければパスキーは全部引き継げる |
| Auth のセッション | Web: `sb-<ref>-auth-token` クッキー。iOS: access/refresh token を Keychain に保存し、`/api/v1/auth/mobile/session/refresh` 経由で更新 | 手順 9 を参照 (JWT 署名鍵が変わると一度ログアウトになりうる) |
| Storage | 公開バケット `chat-images` (チャット画像)。`chat_messages.image_url` に**旧プロジェクトの完全な URL** が入っている | ファイルをコピーし、`image_url` の URL を書き換える (手順 5) |
| Realtime | `chat_messages` を `supabase_realtime` publication に追加 (011)。Web の `useChatRealtime` / `ChatRoom` が `postgres_changes` を購読 | 新プロジェクトで publication に入っているか確認する |
| pg_cron + pg_net + Vault | `meeting-notify-5min` が 5 分ごとに `/api/dispatch/meeting-notify` を呼ぶ (036)。URL と `CRON_SECRET` は Vault に保存 | **Vault の暗号化はプロジェクトごとに別**なので、Vault を登録し直して 036 を再実行する |
| RPC | `get_student_total_unread` / `get_teacher_total_unread` など (032) | スキーマのダンプで移る |

### Vercel に依存しているもの

| 種類 | 中身 |
|---|---|
| ドメイン | `studyplan.nobilva.jp` (iOS の `APIClient.baseURL`、Associated Domains `webcredentials:` / `applinks:` もこのドメイン) |
| Cron | `vercel.json`: `/api/dispatch/sync-retry` (毎日 18:00 UTC)、`/api/dispatch/meeting-topup` (毎日 19:00 UTC)。`CRON_SECRET` で認証 |
| 環境変数 | 下の表 |

Web が参照している環境変数 (コードから抽出):

| 変数 | 移行時の扱い |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` | **新プロジェクトの値に変える** |
| `NEXT_PUBLIC_APP_URL` | `https://studyplan.nobilva.jp` のまま (パスキーの rpID になるので**変えない**) |
| `CRON_SECRET` | 引き継ぐ (新しい値にするなら Vault 側も同じ値にする) |
| `AUTH_COOKIE_SECRET` | 引き継ぐ (変えると、ログイン途中のパスキー challenge が失効するだけ。大きな影響はない) |
| `DASHBOARD_HMAC_SECRET` / `DASHBOARD_SYNC_URL` / `CONTRACT_FORM_HMAC_SECRET` | **引き継ぐ** (nectere_dashboard / nectere_contract_form 側と同じ値でないと連携が止まる) |
| `APNS_AUTH_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_BUNDLE_ID` / `APNS_ENV` | 引き継ぐ |
| `APPLE_APP_ID` / `ANDROID_APP_PACKAGE` / `ANDROID_APP_SHA256` / `WEBAUTHN_RP_NAME` / `WEBAUTHN_EXTRA_ORIGINS` | 引き継ぐ (`APPLE_APP_ID` がないと AASA が 404 になり、iOS のパスキーと Universal Links が壊れる) |
| `ADMIN_LOGIN_EMAIL` / `ADMIN_LOGIN_PASSWORD` / `ADMIN_NOTIFY_EMAIL` | 引き継ぐ |
| `RESEND_API_KEY` / `EMAIL_FROM` | 引き継ぐ (Resend のアカウントも前任者のものなら、別途移す) |
| `GEMINI_API_KEY` / `LINE_*` / `NEXT_PUBLIC_LINE_LIFF_ID` | 引き継ぐ (同上、発行元アカウントを確認) |
| `ALLOW_DEV_SEED` / `NEXT_PUBLIC_SUPABASE_DISABLED` | 本番では未設定のまま |

### iOS アプリ

- iOS は **Supabase に直接つないでいない**。すべて `https://studyplan.nobilva.jp/api/v1/...` 経由 (`NobilvaStudent/Networking/APIClient.swift`)。Supabase の URL や anon key はアプリに入っていない。
- → **ドメインを変えなければ、iOS アプリの作り直しもストア審査も不要**。

### 他のリポジトリとの連携

- `nectere_contract_form` → `NOBILVA_PROVISION_URL` / `NOBILVA_SYNC_URL` (nobilva の API を URL で呼ぶ) + `NOBILVA_HMAC_SECRET`
- `nectere_dashboard` → `NOBILVA_SYNC_URL` + `NOBILVA_HMAC_SECRET`
- どちらもドメイン経由なので、ドメインを変えなければ設定変更は不要。ただし**この 2 つの Vercel プロジェクトも前任者のアカウントにあるなら、同じ手順で移す必要がある** (contract_form は Vercel Postgres を使っているので別の移行になる)。

---

## 2. 全体の流れと停止時間

> **決定 (2026-11-09)**: Vercel・Supabase とも自分のアカウントで有料プランに加入済み。**Vercel は Transfer Project で移す、Supabase は東京で作り直す**。
>
> - Vercel を移した直後は、関数のリージョンを **bom1 (ムンバイ) のまま**にする。DB がムンバイにある間に hnd1 に変えると、関数 ↔ DB の往復が毎回 100ms 以上かかり、今より遅くなる。hnd1 への切り替えは、手順 7 で env を新しい Supabase (東京) に向けるのと**同じデプロイ**で行う。
> - Transfer なら env・ドメイン・Cron もまとめて移るので、手順 6-1 (Import と env の入れ直し) は不要。移したあと、プロジェクトが Pro のチームにあることと、Cron と env が残っていることだけ確認する。

```
[前日まで] 新 Supabase 作成 → スキーマ適用 → リハーサル移行 → 新 Vercel 作成・動作確認 (仮 URL)
[当日]     メンテナンス表示 → 最終データ移行 → Storage 差分コピー → env 切替・再デプロイ → ドメイン付け替え → 確認
```

- 書き込みを止めるのは「最終データ移行 〜 ドメイン付け替え」の間だけ。データ量が小さいので **15〜30 分程度** を見込む。
- 生徒が使わない時間帯 (平日の深夜など) を選ぶ。
- **旧 Supabase と旧 Vercel は 2 週間ほど消さずに残す** (ロールバック先)。

---

## 3. 新しい Supabase プロジェクトを作る

1. https://supabase.com/dashboard で**自分の組織**を作る (または既存の自分の組織を使う)。
2. New project → **Region: Northeast Asia (Tokyo) = ap-northeast-1**。DB パスワードはパスワードマネージャーに保存。
3. プラン: **Pro + compute Micro 以上**にする (今の旧プロジェクトは Nano で、遅さの最有力の原因。Free は 1 週間アクセスがないと一時停止し、日次バックアップもない)。
4. Project Settings → Data API / API Keys で次を控える (画面に出したまま放置しない):
   - Project URL (`https://<NEW_REF>.supabase.co`)
   - anon key (または publishable key)
   - service_role key (または secret key)
5. Authentication → URL Configuration:
   - Site URL: `https://studyplan.nobilva.jp`
   - Redirect URLs: 旧プロジェクトの設定を見て同じものを入れる
6. Authentication → Providers / Email / Rate Limits / SMTP: **旧プロジェクトの設定画面を見ながら同じ値にする** (ダンプには入らない)。メールテンプレートを変えていればコピーする。
7. Database → Extensions で `pg_cron` と `pg_net` を有効にする (036 が使う)。

> 参考: Supabase には組織間で「Transfer project」する機能があるが、**リージョンは変えられない**。東京にするには新規作成が必要。

---

## 4. データを移す (リハーサル → 本番)

公式の「Supabase から Supabase への移行」と同じやり方です。**まずリハーサルとして 1 回通しで行い、当日は 4-3 だけをもう一度やります。**

### 4-0. 準備

```bash
brew install supabase/tap/supabase libpq
brew link --force libpq   # psql / pg_dump
mkdir -p ~/nobilva-migration && cd ~/nobilva-migration
chmod 700 .

# 接続文字列は Connect → Direct → 接続方式を "Session pooler" にしたもの (ホストが ...pooler.supabase.com:5432、ユーザーが postgres.<ref>)。
# Direct connection (db.<ref>.supabase.co) は IPv6 専用で、家の回線ではつながらないことが多い。
# 変数は read -s を実行したタブの中だけで有効。チャット欄の ! は別タブで実行されるので、同じタブに直接打つ。
read -s OLD_DB_URL && export OLD_DB_URL   # 旧: postgresql://postgres.<OLD_REF>:<pw>@aws-0-ap-south-1.pooler.supabase.com:5432/postgres
read -s NEW_DB_URL && export NEW_DB_URL   # 新: postgresql://postgres.<NEW_REF>:<pw>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres
```

旧プロジェクトの DB パスワードが分からない場合は、前任者に旧プロジェクトの組織へ招待してもらう (Owner か Administrator) か、パスワードをリセットしてもらう。

### 4-1. ダンプを取る

```bash
supabase db dump --db-url "$OLD_DB_URL" -f roles.sql  --role-only
supabase db dump --db-url "$OLD_DB_URL" -f schema.sql
supabase db dump --db-url "$OLD_DB_URL" -f data.sql   --use-copy --data-only \
  -x "storage.buckets_vectors" -x "storage.vector_indexes"
```

- `schema.sql` は `public` などアプリのスキーマ。`auth` / `storage` のテーブル定義は Supabase が持っているので入らない。
- `data.sql` には **`auth.users`、`auth.identities`、`auth.sessions`、`auth.refresh_tokens`、`storage.buckets`、`storage.objects` (メタデータのみ) の行が入る**。パスワードのハッシュもここで移る。
- この 3 ファイルには個人情報とパスワードハッシュが含まれる。**移行が終わったら削除する**。

### 4-2. スキーマを新プロジェクトに入れる

```bash
psql "$NEW_DB_URL" --single-transaction -v ON_ERROR_STOP=1 --file schema.sql
```

> **リハーサル (2026-11-09) で分かったこと**: `roles.sql` は Supabase 標準ロールの `statement_timeout` 設定 4 行だけで、新しいプロジェクトにも最初から同じ値が入っている。`supabase_admin` の行が `reserved role` で失敗するので、**`roles.sql` は流さない**。

### 4-3. データを入れる (当日はここをやり直す)

```bash
psql "$NEW_DB_URL" --single-transaction -v ON_ERROR_STOP=1 \
  --command 'SET session_replication_role = replica' \
  --file data.sql
```

`session_replication_role = replica` はトリガーと外部キーのチェックを止める設定です。`auth.users` を入れたときに `handle_new_user` が走って `profiles` が二重に作られるのを防ぎます。

リハーサル後に当日やり直すときは、先に新プロジェクトのデータを空にします (スキーマは残す)。一番確実なのは、リハーサルで使った新プロジェクトを Settings → General → **Pause でなく Delete** し、もう一度作って 4-2 からやり直す方法です。URL とキーが変わるので、Vercel の env もあとで入れ直します。手間を減らしたいなら、**リハーサル用と本番用で別の新プロジェクトを作る**のがおすすめです (リハーサル用は終わったら消す)。

### 4-4. auth.users のトリガーを作り直す

`auth` スキーマのトリガーはダンプに入らないので、手で作ります。関数 (`public.handle_new_user` / `public.sync_profile_email`) は `schema.sql` で移っています。まず旧プロジェクトで実際の定義を確認します。

```bash
psql "$OLD_DB_URL" -c "select tgname, pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;"
```

出てきた `CREATE TRIGGER ...` 文を新プロジェクトでそのまま実行します。マイグレーション上は次の 2 つのはずです。

```bash
psql "$NEW_DB_URL" -c "select tgname from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;"
```

足りなければ、旧で確認した文を実行します。マイグレーションどおりなら次の 2 つです。

```sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS sync_profile_email_on_auth ON auth.users;
CREATE TRIGGER sync_profile_email_on_auth
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_email();
```

これを忘れると、切替後に管理画面で作った生徒・先生に `profiles` の行ができず、ログイン後にエラーになります。

### 4-5. Realtime / Vault / pg_cron

```bash
# chat_messages が Realtime の対象に入っているか
psql "$NEW_DB_URL" -c "select tablename from pg_publication_tables where pubname = 'supabase_realtime';"
# 入っていなければ
psql "$NEW_DB_URL" -c "alter publication supabase_realtime add table public.chat_messages;"
```

Vault (Dashboard → Project Settings → Vault、または SQL) に 2 つ登録します。値は画面に貼るだけで、ファイルには書きません。

| name | secret |
|---|---|
| `meeting_notify_url` | `https://studyplan.nobilva.jp/api/dispatch/meeting-notify` |
| `meeting_notify_cron_secret` | Vercel の `CRON_SECRET` と同じ値 |

そのあと `supabase/migrations/036_meeting_notify_pg_cron.sql` を SQL Editor で実行し直します (同名ジョブを消してから登録するので何度流しても大丈夫)。

> **当日まで旧と新の両方で cron が動くと、面談通知が二重に送られそうに見えますが**、`notification_log` の UNIQUE 制約で冪等になっているので重複送信はされません。それでも念のため、切替が終わったら旧プロジェクトのジョブを止めます (手順 8)。

### 4-5b. Storage のポリシーを作り直す

`schema.sql` は `storage` スキーマを含まないので、031 で `storage.objects` に付けた 2 つのポリシーが抜ける (リハーサルで確認)。新しいプロジェクトで作り直す:

```bash
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -c "CREATE POLICY \"Chat participants can upload images\" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'chat-images' AND (storage.foldername(name))[1] = 'chat' AND EXISTS (SELECT 1 FROM public.chat_threads ct WHERE ct.id::text = (storage.foldername(name))[2] AND (ct.teacher_id = auth.uid() OR ct.student_id IN (SELECT id FROM public.student_profiles WHERE user_id = auth.uid())))); CREATE POLICY \"Public read chat images\" ON storage.objects FOR SELECT TO public USING (bucket_id = 'chat-images');"
```

### 4-6. 件数をくらべる

`public` の全テーブルの実際の行数をくらべる (統計値より正確):

```bash
Q="select table_name, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by 1;"
psql "$OLD_DB_URL" -At -c "$Q" > old_counts.txt && psql "$NEW_DB_URL" -At -c "$Q" > new_counts.txt && diff old_counts.txt new_counts.txt && echo "public の行数はすべて一致"
```

ポリシーを名前でくらべる (差が出たら 4-5b の抜けを疑う):

```bash
P="select schemaname||'.'||tablename||' : '||policyname from pg_policies where schemaname in ('public','storage') order by 1;"
psql "$OLD_DB_URL" -At -c "$P" > old_pol.txt && psql "$NEW_DB_URL" -At -c "$P" > new_pol.txt && diff old_pol.txt new_pol.txt && echo "ポリシーも一致"
```

以下は統計値によるざっくりした比較 (参考):

```bash
Q="select relname, n_live_tup from pg_stat_user_tables where schemaname in ('public') order by 1;"
psql "$OLD_DB_URL" -c "analyze;" -c "$Q" > old_counts.txt
psql "$NEW_DB_URL" -c "analyze;" -c "$Q" > new_counts.txt
diff old_counts.txt new_counts.txt && echo "public の件数一致"

for t in auth.users auth.identities storage.objects public.webauthn_credentials; do
  echo "$t: old=$(psql "$OLD_DB_URL" -tAc "select count(*) from $t") new=$(psql "$NEW_DB_URL" -tAc "select count(*) from $t")"
done
```

あわせて、マイグレーションのファイルと本番がずれていないかも確認しておくと安心です (SQL Editor で直接変更した箇所がないか)。

```bash
psql "$NEW_DB_URL" -c "select count(*) from pg_policies where schemaname in ('public','storage');"   # 旧と同じ数か
```

---

## 5. Storage (chat-images) を移す

`storage.objects` の行は 4-3 で移っていますが、**ファイル本体は移っていません**。小さなスクリプトでコピーします。Web リポジトリで実行すれば `@supabase/supabase-js` がすでに入っています。

`~/nobilva-migration/copy-storage.mjs` (リポジトリの外に置く):

```js
// 使い方: OLD_URL / OLD_KEY / NEW_URL / NEW_KEY を環境変数で渡す (service_role キー)
import { createClient } from "@supabase/supabase-js";

const BUCKET = "chat-images";
const oldSb = createClient(process.env.OLD_URL, process.env.OLD_KEY, { auth: { persistSession: false } });
const newSb = createClient(process.env.NEW_URL, process.env.NEW_KEY, { auth: { persistSession: false } });

async function listAll(prefix) {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await oldSb.storage.from(BUCKET).list(prefix, { limit: 1000, offset });
    if (error) throw error;
    for (const e of data) {
      const path = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.id === null) out.push(...(await listAll(path))); // フォルダ
      else out.push({ path, contentType: e.metadata?.mimetype });
    }
    if (data.length < 1000) return out;
  }
}

const files = await listAll("");
console.log(`${files.length} files`);
let ok = 0;
for (const f of files) {
  const { data, error } = await oldSb.storage.from(BUCKET).download(f.path);
  if (error) { console.error("download", f.path, error.message); continue; }
  const { error: upErr } = await newSb.storage.from(BUCKET).upload(f.path, data, {
    contentType: f.contentType, cacheControl: "31536000", upsert: true,
  });
  if (upErr) console.error("upload", f.path, upErr.message); else ok++;
}
console.log(`copied ${ok}/${files.length}`);
```

```bash
cd ~/programs/nobilva_study_plan
read -s OLD_KEY && export OLD_KEY; read -s NEW_KEY && export NEW_KEY
OLD_URL=https://<OLD_REF>.supabase.co NEW_URL=https://<NEW_REF>.supabase.co \
  node ~/nobilva-migration/copy-storage.mjs
```

- `upsert: true` なので、何度実行しても大丈夫です。前日に 1 回、当日に最終データ移行のあとにもう 1 回実行すると、当日の分だけ差分を埋められます。
- バケットが新プロジェクトにない場合は、031 の `INSERT INTO storage.buckets ...` を実行する (`storage.buckets` の行は data.sql で移るので、通常は不要)。

> **リハーサル (2026-11-09) で使った簡単な方法**: 画像が少ないときは、Node スクリプトより `curl` が楽 (旧は公開 URL からダウンロード、新は service_role キーで上書きアップロード)。キーは **Legacy API keys の service_role (`eyJ...`)** を使う。新しい形式の `sb_secret_...` を `Authorization: Bearer` に入れると `Invalid Compact JWS` (403) になる (その場合は `apikey` ヘッダーだけで送る)。
>
> ```bash
> export OLD_REF=<旧ref> NEW_REF=<新ref>
> read -s NEW_SERVICE_KEY && export NEW_SERVICE_KEY   # 入力待ちになったらキーだけを貼る
> psql "$OLD_DB_URL" -At -F' ' -c "select name, metadata->>'mimetype' from storage.objects where bucket_id='chat-images'" | while read -r name mime; do curl -sf -o ~/nobilva-migration/obj.bin "https://$OLD_REF.supabase.co/storage/v1/object/public/chat-images/$name" && curl -s -o /dev/null -w "$name -> %{http_code}\n" -X POST -H "Authorization: Bearer $NEW_SERVICE_KEY" -H "apikey: $NEW_SERVICE_KEY" -H "Content-Type: $mime" -H "x-upsert: true" -H "Cache-Control: max-age=31536000" --data-binary @$HOME/nobilva-migration/obj.bin "https://$NEW_REF.supabase.co/storage/v1/object/chat-images/$name"; done
> ```

### チャット画像の URL を書き換える

`chat_messages.image_url` には `https://<OLD_REF>.supabase.co/storage/v1/object/public/chat-images/...` が入っています。旧プロジェクトを消すと画像が表示されなくなるので、新しいホストに書き換えます。

```bash
psql "$NEW_DB_URL" -c "
update public.chat_messages
   set image_url = replace(image_url, 'https://<OLD_REF>.supabase.co/', 'https://<NEW_REF>.supabase.co/')
 where image_url like 'https://<OLD_REF>.supabase.co/%';"
```

---

## 6. 新しい Vercel プロジェクトを作る

### 移管 (Transfer) と新規作成のどちらにするか

| | Transfer Project | 新規作成 (推奨) |
|---|---|---|
| やり方 | 前任者が Project Settings → General → Transfer Project で、**自分がメンバーになっているチーム**へ移す | 自分の Vercel で GitHub リポジトリ (`ryuto1246/...`) を Import |
| 前任者の作業 | 必要 (前任者が操作する) | 不要 (ドメインを外してもらうだけ) |
| 環境変数・ドメイン・デプロイ履歴 | まとめて移る | 自分で入れ直す |
| リージョン | 移したあと自分で hnd1 に設定 | 最初から hnd1 |

Supabase の値はどちらにしても全部変わるので、**新規作成のほうが分かりやすい**です。ただし前任者が協力的で、環境変数の値を自分が知らない (Sensitive 指定で読めない) 場合は、Transfer のほうが楽です。Transfer を使うなら、移したあと 6-2 のリージョン設定と 7 の env 切替だけ行います。

> 移す前に、旧プロジェクトの env を前任者に**値ごと**共有してもらう必要があります (Sensitive の env はダッシュボードでも CLI でも読み出せないため)。値は 1Password の共有などで受け取り、チャットやメールに貼らないでもらう。

### 6-1. Import

1. 自分の Vercel アカウント (またはチーム) → Add New → Project → GitHub の `nobilva_study_plan` を Import。
2. Production Branch を旧プロジェクトと同じにする (旧の Settings → Git で確認)。
3. 環境変数を 1 章の表のとおり入れる。Supabase の 3 つは**新プロジェクトの値**。最初は Preview だけに入れて動作確認し、当日 Production に入れる、でもよい。

CLI で入れる場合 (値は対話入力されるので履歴に残らない):

```bash
cd ~/programs/nobilva_study_plan
npx vercel link                 # 自分のスコープの新プロジェクトを選ぶ
npx vercel env add NEXT_PUBLIC_SUPABASE_URL production
npx vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production
npx vercel env add SUPABASE_SERVICE_ROLE_KEY production --sensitive
# ...以下 1 章の表のものを同様に
```

### 6-2. 関数のリージョンを東京にする

どちらか一方で設定します。コードに残るので `vercel.json` に書く方法がおすすめです。

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "regions": ["hnd1"],
  "crons": [
    { "path": "/api/dispatch/sync-retry", "schedule": "0 18 * * *" },
    { "path": "/api/dispatch/meeting-topup", "schedule": "0 19 * * *" }
  ]
}
```

または Project Settings → Functions → Function Region → **Tokyo, Japan (hnd1)**。

デプロイしたら `x-vercel-id` の最後が `hnd1` になっていることを確認します (0 章のコマンド)。

### 6-3. 仮 URL で動作確認

`https://<project>.vercel.app` で次を確認します。**この時点の新 DB はリハーサル時点のデータ**なので、確認で作ったデータは当日消えます。

- 管理画面にパスワードでログインできる
- 先生・生徒でログインできる (パスワード)
- メモ・テスト登録が速い
- チャットの送受信、画像の表示、Realtime で即時に反映される

パスキーは rpID が `studyplan.nobilva.jp` なので、`*.vercel.app` では**試せません** (当日ドメインを付け替えたあとに確認する)。

---

### 6-4. リハーサル (2026-11-09) で分かった Vercel の注意

- **関数の地域**: Web リポジトリのブランチ `claude/vercel-region-hnd1` で `vercel.json` に `"regions": ["hnd1"]` を足した。`vercel.json` はデプロイごとに効くので、このブランチのプレビューだけ東京で動く。**当日このブランチを本番ブランチに入れる**と、本番も hnd1 になる。
- **環境変数の種類**: Vercel は環境変数を Config (値を見られる) と Secret に分けるようになった。`NEXT_PUBLIC_` で始まる変数は Config でないと保存できず、**既存の変数を画面で編集しようとしても `Remove the public framework prefix...` で保存できない**。CLI で種類を指定して入れる:

```bash
cd ~/programs/nobilva_study_plan && npx vercel@latest link   # 移管後のチームとプロジェクトを選ぶ
printf %s 'https://<NEW_REF>.supabase.co' | npx vercel@latest env add NEXT_PUBLIC_SUPABASE_URL --environment <preview|production> [--git-branch <branch>] --type config
pbpaste | npx vercel@latest env add NEXT_PUBLIC_SUPABASE_ANON_KEY --environment <...> --type config     # anon (eyJ...) をコピーしてから
pbpaste | npx vercel@latest env add SUPABASE_SERVICE_ROLE_KEY --environment <...> --type secret          # service_role (eyJ...) をコピーしてから
printf '' | pbcopy
```

- **プレビューだけ新しい DB に向ける**: 既存の Preview 用の変数を触らず、`--git-branch` でブランチ専用の変数を足すと、そのブランチだけ値が上書きされる。ブランチは先に push しておく必要がある。変数を足したら、空コミットを push して作り直す (環境変数はビルド時に読まれる)。
- **プレビューは Vercel のログイン保護つき**: `curl` では中に入れないので、関数の地域 (`x-vercel-id`) はブラウザの開発者ツールで見る。
- **結果**: プレビュー (hnd1 + 東京の Supabase) で、体感で速くなったことを確認。

## 7A. 今夜の切替手順 (2026-11-09 深夜、リハーサルのプロジェクトをそのまま使う)

前提: 新しい Supabase は `orrnulumiqcfvetldnrn` (リハーサルで使ったもの)。ドメインは移管で引き継いでいるので**DNS もパスキーも iOS アプリも変更なし**。すべてタブ 0 (`~/nobilva-migration`) で行う。

### 事前 (切替の前に済ませる)

- [ ] 生徒・先生に作業時間を告知する (例: 0:00〜0:45 は保存できません)
- [ ] `~/nobilva-migration` に `wipe.sql` / `wipe_dryrun.sql` / `reload_dryrun.sql` がある
- [ ] 試し流し (元に戻るので本番に影響なし):
  `psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -f reload_dryrun.sql` → 最後に件数が出て `ROLLBACK` で終われば OK
- [ ] Vercel の本番ブランチ名を確認 (Settings → Git → Production Branch)
- [ ] 旧本番の anon / service_role キーが旧 Supabase の画面で見られること (ロールバック用)
- [ ] `CRON_SECRET` の値が分かること (Vercel で Secret だと読めない。分からなければ今夜新しい値に作り直す)
- [ ] 新しい Supabase の Authentication → URL Configuration の Site URL が `https://studyplan.nobilva.jp`

### 本番 (目安 30〜45 分)

1. **旧の 5 分ごとの通知を止める**
   `psql "$OLD_DB_URL" -c "select cron.unschedule('meeting-notify-5min');"`
2. **旧を読み取り専用にする** (権限で断られたら、告知だけで進めてよい。利用者は 8 人)
   `psql "$OLD_DB_URL" -c "alter database postgres set default_transaction_read_only = on;"`
   `psql "$OLD_DB_URL" -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = 'postgres' and pid <> pg_backend_pid() and usename in ('authenticator','supabase_auth_admin','supabase_storage_admin');"`
3. **データだけダンプを取り直す** (スキーマはリハーサルと同じなので取り直さない)
   `supabase db dump --db-url "$OLD_DB_URL" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"`
4. **新を空にして入れ直す** (1 つの取引。失敗したら全部元に戻る)
   `psql "$NEW_DB_URL" --single-transaction -v ON_ERROR_STOP=1 -f wipe.sql -f data.sql`
5. **くらべる** (4-6 の `Q` と `P` の比較、`auth.users` などの件数)。すべて一致すること
6. **画像をコピーして URL を書き換える** (5 章の curl と update。`NEW_SERVICE_KEY` は読み込み直す)
7. **新の 5 分ごとの通知を動かす**
   - 新しい Supabase の Vault に `meeting_notify_url` = `https://studyplan.nobilva.jp/api/dispatch/meeting-notify`、`meeting_notify_cron_secret` = `CRON_SECRET` の値 を登録 (画面で)
   - `psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -f ~/programs/nobilva_study_plan/supabase/migrations/036_meeting_notify_pg_cron.sql`
8. **Vercel の Production 用の変数を新しい値にする** (既存を消してから足す。値は新しい Supabase の Legacy API keys)
   ```bash
   cd ~/programs/nobilva_study_plan
   npx vercel@latest env rm NEXT_PUBLIC_SUPABASE_URL production -y
   npx vercel@latest env rm NEXT_PUBLIC_SUPABASE_ANON_KEY production -y
   npx vercel@latest env rm SUPABASE_SERVICE_ROLE_KEY production -y
   printf %s 'https://orrnulumiqcfvetldnrn.supabase.co' | npx vercel@latest env add NEXT_PUBLIC_SUPABASE_URL --environment production --type config
   pbpaste | npx vercel@latest env add NEXT_PUBLIC_SUPABASE_ANON_KEY --environment production --type config   # anon をコピーしてから
   pbpaste | npx vercel@latest env add SUPABASE_SERVICE_ROLE_KEY --environment production --type secret      # service_role をコピーしてから
   printf '' | pbcopy
   ```
   `CRON_SECRET` を作り直す場合は同じく `env rm` → `env add CRON_SECRET --environment production --type secret` (Vault と同じ値)
9. **本番をデプロイする** (東京の関数 + 新しい変数を同じデプロイで)
   `claude/vercel-region-hnd1` を本番ブランチにマージして push。Vercel の Deployments で Production のビルドが終わるのを待つ
10. **確かめる**
    - `curl -sI https://studyplan.nobilva.jp/login | grep -i x-vercel-id` → 2 つ目が `hnd1`
    - Web: パスワードとパスキーでログイン、メモ・テスト登録、チャット (画像・即時反映)
    - iOS アプリ: そのまま使えるか (使えなければ再ログインで直るか)
    - 5 分後: `psql "$NEW_DB_URL" -c "select status, start_time from cron.job_run_details order by start_time desc limit 3;"` が `succeeded`
11. **告知を解除する**

### うまくいかなかったら (ロールバック、5 分)

1. Vercel → Deployments → 切替前の Production デプロイ → **Instant Rollback** (デプロイは作られた時の変数を持っているので、旧 Supabase + bom1 にすぐ戻る)
2. 旧を書き込み可能に戻す: `psql "$OLD_DB_URL" -c "alter database postgres set default_transaction_read_only = off;"`
3. 旧の通知を戻す: `psql "$OLD_DB_URL" -f ~/programs/nobilva_study_plan/supabase/migrations/036_meeting_notify_pg_cron.sql`
4. 落ち着いてから、Vercel の Production 用の変数を旧の値に戻しておく (次のデプロイで新に向かないように)

## 7. 当日の切替

| 時刻の目安 | 作業 |
|---|---|
| T-1 日 | 6-3 まで終わらせる。前任者に当日の作業時間を伝え、ドメインを外してもらう段取りをつける |
| T-0 | 生徒・先生に告知した時間に開始 |
| T+0 | 旧 Vercel で書き込みを止める (下記) |
| T+5 | 4-3 (データ再投入) → 4-4 → 4-5 → 4-6 (件数確認) → 5 (Storage 差分コピー + URL 書き換え) |
| T+20 | 新 Vercel の Production env を新 Supabase に向け、Redeploy |
| T+25 | ドメイン付け替え (下記) |
| T+30 | 確認 (下記)。問題があればロールバック |

### 書き込みを止める

一番簡単なのは、旧 Supabase の DB を読み取り専用にすることです (前任者の組織で、自分に権限があるうちに行う)。

```bash
psql "$OLD_DB_URL" -c "alter database postgres set default_transaction_read_only = on;"
# 既存の接続にも効かせるため、Dashboard → Database → Settings → Restart database でも可
```

この間、旧サイトで書き込みをするとエラーになります。読み取りは使えます。

### ドメインを付け替える

1. 前任者に旧 Vercel プロジェクトから `studyplan.nobilva.jp` を **Remove** してもらう。
2. 自分の新プロジェクト → Settings → Domains → `studyplan.nobilva.jp` を Add。
3. Vercel が「別のアカウントで使われていた」として TXT レコードでの確認を求めたら、`nobilva.jp` の DNS 管理画面に `_vercel` の TXT レコードを追加する。
4. DNS の CNAME / A レコードは**今のまま** (`cname.vercel-dns.com` など) で通常は変更不要。DNS も前任者の管理なら、このタイミングでドメインの管理者も自分に移しておく。
5. 証明書の発行に数分かかる。この間 HTTPS がエラーになることがある。

**前任者がすぐに対応できない場合の代わりの方法**: 先にドメインを付け替えて、新 Vercel の env を「旧 Supabase」に向けておく → 後日 env だけ新 Supabase に切り替える。ドメインの切替と DB の切替を別の日にできるので、当日の作業が減ります。

### 確認

```bash
curl -sI https://studyplan.nobilva.jp/login | grep -i x-vercel-id      # 最後が hnd1
curl -s  https://studyplan.nobilva.jp/.well-known/apple-app-site-association | head -c 200   # 404 でなく JSON
```

- Web: パスワードログイン / **パスキーログイン** / メモ・テスト登録 / チャット (画像含む)
- iOS: 既存の端末でそのまま使えるか (使えなければ再ログインで直るか)、パスキーでログインできるか、プッシュ通知
- 5 分後: 新 Supabase の `select * from cron.job_run_details order by start_time desc limit 5;` で meeting-notify が成功しているか
- 翌日: Vercel Cron (sync-retry / meeting-topup) が動いたか (Vercel → Logs)
- nectere_contract_form / nectere_dashboard からの連携 (契約 → アカウント発行) が通るか

---

## 8. 切替後の片付け

1. 旧 Supabase の cron を止める:
   ```bash
   psql "$OLD_DB_URL" -c "select cron.unschedule('meeting-notify-5min');"
   ```
   (読み取り専用にした場合は、一時的に `set default_transaction_read_only = off` が必要)
2. 2 週間ほど様子を見てから、前任者に旧 Supabase / 旧 Vercel を消してもらう (または Pause)。
3. `~/nobilva-migration` のダンプとスクリプトを削除する: `rm -rf ~/nobilva-migration`
4. 前任者に共有された秘密情報のうち、ローテーションできるもの (`CRON_SECRET`、`AUTH_COOKIE_SECRET`、`ADMIN_LOGIN_PASSWORD`、Resend / Gemini の API キーなど) は新しい値にする。`CRON_SECRET` を変えたら Vault の `meeting_notify_cron_secret` も同じ値にする。HMAC 系は連携先 (contract_form / dashboard) と同時に変える。
5. `lib/supabase/env.ts` のタイムアウト 10 秒とコメント (ムンバイ前提) は、様子を見て 3〜5 秒に戻してよい。

---

## 9. ログイン状態への影響 (iOS の審査は不要)

- **パスワード**: ハッシュが移るので、そのまま同じパスワードでログインできる。
- **パスキー**: `webauthn_credentials` が移り、rpID (ドメイン) も同じなので、そのまま使える。
- **すでにログイン中のセッション**: 新プロジェクトは JWT の署名鍵が旧と違うので、旧プロジェクトが発行した access token は新プロジェクトで受け付けられない。
  - iOS は 401 を受けると refresh を試みる。`auth.refresh_tokens` / `auth.sessions` も移しているので、**refresh が通れば利用者は気づかない**。通らなければ一度ログアウトになり、パスワードかパスキーでログインし直せば直る。
  - Web はクッキー名が `sb-<ref>-auth-token` でプロジェクトごとに違うので、**全員一度ログアウトになる**。
  - どちらになるかはリハーサル (6-3) で確かめられる: 旧本番でログインした iOS 端末を、切替後に開いてみる。
  - ログアウトを避けたい場合、Supabase の JWT Signing Keys の画面で旧プロジェクトの legacy JWT secret を新プロジェクトに取り込めるか確認する (できれば access token もそのまま通る)。生徒数が少ないなら「一度ログインし直してください」と告知するだけで十分です。
- **iOS アプリのアップデートや審査は不要**。アプリが持っている接続先は `studyplan.nobilva.jp` だけで、Supabase の URL やキーは持っていない。ドメインを変える場合だけ、`APIClient.baseURL` と Associated Domains の変更 → 新バージョンの審査が必要になる (おすすめしない)。

---

## 10. ロールバック

切替後に問題が出たら、次の順で戻します。

1. 旧 Supabase の読み取り専用を解除: `alter database postgres set default_transaction_read_only = off;`
2. ドメインを旧 Vercel プロジェクトに戻す (前任者の協力が必要) — **または**、新 Vercel の Production env を旧 Supabase の値に戻して Redeploy (前任者がいなくても戻せるので、こちらが速い)
3. 新プロジェクトで書き込まれたデータがあれば、手で旧に反映する (切替直後なら件数は少ない)

ロールバックしやすいよう、**切替後 1〜2 時間は新しい機能のリリースをしない**ようにします。

---

## 11. Neon にするべきか

### 結論: **Supabase のまま東京に移すのがおすすめ**

本番は関数も DB もムンバイにあり、すでに近くに置かれています。遅さの原因は「Supabase だから」ではありません。Neon の東京 (aws-ap-northeast-1) に移しても、Supabase の東京に移しても、同じ AWS 東京リージョン内なので速さはほぼ同じになります。一方で、Neon にすると下のものを全部作り直す必要があります。

### コードの使い方から見た置き換え量

| Supabase の機能 | このアプリでの使い方 | Neon にした場合 |
|---|---|---|
| PostgREST + supabase-js | `.from("...")` が **91 ファイル・434 か所**。Server Component・server action・route handler のすべて | Drizzle / Kysely などで書き直し。Neon の Data API (PostgREST 互換) を使えば書き直しは減るが、まだ新しい機能で、Auth との組み合わせも含めて検証が必要 |
| RLS + `auth.uid()` | ポリシー 90 個、`auth.uid()` 99 か所。ユーザーの JWT をそのまま DB に渡して RLS で絞っている | `auth.uid()` を自前の関数に置き換え、リクエストごとに `set_config('request.jwt.claims', ...)` を流す仕組みを作る。または RLS をやめてアプリ側の where 句で絞る (漏れがあると情報漏えいにつながる) |
| Supabase Auth | パスワード (bcrypt)、`admin.createUser` / `generateLink` + `verifyOtp` でパスキーログイン後のセッション発行、iOS 向けの access/refresh token、管理画面のユーザー作成・削除 | Neon Auth (Better Auth ベース) か Auth.js などに置き換え。パスワードハッシュの移し替え、iOS のトークン更新 API の作り直し、パスキー後のセッション発行の作り直しが必要。**iOS アプリの改修と再審査が必要になる可能性が高い** |
| Storage | `chat-images` 公開バケット | S3 / Cloudflare R2 / Vercel Blob に移し、アップロード処理と URL を作り直す |
| Realtime | チャットの `postgres_changes` 購読 | Pusher / Ably などを入れるか、ポーリングに変える |
| pg_cron + pg_net + Vault | 5 分ごとの面談通知 | Vercel Cron (Pro なら 5 分間隔も可) か外部 cron に移す |

**見積もり**: 書き直し・テスト・iOS の改修と審査を合わせて、1 人で **3〜6 週間**。Supabase のまま東京に移すのは、リハーサルを含めて **1〜2 日** (当日の停止は 30 分前後)。

### レイテンシの見込み

| 構成 | DB への 1 往復 |
|---|---|
| 構成 | 関数 ↔ DB の 1 往復 | 利用者 (日本) ↔ 関数 |
|---|---|---|
| 今 (Vercel bom1 + Supabase ムンバイ) | 数 ms | 約 100〜150ms |
| Vercel hnd1 + Supabase 東京 | 1〜3ms (+ PostgREST / Auth の処理) | 数 ms |
| Vercel hnd1 + Neon 東京 | 1〜3ms (+ 止まっていた計算資源が起動するとき数百 ms) | 数 ms |

Neon が有利なのは、PostgREST を通さずに直接 SQL を送れる分だけで、数 ms の差です。今の本番はすでに関数と DB が近くにあるので、**「数十秒」の原因は Supabase でも距離でもない可能性が高く、Neon にしても直りません** (0 章の「本番が遅い原因を探す」を参照)。

### 東京に移したあとも遅い場合

1. `x-vercel-id` で関数が hnd1 で動いているか
2. Supabase の Dashboard → Reports → Query Performance で遅いクエリを探す (RLS のサブクエリにインデックスがない、など)
3. 1 画面の中で直列になっているクエリを `Promise.all` で並列にする
4. middleware の `auth.getUser()` (毎回ネットワーク往復) を `auth.getClaims()` (新しい非対称鍵なら JWT をその場で検証できる) に置き換える

---

## チェックリスト

- [x] 0: `x-vercel-id` で今の関数リージョンを確認 (bom1 = ムンバイ)
- [ ] 0: 本番が遅い原因を探す (関数ログ・Supabase の計算資源・遅いクエリ)
- [ ] 3: 新 Supabase (Tokyo) を自分の組織に作成、Auth 設定・拡張を旧と同じに
- [ ] 前任者から: 旧 Supabase の DB 接続権限、旧 Vercel の env の値、当日のドメイン解除の約束、DNS / Resend / LINE / Gemini / Apple Developer などの所有者の確認
- [ ] 4: リハーサル移行 (ダンプ → スキーマ → データ → auth トリガー → Realtime / Vault / cron → 件数確認)
- [ ] 5: Storage コピー + `image_url` 書き換え
- [ ] 6: 新 Vercel (hnd1) を作成、仮 URL で確認
- [ ] 7: 当日切替 (読み取り専用 → 最終移行 → env 切替 → ドメイン付け替え → 確認)
- [ ] 8: 旧 cron 停止、ダンプ削除、秘密情報のローテーション
- [ ] 2 週間後: 旧 Supabase / 旧 Vercel を削除してもらう
