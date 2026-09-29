-- 碩学館 欠席連絡・振替授業: スキーマ / RLS / DB関数 / トリガー
-- schema.sql → pickup.sql のあとで、Supabase の SQL Editor に貼り付けて実行してください（何度実行しても壊れないようにしてあります）。
-- 生徒名簿・本人確認・管理者の確認は、送迎予約（pickup.sql）のものを使う。設計は docs/absence-plan.md を参照。
--
-- 流れ：欠席の連絡 → 振替ストック +1 → 違う学年の授業に振替を申請（ストックを押さえる）→ 管理者が承認（使用済み）／却下（戻る）

------------------------------------------------------------
-- 1. テーブル
------------------------------------------------------------

-- 設定（1行だけ）
create table if not exists public.makeup_settings (
  id                  int primary key default 1 check (id = 1),
  credit_valid_months int not null default 3 check (credit_valid_months between 1 and 24),  -- ストックの有効期限（欠席した日から）
  makeup_capacity     int not null default 3 check (makeup_capacity between 1 and 20),      -- 1回の授業に受け入れる振替の人数
  updated_at          timestamptz not null default now()
);
insert into public.makeup_settings (id) values (1) on conflict (id) do nothing;

-- 欠席の連絡。授業は日付・種別・時刻を写して持つ（CSV の置き換えで events の id が変わっても残るように）
create table if not exists public.class_absences (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students(id),
  contact_id  uuid references public.student_contacts(id),
  event_id    uuid references public.events(id) on delete set null,
  class_date  date not null,
  class_type  text not null,
  start_time  time,
  end_time    time,
  reason      text not null default '' check (char_length(reason) <= 200),
  status      text not null default 'registered' check (status in ('registered', 'cancelled')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists class_absences_one on public.class_absences (student_id, class_date, class_type) where status = 'registered';
create index if not exists class_absences_date_idx on public.class_absences (class_date);

-- 振替ストック（1つ＝1行）。期限切れは expires_on で判断する（status は available のまま）
create table if not exists public.makeup_credits (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students(id),
  absence_id  uuid references public.class_absences(id) on delete set null,   -- 管理者が手動で足したものは null
  granted_on  date not null,
  expires_on  date not null,
  status      text not null default 'available' check (status in ('available', 'reserved', 'used', 'revoked')),
  note        text not null default '' check (char_length(note) <= 200),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists makeup_credits_absence on public.makeup_credits (absence_id) where absence_id is not null;
create index if not exists makeup_credits_student_idx on public.makeup_credits (student_id, status);

-- 振替の申請
create table if not exists public.makeup_requests (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.students(id),
  contact_id    uuid references public.student_contacts(id),
  credit_id     uuid not null references public.makeup_credits(id),
  event_id      uuid references public.events(id) on delete set null,
  class_date    date not null,
  class_type    text not null,
  start_time    time,
  end_time      time,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reject_reason text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists makeup_requests_one on public.makeup_requests (student_id, class_date, class_type) where status in ('pending', 'approved');
create unique index if not exists makeup_requests_credit on public.makeup_requests (credit_id) where status in ('pending', 'approved');
create index if not exists makeup_requests_date_idx on public.makeup_requests (class_date, status);

------------------------------------------------------------
-- 2. 権限と RLS（送迎と同じ：anon は触れない。管理者だけ読み書き。生徒の操作は DB 関数を Edge Function から）
------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['makeup_settings', 'class_absences', 'makeup_credits', 'makeup_requests'] loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_all', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))',
                   t || '_admin_all', t);
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()', t || '_set_updated_at', t);
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.log_audit()', t || '_audit', t);
  end loop;
end $$;

------------------------------------------------------------
-- 3. 共通の関数
------------------------------------------------------------

-- 学年 → 授業の種別（高2 → 高2授業）。それ以外は null
create or replace function public.class_type_of(p_grade text)
returns text
language sql
immutable
as $$ select case when p_grade in ('高1', '高2', '高3') then p_grade || '授業' end; $$;

-- 授業の開始日時（時刻が無ければその日の 0:00）
create or replace function public.class_start(p_date date, p_start time)
returns timestamp
language sql
immutable
as $$ select p_date + coalesce(p_start, '00:00'::time); $$;

-- 期間内の授業（公開済みの「高1〜高3授業」。公開済みの「休講」「休暇」がある日は除く。同じ日・同じ種別は1つにまとめる）
create or replace function public.makeup_classes(p_from date, p_to date)
returns table (event_id uuid, class_date date, class_type text, start_time time, end_time time)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (e.event_date, e.type) e.id, e.event_date, e.type, e.start_time, e.end_time
  from public.events e
  where e.is_published and e.type in ('高1授業', '高2授業', '高3授業') and e.event_date between p_from and p_to
    and not exists (select 1 from public.events k where k.event_date = e.event_date and k.is_published and k.type in ('休講', '休暇'))
  order by e.event_date, e.type, e.start_time nulls first;
$$;

-- その授業に入っている振替の人数（申請中＋承認）
create or replace function public.makeup_load(p_date date, p_type text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.makeup_requests
  where class_date = p_date and class_type = p_type and status in ('pending', 'approved');
$$;

-- 生徒の学年の授業の種別（無ければ利用者向けのエラー）
create or replace function public.makeup_own_type(p_student uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  t text;
begin
  select public.class_type_of(grade) into t from public.students where id = p_student;
  if t is null then perform public.pickup_fail('学年が登録されていないため、欠席・振替は使えません。碩学館に連絡してください。'); end if;
  return t;
end;
$$;

------------------------------------------------------------
-- 4. 生徒の操作（Edge Function から service_role で呼ぶ）
------------------------------------------------------------

-- 自分の学年の、今日から60日分の授業と、欠席の連絡の状態
create or replace function public.my_classes(p_contact_id uuid)
returns table (event_id uuid, class_date date, class_type text, start_time text, end_time text,
               absence_id uuid, reason text, can_register boolean, can_cancel boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  own text := public.makeup_own_type(sid);
  now_jst timestamp := public.pickup_now();
begin
  return query
  select c.event_id, c.class_date, c.class_type, to_char(c.start_time, 'HH24:MI'), to_char(c.end_time, 'HH24:MI'),
         a.id, a.reason,
         a.id is null and public.class_start(c.class_date, c.start_time) > now_jst,
         a.id is not null and public.class_start(c.class_date, c.start_time) > now_jst
           and coalesce((select m.status = 'available' from public.makeup_credits m where m.absence_id = a.id), true)
  from public.makeup_classes(now_jst::date, now_jst::date + 60) c
  left join public.class_absences a
    on a.student_id = sid and a.class_date = c.class_date and a.class_type = c.class_type and a.status = 'registered'
  where c.class_type = own
  order by c.class_date, c.start_time;
end;
$$;

-- 欠席の連絡（授業の開始時刻まで）→ 振替ストックを1つ付ける
create or replace function public.register_absence(p_contact_id uuid, p_date date, p_type text, p_reason text default '')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  own text := public.makeup_own_type(sid);
  c record;
  aid uuid;
begin
  if p_type is distinct from own then perform public.pickup_fail('自分の学年の授業だけ、欠席の連絡ができます。'); end if;
  select * into c from public.makeup_classes(p_date, p_date) x where x.class_type = p_type;
  if not found then perform public.pickup_fail('その日の授業が見つかりません。'); end if;
  if public.class_start(c.class_date, c.start_time) <= public.pickup_now() then
    perform public.pickup_fail('授業の開始時刻を過ぎているため、欠席の連絡はできません（振替ストックは付きません）。碩学館に直接連絡してください。');
  end if;
  perform pg_advisory_xact_lock(hashtext('makeup:student:' || sid::text));
  begin
    insert into public.class_absences (student_id, contact_id, event_id, class_date, class_type, start_time, end_time, reason)
    values (sid, p_contact_id, c.event_id, c.class_date, c.class_type, c.start_time, c.end_time, left(coalesce(p_reason, ''), 200))
    returning id into aid;
  exception when unique_violation then
    perform public.pickup_fail('この授業は、すでに欠席の連絡をしています。');
  end;
  insert into public.makeup_credits (student_id, absence_id, granted_on, expires_on)
  values (sid, aid, p_date, (p_date + make_interval(months => (select credit_valid_months from public.makeup_settings where id = 1)))::date);
  return aid;
end;
$$;

-- 欠席の取り消し（授業の開始時刻まで）。ストックも消す。振替の申請に使っている間は取り消せない
create or replace function public.cancel_absence(p_contact_id uuid, p_absence_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  a public.class_absences;
  st text;
begin
  perform pg_advisory_xact_lock(hashtext('makeup:student:' || sid::text));
  select * into a from public.class_absences where id = p_absence_id and student_id = sid and status = 'registered' for update;
  if not found or public.class_start(a.class_date, a.start_time) <= public.pickup_now() then
    perform public.pickup_fail('この欠席の連絡は取り消せません（授業の開始時刻を過ぎたか、すでに取り消されています）。');
  end if;
  select status into st from public.makeup_credits where absence_id = a.id for update;
  if st is not null and st <> 'available' then
    perform public.pickup_fail('この欠席の振替ストックは、振替の申請に使われています。先に振替の申請を取り消してください。');
  end if;
  update public.class_absences set status = 'cancelled' where id = a.id;
  update public.makeup_credits set status = 'revoked', note = '欠席の取り消し' where absence_id = a.id;
end;
$$;

-- 自分の振替ストックと、振替の申請（ストックの状態：available / expired / reserved / used / revoked）
create or replace function public.my_makeup(p_contact_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select public.pickup_student_of(p_contact_id) as sid, public.pickup_now()::date as today)
  select jsonb_build_object(
    'credits', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'granted_on', m.granted_on, 'expires_on', m.expires_on,
               'status', case when m.status = 'available' and m.expires_on < me.today then 'expired' else m.status end,
               'from_date', a.class_date, 'from_type', a.class_type, 'note', m.note)
             order by m.expires_on, m.granted_on)
      from public.makeup_credits m left join public.class_absences a on a.id = m.absence_id, me
      where m.student_id = me.sid and m.status <> 'revoked'
        and (m.status = 'reserved'
             or (m.status = 'available' and m.expires_on >= me.today - 90)    -- 期限切れは90日だけ見せる
             or (m.status = 'used' and m.updated_at > now() - interval '90 days'))), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'class_date', r.class_date, 'class_type', r.class_type,
               'start_time', to_char(r.start_time, 'HH24:MI'), 'end_time', to_char(r.end_time, 'HH24:MI'),
               'status', r.status, 'reject_reason', r.reject_reason,
               'can_cancel', r.status in ('pending', 'approved') and public.class_start(r.class_date, r.start_time) > public.pickup_now())
             order by r.class_date, r.start_time)
      from public.makeup_requests r, me
      where r.student_id = me.sid and r.class_date >= me.today - 30), '[]'::jsonb))
  from me;
