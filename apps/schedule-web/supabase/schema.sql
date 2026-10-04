-- 碩学館 年間スケジュール: スキーマ / RLS / トリガー
-- Supabase の SQL Editor に貼り付けて実行してください（何度実行しても壊れないようにしてあります）。

------------------------------------------------------------
-- 1. テーブル
------------------------------------------------------------

-- 管理者（ここに登録した user_id だけが編集できる）
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- 種別（名前と色）
create table if not exists public.event_types (
  name       text primary key,
  color      text not null check (color ~ '^#[0-9a-fA-F]{6}$'),
  sort_order int  not null default 0
);

-- 予定
create table if not exists public.events (
  id           uuid primary key default gen_random_uuid(),
  event_date   date not null,
  type         text not null references public.event_types(name) on update cascade,
  title        text not null default '',
  start_time   time,
  end_time     time,
  note         text not null default '',
  is_published boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint events_time_order check (start_time is null or end_time is null or end_time >= start_time)
);
create index if not exists events_event_date_idx on public.events (event_date);

-- 変更履歴（トリガーだけが書き込む）
create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  table_name text not null,
  op         text not null,
  row_id     text,
  actor      uuid,
  old_data   jsonb,
  new_data   jsonb
);
create index if not exists audit_log_at_idx on public.audit_log (at desc);

------------------------------------------------------------
-- 2. 管理者判定
------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

------------------------------------------------------------
-- 3. 権限（GRANT）: まず全部剥がして、必要なものだけ与える。
--    実際の可否は RLS が決める。
------------------------------------------------------------
revoke all on public.admins, public.event_types, public.events, public.audit_log from anon, authenticated;

grant select on public.events, public.event_types to anon, authenticated;
grant insert, update, delete on public.events, public.event_types to authenticated;
grant select on public.audit_log to authenticated;
grant select on public.admins to authenticated;   -- 自分が管理者かの確認用（RLSで自分の行のみ）

------------------------------------------------------------
-- 4. RLS
------------------------------------------------------------
alter table public.admins      enable row level security;
alter table public.event_types enable row level security;
alter table public.events      enable row level security;
alter table public.audit_log   enable row level security;

-- admins: ログイン中ユーザーは自分の行だけ読める。書き込みポリシーは無し
--        （SQL Editor など service 権限からのみ登録可能）
drop policy if exists admins_select_self on public.admins;
create policy admins_select_self on public.admins
  for select to authenticated
  using (user_id = auth.uid());

-- event_types: 誰でも読める / 管理者のみ書き込み
drop policy if exists event_types_select on public.event_types;
create policy event_types_select on public.event_types
  for select to anon, authenticated using (true);

drop policy if exists event_types_admin_insert on public.event_types;
create policy event_types_admin_insert on public.event_types
  for insert to authenticated with check ((select public.is_admin()));

drop policy if exists event_types_admin_update on public.event_types;
create policy event_types_admin_update on public.event_types
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists event_types_admin_delete on public.event_types;
create policy event_types_admin_delete on public.event_types
  for delete to authenticated using ((select public.is_admin()));

-- events: 公開の行は誰でも読める（管理者は下書きも） / 管理者のみ書き込み
drop policy if exists events_select on public.events;
create policy events_select on public.events
  for select to anon, authenticated
  using (is_published or (select public.is_admin()));

drop policy if exists events_admin_insert on public.events;
create policy events_admin_insert on public.events
  for insert to authenticated with check ((select public.is_admin()));

drop policy if exists events_admin_update on public.events;
create policy events_admin_update on public.events
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists events_admin_delete on public.events;
create policy events_admin_delete on public.events
  for delete to authenticated using ((select public.is_admin()));

-- audit_log: 管理者のみ読める。INSERT/UPDATE/DELETE のポリシーは無し（トリガーのみ）
drop policy if exists audit_log_admin_select on public.audit_log;
create policy audit_log_admin_select on public.audit_log
  for select to authenticated using ((select public.is_admin()));

------------------------------------------------------------
-- 5. トリガー
------------------------------------------------------------

-- updated_at の自動更新
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

-- 変更履歴の自動記録（RLSを越えて書き込むため security definer）
create or replace function public.log_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o jsonb;
  n jsonb;
begin
  if tg_op in ('UPDATE', 'DELETE') then o := to_jsonb(old); end if;
  if tg_op in ('UPDATE', 'INSERT') then n := to_jsonb(new); end if;

  -- 実質変更なしの UPDATE は記録しない
  if tg_op = 'UPDATE' and (o - 'updated_at') = (n - 'updated_at') then
    return new;
  end if;

  insert into public.audit_log (table_name, op, row_id, actor, old_data, new_data)
  values (
    tg_table_name, tg_op,
    coalesce(n ->> 'id', n ->> 'name', o ->> 'id', o ->> 'name'),
    auth.uid(), o, n
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists events_audit on public.events;
create trigger events_audit
  after insert or update or delete on public.events
  for each row execute function public.log_audit();

drop trigger if exists event_types_audit on public.event_types;
create trigger event_types_audit
  after insert or update or delete on public.event_types
  for each row execute function public.log_audit();

------------------------------------------------------------
-- 6. 種別の初期データ
------------------------------------------------------------
insert into public.event_types (name, color, sort_order) values
  ('高1授業',    '#2a6fdb', 1),
  ('高2授業',    '#0e8a7d', 2),
  ('高3授業',    '#7a3fd1', 3),
  ('自習',       '#c27a00', 4),
  ('日曜自習室', '#d1541f', 5),
  ('講習',       '#c2306b', 6),
  ('休講',       '#b3273a', 7),
  ('休暇',       '#4f6b1e', 8)
on conflict (name) do nothing;