$$;

-- 振替に申請できる授業（違う学年・開始前・使えるストックの期限内。残り人数つき）
create or replace function public.makeup_options(p_contact_id uuid)
returns table (event_id uuid, class_date date, class_type text, start_time text, end_time text, remaining int, requested boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  own text := public.makeup_own_type(sid);
  now_jst timestamp := public.pickup_now();
  last_day date;
  cap int := (select makeup_capacity from public.makeup_settings where id = 1);
begin
  select max(expires_on) into last_day from public.makeup_credits
   where student_id = sid and status = 'available' and expires_on >= now_jst::date;
  if last_day is null then return; end if;
  return query
  select c.event_id, c.class_date, c.class_type, to_char(c.start_time, 'HH24:MI'), to_char(c.end_time, 'HH24:MI'),
         greatest(cap - public.makeup_load(c.class_date, c.class_type), 0),
         exists (select 1 from public.makeup_requests r where r.student_id = sid and r.class_date = c.class_date
                   and r.class_type = c.class_type and r.status in ('pending', 'approved'))
  from public.makeup_classes(now_jst::date, least(last_day, now_jst::date + 120)) c
  where c.class_type <> own
    and public.class_start(c.class_date, c.start_time) > now_jst
  order by c.class_date, c.start_time, c.class_type;
end;
$$;

-- 振替の申請（振替先の授業の開始時刻まで）。期限が近いストックから使う
create or replace function public.request_makeup(p_contact_id uuid, p_date date, p_type text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  own text := public.makeup_own_type(sid);
  c record;
  cid uuid;
  rid uuid;
begin
  if p_type = own then perform public.pickup_fail('振替は、違う学年の授業にだけ申請できます。'); end if;
  select * into c from public.makeup_classes(p_date, p_date) x where x.class_type = p_type;
  if not found then perform public.pickup_fail('その日の授業が見つかりません。'); end if;
  if public.class_start(c.class_date, c.start_time) <= public.pickup_now() then
    perform public.pickup_fail('その授業は開始時刻を過ぎているため、申請できません。');
  end if;
  perform pg_advisory_xact_lock(hashtext('makeup:class:' || p_date::text || p_type));
  perform pg_advisory_xact_lock(hashtext('makeup:student:' || sid::text));
  if public.makeup_load(p_date, p_type) >= (select makeup_capacity from public.makeup_settings where id = 1) then
    perform public.pickup_fail('その授業は、振替の受け入れ人数がいっぱいです。別の日を選んでください。');
  end if;
  select id into cid from public.makeup_credits
   where student_id = sid and status = 'available' and expires_on >= p_date
   order by expires_on, granted_on limit 1 for update;
  if cid is null then perform public.pickup_fail('この日に使える振替ストックがありません（ストックの期限は、欠席した日から決まっています）。'); end if;
  begin
    insert into public.makeup_requests (student_id, contact_id, credit_id, event_id, class_date, class_type, start_time, end_time)
    values (sid, p_contact_id, cid, c.event_id, c.class_date, c.class_type, c.start_time, c.end_time)
    returning id into rid;
  exception when unique_violation then
    perform public.pickup_fail('この授業には、すでに振替を申請しています。');
  end;
  update public.makeup_credits set status = 'reserved' where id = cid;
  return rid;
end;
$$;

-- 振替の申請の取り消し（振替先の授業の開始時刻まで）。ストックは戻る
create or replace function public.cancel_makeup(p_contact_id uuid, p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  r public.makeup_requests;
begin
  select * into r from public.makeup_requests
   where id = p_request_id and student_id = sid and status in ('pending', 'approved') for update;
  if not found or public.class_start(r.class_date, r.start_time) <= public.pickup_now() then
    perform public.pickup_fail('この振替の申請は取り消せません（授業の開始時刻を過ぎたか、すでに取り消し・却下されています）。');
  end if;
  update public.makeup_requests set status = 'cancelled' where id = r.id;
  update public.makeup_credits set status = 'available' where id = r.credit_id;
end;
$$;

------------------------------------------------------------
-- 5. 管理者の操作
------------------------------------------------------------

-- 振替の申請を承認（ストックは使用済み）
create or replace function public.admin_approve_makeup(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.makeup_requests;
begin
  perform public.pickup_require_admin();
  update public.makeup_requests set status = 'approved' where id = p_request_id and status = 'pending' returning * into r;
  if r.id is null then perform public.pickup_fail('申請中の振替だけ承認できます。'); end if;
  update public.makeup_credits set status = 'used' where id = r.credit_id;
end;
$$;

-- 振替の申請を却下（ストックは戻る）
create or replace function public.admin_reject_makeup(p_request_id uuid, p_reason text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.makeup_requests;
begin
  perform public.pickup_require_admin();
  update public.makeup_requests set status = 'rejected', reject_reason = left(coalesce(p_reason, ''), 200)
   where id = p_request_id and status = 'pending' returning * into r;
  if r.id is null then perform public.pickup_fail('申請中の振替だけ却下できます。'); end if;
  update public.makeup_credits set status = 'available' where id = r.credit_id;
end;
$$;

-- 承認済みの振替を管理者が取り消す（p_return で、ストックを戻すかを選ぶ）
create or replace function public.admin_cancel_makeup(p_request_id uuid, p_return boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.makeup_requests;
begin
  perform public.pickup_require_admin();
  update public.makeup_requests set status = 'cancelled'
   where id = p_request_id and status in ('pending', 'approved') returning * into r;
  if r.id is null then perform public.pickup_fail('申請中・承認済みの振替だけ取り消せます。'); end if;
  update public.makeup_credits set status = case when p_return then 'available' else 'used' end where id = r.credit_id;
end;
$$;

-- ストックを手動で足す（休講の補填など）
create or replace function public.admin_grant_credit(p_student_id uuid, p_note text default '')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := public.pickup_now()::date;
  cid uuid;
begin
  perform public.pickup_require_admin();
  if not exists (select 1 from public.students where id = p_student_id and is_active) then
    perform public.pickup_fail('在籍中の生徒ではありません。');
  end if;
  insert into public.makeup_credits (student_id, granted_on, expires_on, note)
  values (p_student_id, today, (today + make_interval(months => (select credit_valid_months from public.makeup_settings where id = 1)))::date,
          left(coalesce(nullif(p_note, ''), '管理者が追加'), 200))
  returning id into cid;
  return cid;
end;
$$;

-- 使っていないストックを取り消す
create or replace function public.admin_revoke_credit(p_credit_id uuid, p_note text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.pickup_require_admin();
  update public.makeup_credits set status = 'revoked', note = left(coalesce(nullif(p_note, ''), '管理者が取り消し'), 200)
   where id = p_credit_id and status = 'available';
  if not found then perform public.pickup_fail('使える状態のストックだけ取り消せます（申請中・使用済みは取り消せません）。'); end if;
end;
$$;

------------------------------------------------------------
-- 6. 関数の実行権限（既定で誰でも実行できるので、全部剥がしてから与える）
------------------------------------------------------------
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'class_type_of', 'class_start', 'makeup_classes', 'makeup_load', 'makeup_own_type',
      'my_classes', 'register_absence', 'cancel_absence', 'my_makeup', 'makeup_options', 'request_makeup', 'cancel_makeup',
      'admin_approve_makeup', 'admin_reject_makeup', 'admin_cancel_makeup', 'admin_grant_credit', 'admin_revoke_credit')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'admin\_%' then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;

------------------------------------------------------------
-- 7. Realtime（管理画面の通知用）
------------------------------------------------------------
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime が無いため、Realtime の設定はしていません。';
    return;
  end if;
  foreach t in array array['class_absences', 'makeup_requests'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
