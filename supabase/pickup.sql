-- 碩学館 送迎予約: スキーマ / RLS / DB関数 / トリガー
-- schema.sql を実行したあとで、Supabase の SQL Editor に貼り付けて実行してください（何度実行しても壊れないようにしてあります）。
-- 設計の説明は docs/pickup-plan.md を参照。

------------------------------------------------------------
-- 1. テーブル
------------------------------------------------------------

-- 設定（1行だけ）
create table if not exists public.pickup_settings (
  id                 int primary key default 1 check (id = 1),
  pickup_place       text not null default '勝瑞駅',
  slot_minutes       int  not null default 15 check (slot_minutes in (5, 10, 15, 30)),  -- 希望時刻の刻み
  trip_minutes       int  not null default 15 check (trip_minutes between 5 and 120),  -- 1便の所要時間（次の便を出せるまで）
  tolerance_minutes  int  not null default 10 check (tolerance_minutes between 0 and 60), -- 相乗りで許容する時刻のずれ
  min_lead_minutes   int  not null default 10 check (min_lead_minutes between 0 and 1440), -- 何分前まで予約・キャンセルできるか
  max_advance_days   int  not null default 60 check (max_advance_days between 1 and 365),  -- 何日先まで予約できるか
  default_capacity   int  not null default 3  check (default_capacity between 1 and 8),
  admin_notify_email text,
  updated_at         timestamptz not null default now()
);
insert into public.pickup_settings (id) values (1) on conflict (id) do nothing;

-- 生徒名簿（管理者が登録。退塾しても消さずに is_active = false）
create table if not exists public.students (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 50),
  grade      text not null default '',
  phone      text not null default '',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 登録コード（生徒ごとに1つ。元のコードは保存せず、sha256 だけ）
create table if not exists public.student_link_codes (
  code_hash  text primary key,
  student_id uuid not null references public.students(id) on delete cascade,
  expires_at timestamptz not null,
  max_uses   int not null default 1,
  used_count int not null default 0,
  created_at timestamptz not null default now()
);

-- 生徒と連絡先（本番は LINE、開発はメール）。機種変更などで作り直すと、前のものは is_active = false になる
create table if not exists public.student_contacts (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references public.students(id) on delete cascade,
  line_user_id text,
  email        text,
  display_name text not null default '',
  is_active    boolean not null default true,
  linked_at    timestamptz not null default now(),
  constraint student_contacts_has_address check (line_user_id is not null or email is not null)
);
create unique index if not exists student_contacts_line_active  on public.student_contacts (line_user_id) where is_active and line_user_id is not null;
create unique index if not exists student_contacts_email_active on public.student_contacts (email)        where is_active and email is not null;
create index if not exists student_contacts_student_idx on public.student_contacts (student_id);

-- 送迎可能時間帯（1つの曜日に複数の時間帯も可。重なりはトリガーで拒否）
create table if not exists public.pickup_availability (
  id           uuid primary key default gen_random_uuid(),
  day_of_week  smallint not null check (day_of_week between 0 and 6),   -- 0 = 日曜
  start_time   time not null,
  end_time     time not null,
  max_capacity int  not null default 3 check (max_capacity between 1 and 8),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint pickup_availability_order check (end_time > start_time)
);

-- 便（＝相乗りグループ。1人だけの便も1グループ）
create table if not exists public.pickup_groups (
  id            uuid primary key default gen_random_uuid(),
  pickup_date   date not null,
  approved_time time not null,
  trip_minutes  int  not null check (trip_minutes between 5 and 120),   -- 作成時の設定値を写す（下の排他制約で使う）
  max_capacity  int  not null check (max_capacity between 1 and 8),
  status        text not null default 'confirmed' check (status in ('proposing', 'confirmed', 'cancelled')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists pickup_groups_date_idx on public.pickup_groups (pickup_date);

-- 車は1台：取り消していない便どうしは、走行時間が重なってはいけない
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pickup_groups_no_overlap') then
    alter table public.pickup_groups add constraint pickup_groups_no_overlap
      exclude using gist (
        tsrange(pickup_date + approved_time,
                pickup_date + approved_time + make_interval(mins => trip_minutes)) with &&
      ) where (status <> 'cancelled');
  end if;
end $$;

-- 予約
create table if not exists public.pickup_reservations (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.students(id),
  contact_id    uuid references public.student_contacts(id),
  pickup_date   date not null,
  pickup_time   time not null,
  approved_time time,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  notes         text not null default '' check (char_length(notes) <= 300),
  reject_reason text not null default '',
  group_id      uuid references public.pickup_groups(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint pickup_res_approved check (status <> 'approved' or (approved_time is not null and group_id is not null))
);
create index if not exists pickup_res_date_idx  on public.pickup_reservations (pickup_date, status);
create index if not exists pickup_res_group_idx on public.pickup_reservations (group_id);
-- 同じ生徒が同じ日に、有効な予約を2件持てない
create unique index if not exists pickup_res_one_per_day
  on public.pickup_reservations (student_id, pickup_date) where status in ('pending', 'approved');

-- 相乗り打診（予約ごとの回答）
create table if not exists public.pickup_proposals (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.pickup_groups(id) on delete cascade,
  reservation_id uuid not null references public.pickup_reservations(id) on delete cascade,
  proposed_time  time not null,
  token_hash     text unique,              -- 開発用の回答リンク（sha256）。本番は LINE の postback なので使わない
  response       text not null default 'waiting' check (response in ('waiting', 'accepted', 'declined', 'expired')),
  responded_at   timestamptz,
  expires_at     timestamptz not null,     -- 送迎時刻の min_lead_minutes 分前
  created_at     timestamptz not null default now(),
  constraint pickup_proposals_one unique (group_id, reservation_id)
);

-- 通知の記録（Edge Function が書き込む。再送や、LINE の無料枠の確認に使う）
create table if not exists public.pickup_notifications (
  id             bigint generated always as identity primary key,
  at             timestamptz not null default now(),
  channel        text not null check (channel in ('email', 'line')),
  kind           text not null,
  reservation_id uuid references public.pickup_reservations(id),
  recipient      text not null,
  ok             boolean not null,
  error          text
);
create index if not exists pickup_notifications_at_idx on public.pickup_notifications (at desc);

------------------------------------------------------------
-- 2. 権限（GRANT）と RLS
--    anon には一切与えない。管理者（authenticated ＋ is_admin()）だけが読み書きできる。
--    利用者の操作は、下の DB 関数を Edge Function（service_role）から呼ぶ形でだけ行う。
------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['pickup_settings', 'students', 'student_link_codes', 'student_contacts', 'pickup_availability',
                           'pickup_groups', 'pickup_reservations', 'pickup_proposals', 'pickup_notifications'] loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_all', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))',
                   t || '_admin_all', t);
  end loop;
end $$;

------------------------------------------------------------
-- 3. 共通の小さな関数
------------------------------------------------------------

-- 日本時間の現在時刻（タイムゾーンなし）
create or replace function public.pickup_now()
returns timestamp
language sql
stable
as $$ select (now() at time zone 'Asia/Tokyo')::timestamp; $$;

create or replace function public.pickup_hash(p text)
returns text
language sql
immutable
as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex'); $$;

-- 利用者に見せるエラー（Edge Function は SQLSTATE PT400 のメッセージだけを、そのまま画面に出す）
create or replace function public.pickup_fail(p_message text)
returns void
language plpgsql
as $$ begin raise exception using errcode = 'PT400', message = p_message; end; $$;

-- その日の予約処理を1件ずつにする（定員・便の重なりの確認と書き込みの間に、割り込ませない）
create or replace function public.pickup_lock_date(p_date date)
returns void
language sql
as $$ select pg_advisory_xact_lock(hashtext('pickup:' || p_date::text)); $$;

-- その時刻を含む時間帯の定員（無ければ設定の既定値）
create or replace function public.pickup_capacity_at(p_date date, p_time time)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select a.max_capacity from public.pickup_availability a
      where a.is_active and a.day_of_week = extract(dow from p_date)::int
        and p_time >= a.start_time and p_time < a.end_time
      order by a.start_time limit 1),
    (select default_capacity from public.pickup_settings where id = 1));
$$;

------------------------------------------------------------
-- 4. 選べる時刻
------------------------------------------------------------

-- その日に選べる時刻と、定員・使用数。group_id があれば、その時刻の既存の便（相乗り便）
--   ・時間帯を slot_minutes 刻みにし、便が時間帯の終わりまでに戻れる時刻だけ（例 16:00-21:00・15分なら最終 20:45）
--   ・今から min_lead_minutes 分以内の時刻は出さない
--   ・既存の便と同じ時刻 → その便の空き。既存の便の走行時間と重なる時刻 → 出さない（車は1台）
--   ・公開済みの「休暇」「休講」の日は出さない
create or replace function public.pickup_slots_internal(p_date date)
returns table (slot_time time, capacity int, used int, group_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  s public.pickup_settings;
  now_jst timestamp := public.pickup_now();
begin
  select * into s from public.pickup_settings where id = 1;
  if p_date is null or p_date < now_jst::date or p_date > now_jst::date + s.max_advance_days then
    return;
  end if;
  if exists (select 1 from public.events e
              where e.event_date = p_date and e.is_published and e.type in ('休暇', '休講')) then
    return;
  end if;

  return query
  with grid as (
    select distinct on (x.st) x.st, w.max_capacity
    from public.pickup_availability w
    cross join lateral (
      select g::time as st
      from generate_series(p_date + w.start_time,
                           p_date + w.end_time - make_interval(mins => s.trip_minutes),
                           make_interval(mins => s.slot_minutes)) g
    ) x
    where w.is_active and w.day_of_week = extract(dow from p_date)::int
    order by x.st, w.start_time
  ), grp as (
    select g.id, g.approved_time, g.trip_minutes, g.max_capacity
    from public.pickup_groups g
    where g.pickup_date = p_date and g.status <> 'cancelled'
  )
  select grid.st,
         coalesce(same.max_capacity, grid.max_capacity),
         ((select count(*) from public.pickup_reservations r
            where same.id is not null and r.group_id = same.id and r.status in ('pending', 'approved'))
        + (select count(*) from public.pickup_reservations r
            where r.pickup_date = p_date and r.pickup_time = grid.st and r.status = 'pending' and r.group_id is null))::int,
         same.id
  from grid
  left join grp same on same.approved_time = grid.st
  where p_date + grid.st > now_jst + make_interval(mins => s.min_lead_minutes)
    and not exists (
      select 1 from grp o
      where o.approved_time <> grid.st
        and p_date + o.approved_time < p_date + grid.st + make_interval(mins => s.trip_minutes)
        and p_date + grid.st < p_date + o.approved_time + make_interval(mins => o.trip_minutes))
  order by grid.st;
end;
$$;

-- 予約フォーム用（誰でも呼べる。人数だけを返し、個人情報は返さない）
create or replace function public.get_pickup_slots(p_date date)
returns table (slot text, remaining int, is_group boolean)
language sql
stable
security definer
set search_path = public
as $$
  select to_char(s.slot_time, 'HH24:MI'), greatest(s.capacity - s.used, 0), s.group_id is not null
  from public.pickup_slots_internal(p_date) s;
$$;

-- 予約フォームの初期表示用（誰でも呼べる）
create or replace function public.get_pickup_info()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'place', s.pickup_place,
    'today', public.pickup_now()::date,
    'max_date', public.pickup_now()::date + s.max_advance_days,
    'min_lead_minutes', s.min_lead_minutes,
    'days', coalesce((select jsonb_agg(distinct a.day_of_week) from public.pickup_availability a where a.is_active), '[]'::jsonb))
  from public.pickup_settings s where s.id = 1;
$$;

------------------------------------------------------------
-- 5. 便の状態をそろえる（打診の回答・予約の取り消しのたびに呼ばれる）
------------------------------------------------------------
create or replace function public.pickup_sync_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.pickup_groups;
begin
  select * into g from public.pickup_groups where id = p_group for update;
  if not found or g.status = 'cancelled' then return; end if;

  if g.status = 'confirmed' then
    -- 確定済みの便に追加された人：時刻が同じ、または打診を承認していれば承認
    update public.pickup_reservations r
       set status = 'approved', approved_time = g.approved_time
     where r.group_id = g.id and r.status = 'pending'
       and (r.pickup_time = g.approved_time
            or exists (select 1 from public.pickup_proposals p
                        where p.group_id = g.id and p.reservation_id = r.id and p.response = 'accepted'));
  elsif exists (select 1 from public.pickup_reservations r where r.group_id = g.id and r.status = 'pending')
    and not exists (
      select 1 from public.pickup_reservations r
      where r.group_id = g.id and r.status = 'pending'
        and not exists (select 1 from public.pickup_proposals p
                         where p.group_id = g.id and p.reservation_id = r.id and p.response = 'accepted')) then
    -- 調整中の便で、残っている全員が承認した → 確定
    update public.pickup_groups set status = 'confirmed' where id = g.id;
    update public.pickup_reservations
       set status = 'approved', approved_time = g.approved_time
     where group_id = g.id and status = 'pending';
  end if;

  -- 乗る人がいなくなった便は取り消す
  if not exists (select 1 from public.pickup_reservations r
                  where r.group_id = g.id and r.status in ('pending', 'approved')) then
    update public.pickup_groups set status = 'cancelled' where id = g.id and status <> 'cancelled';
  end if;
end;
$$;

------------------------------------------------------------
-- 6. トリガー
------------------------------------------------------------

-- updated_at（schema.sql の set_updated_at を使う）
do $$
declare
  t text;
begin
  foreach t in array array['pickup_settings', 'students', 'pickup_availability', 'pickup_groups', 'pickup_reservations'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
                   t || '_set_updated_at', t);
  end loop;
end $$;

-- 変更履歴（schema.sql の log_audit を使う。登録コードと通知の記録は対象外）
do $$
declare
  t text;
begin
  foreach t in array array['pickup_settings', 'students', 'student_contacts', 'pickup_availability',
                           'pickup_groups', 'pickup_reservations', 'pickup_proposals'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.log_audit()',
                   t || '_audit', t);
  end loop;
end $$;

-- 同じ曜日の、有効な時間帯どうしの重なりを拒否
create or replace function public.pickup_availability_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active and exists (
    select 1 from public.pickup_availability a
    where a.id <> new.id and a.is_active and a.day_of_week = new.day_of_week
      and a.start_time < new.end_time and new.start_time < a.end_time) then
    perform public.pickup_fail('同じ曜日に、時間が重なる送迎時間帯があります。');
  end if;
  return new;
end;
$$;
drop trigger if exists pickup_availability_check on public.pickup_availability;
create trigger pickup_availability_check
  before insert or update on public.pickup_availability
  for each row execute function public.pickup_availability_check();

-- 予約の状態の変え方を制限する
--   pending → approved / rejected / cancelled、approved → cancelled だけ。却下・取り消しは最終状態
create or replace function public.pickup_reservation_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and not ((old.status = 'pending'  and new.status in ('approved', 'rejected', 'cancelled'))
           or (old.status = 'approved' and new.status = 'cancelled')) then
    perform public.pickup_fail(format('予約の状態を「%s」から「%s」に変えることはできません。', old.status, new.status));
  end if;
  if old.status in ('rejected', 'cancelled')
     and (new.pickup_date, new.pickup_time, new.group_id) is distinct from (old.pickup_date, old.pickup_time, old.group_id) then
    perform public.pickup_fail('却下・取り消し済みの予約は変更できません。');
  end if;
  return new;
end;
$$;
drop trigger if exists pickup_reservation_transition on public.pickup_reservations;
create trigger pickup_reservation_transition
  before update on public.pickup_reservations
  for each row execute function public.pickup_reservation_transition();

-- 予約が取り消し・却下されたり、便から外れたりしたら、便の状態をそろえる
create or replace function public.pickup_reservation_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.group_id is not null then perform public.pickup_sync_group(old.group_id); end if;
  if new.group_id is not null and new.group_id is distinct from old.group_id then perform public.pickup_sync_group(new.group_id); end if;
  return null;
end;
$$;
drop trigger if exists pickup_reservation_after on public.pickup_reservations;
create trigger pickup_reservation_after
  after update on public.pickup_reservations
  for each row
  when (old.status is distinct from new.status or old.group_id is distinct from new.group_id)
  execute function public.pickup_reservation_after();

-- 打診の回答が変わったら、便の状態をそろえる（全員承認で確定）
create or replace function public.pickup_proposal_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.pickup_sync_group(new.group_id);
  return null;
end;
$$;
drop trigger if exists pickup_proposal_after on public.pickup_proposals;
create trigger pickup_proposal_after
  after update of response on public.pickup_proposals
  for each row
  when (old.response is distinct from new.response)
  execute function public.pickup_proposal_after();

-- 便の時刻を直したら、承認済みの予約の時刻も合わせる
create or replace function public.pickup_group_time_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pickup_reservations set approved_time = new.approved_time
   where group_id = new.id and status = 'approved';
  return null;
end;
$$;
drop trigger if exists pickup_group_time_after on public.pickup_groups;
create trigger pickup_group_time_after
  after update of approved_time on public.pickup_groups
  for each row
  when (old.approved_time is distinct from new.approved_time)
  execute function public.pickup_group_time_after();

------------------------------------------------------------
-- 7. 利用者の操作（Edge Function から service_role で呼ぶ。anon・authenticated は呼べない）
------------------------------------------------------------

-- 登録コードで、生徒と連絡先（LINE またはメール）を結び付ける
create or replace function public.link_student(p_code text, p_line_user_id text, p_email text, p_display_name text default '')
returns table (contact_id uuid, student_id uuid, student_name text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  c public.student_link_codes;
  st public.students;
  new_id uuid;
begin
  if coalesce(p_line_user_id, p_email) is null then perform public.pickup_fail('連絡先がありません。'); end if;
  select * into c from public.student_link_codes
   where code_hash = public.pickup_hash(upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g')))
     and expires_at > now() and used_count < max_uses
   for update;
  if not found then perform public.pickup_fail('登録コードが正しくないか、期限が切れています。'); end if;
  select * into st from public.students where id = c.student_id and is_active;
  if not found then perform public.pickup_fail('この生徒は現在、送迎を予約できません。'); end if;

  -- 同じ LINE（メール）の以前の結び付けと、この生徒の以前の結び付けを無効にする（生徒本人の1アカウントだけ）
  update public.student_contacts
     set is_active = false
   where is_active
     and (student_contacts.student_id = st.id
          or (p_line_user_id is not null and line_user_id = p_line_user_id)
          or (p_email is not null and email = lower(p_email)));
  insert into public.student_contacts (student_id, line_user_id, email, display_name)
  values (st.id, p_line_user_id, lower(p_email), coalesce(p_display_name, ''))
  returning id into new_id;
  update public.student_link_codes set used_count = used_count + 1 where code_hash = c.code_hash;

  return query select new_id, st.id, st.name;
end;
$$;

-- LINE（メール）から、結び付いた生徒を探す
create or replace function public.find_contact(p_line_user_id text, p_email text)
returns table (contact_id uuid, student_id uuid, student_name text, grade text)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, s.id, s.name, s.grade
  from public.student_contacts c
  join public.students s on s.id = c.student_id
  where c.is_active and s.is_active
    and ((p_line_user_id is not null and c.line_user_id = p_line_user_id)
      or (p_email is not null and c.email = lower(p_email)))
  limit 1;
$$;

-- 連絡先から生徒を求める（無効なら利用者向けのエラー）
create or replace function public.pickup_student_of(p_contact_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  select c.student_id into sid
  from public.student_contacts c join public.students s on s.id = c.student_id
  where c.id = p_contact_id and c.is_active and s.is_active;
  if sid is null then perform public.pickup_fail('生徒の登録が確認できません。登録コードを入力し直してください。'); end if;
  return sid;
end;
$$;

-- 予約する
create or replace function public.submit_pickup_reservation(p_contact_id uuid, p_date date, p_time time, p_notes text default '')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := public.pickup_student_of(p_contact_id);
  sl record;
  rid uuid;
begin
  perform public.pickup_lock_date(p_date);
  select * into sl from public.pickup_slots_internal(p_date) s where s.slot_time = p_time;
  if not found then perform public.pickup_fail('その日時は予約できません。時刻を選び直してください。'); end if;
  if sl.used >= sl.capacity then perform public.pickup_fail('その時刻は満席になりました。別の時刻を選んでください。'); end if;
  begin
    insert into public.pickup_reservations (student_id, contact_id, pickup_date, pickup_time, notes)
    values (sid, p_contact_id, p_date, p_time, left(coalesce(p_notes, ''), 300))
    returning id into rid;
  exception when unique_violation then
    perform public.pickup_fail('この日はすでに予約があります。変更する場合は、先に今の予約を取り消してください。');
  end;
  return rid;
end;
$$;

-- 自分の予約（今日以降）と、回答待ちの打診
create or replace function public.my_pickup_reservations(p_contact_id uuid)
returns table (id uuid, pickup_date date, pickup_time text, approved_time text, status text, reject_reason text, notes text,
               proposal_id uuid, proposed_time text, proposal_expires_at timestamptz, can_cancel boolean)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.pickup_date, to_char(r.pickup_time, 'HH24:MI'), to_char(r.approved_time, 'HH24:MI'), r.status, r.reject_reason, r.notes,
         p.id, to_char(p.proposed_time, 'HH24:MI'), p.expires_at,
         r.status in ('pending', 'approved')
           and r.pickup_date + coalesce(r.approved_time, r.pickup_time)
               > public.pickup_now() + make_interval(mins => (select min_lead_minutes from public.pickup_settings where id = 1))
  from public.pickup_reservations r
  left join public.pickup_proposals p
    on p.reservation_id = r.id and p.group_id = r.group_id and p.response = 'waiting' and p.expires_at > now() and r.status = 'pending'
  where r.student_id = public.pickup_student_of(p_contact_id)
    and r.pickup_date >= public.pickup_now()::date
  order by r.pickup_date, r.pickup_time;
$$;

-- 利用者の取り消し（送迎の min_lead_minutes 分前まで）
create or replace function public.cancel_pickup_reservation(p_contact_id uuid, p_reservation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pickup_reservations r
     set status = 'cancelled'
   where r.id = p_reservation_id
     and r.student_id = public.pickup_student_of(p_contact_id)
     and r.status in ('pending', 'approved')
     and r.pickup_date + coalesce(r.approved_time, r.pickup_time)
         > public.pickup_now() + make_interval(mins => (select min_lead_minutes from public.pickup_settings where id = 1));
  if not found then
    perform public.pickup_fail('この予約は取り消せません（送迎の直前、またはすでに取り消し・却下されています）。');
  end if;
end;
$$;

-- 打診への回答（共通部分）
create or replace function public.pickup_apply_response(p_proposal_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  gid uuid;
begin
  update public.pickup_proposals p
     set response = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
    from public.pickup_reservations r, public.pickup_groups g
   where p.id = p_proposal_id and p.response = 'waiting' and p.expires_at > now()
     and r.id = p.reservation_id and r.status = 'pending' and r.group_id = p.group_id
     and g.id = p.group_id and g.status <> 'cancelled'
  returning p.group_id into gid;
  if gid is null then perform public.pickup_fail('この打診には回答できません（期限切れ、または回答済みです）。'); end if;
  return (select status from public.pickup_groups where id = gid);   -- 'confirmed' なら確定した
end;
$$;

-- 打診への回答（本番：LINE から。自分の予約の打診だけ）
create or replace function public.respond_pickup_proposal(p_contact_id uuid, p_proposal_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.pickup_proposals p join public.pickup_reservations r on r.id = p.reservation_id
                  where p.id = p_proposal_id and r.student_id = public.pickup_student_of(p_contact_id)) then
    perform public.pickup_fail('この打診には回答できません。');
  end if;
  return public.pickup_apply_response(p_proposal_id, p_accept);
end;
$$;

-- 打診の表示と回答（開発：メールのリンクのトークンで）
create or replace function public.get_pickup_proposal_by_token(p_token text)
returns table (pickup_date date, pickup_time text, proposed_time text, response text, expires_at timestamptz, student_name text)
language sql
stable
security definer
set search_path = public
as $$
  select r.pickup_date, to_char(r.pickup_time, 'HH24:MI'), to_char(p.proposed_time, 'HH24:MI'),
         case when p.response = 'waiting' and p.expires_at <= now() then 'expired' else p.response end,
         p.expires_at, s.name
  from public.pickup_proposals p
  join public.pickup_reservations r on r.id = p.reservation_id
  join public.students s on s.id = r.student_id
  where p.token_hash = public.pickup_hash(p_token);
$$;

create or replace function public.respond_pickup_proposal_by_token(p_token text, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
begin
  select id into pid from public.pickup_proposals where token_hash = public.pickup_hash(p_token);
  if pid is null then perform public.pickup_fail('このリンクは無効です。'); end if;
  return public.pickup_apply_response(pid, p_accept);
end;
$$;

------------------------------------------------------------
-- 8. 管理者の操作（管理画面から呼ぶ。RLS と is_admin() の確認つき）
------------------------------------------------------------

create or replace function public.pickup_require_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$ begin if not public.is_admin() then raise exception using errcode = '42501', message = '管理者のみ実行できます。'; end if; end; $$;

-- 登録コードを発行する（前のコードは使えなくなる）。8文字、紛らわしい文字（0 O 1 I）は使わない
create or replace function public.issue_link_code(p_student_id uuid, p_valid_days int default 14)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- 32文字
  b bytea := uuid_send(gen_random_uuid());
  idx int[] := array[0, 1, 2, 3, 4, 5, 10, 11];                    -- uuid v4 の固定ビット（6, 8 バイト目）を避ける
  code text := '';
  i int;
begin
  perform public.pickup_require_admin();
  if not exists (select 1 from public.students where id = p_student_id and is_active) then
    perform public.pickup_fail('在籍中の生徒ではありません。');
  end if;
  foreach i in array idx loop
    code := code || substr(alphabet, (get_byte(b, i) % 32) + 1, 1);
  end loop;
  delete from public.student_link_codes where student_id = p_student_id;
  insert into public.student_link_codes (code_hash, student_id, expires_at)
  values (public.pickup_hash(code), p_student_id, now() + make_interval(days => p_valid_days));
  return code;
end;
$$;

-- 便の重なりエラーを、分かる文に直す
create or replace function public.pickup_overlap_message(p_date date, p_time time)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select format('%s の便と時間が重なります（車は1台です）。', to_char(g.approved_time, 'HH24:MI'))
       from public.pickup_groups g
      where g.pickup_date = p_date and g.status <> 'cancelled'
      order by abs(extract(epoch from g.approved_time - p_time)) limit 1),
    'ほかの便と時間が重なります。');
$$;

-- 承認する。p_group を渡すと既存の便（確定済み）に入れる。渡さなければ1人の便を作る（p_time を省略すると希望時刻）
create or replace function public.admin_approve_reservation(p_reservation_id uuid, p_time time default null, p_group uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.pickup_reservations;
  g public.pickup_groups;
  t time;
  gid uuid;
begin
  perform public.pickup_require_admin();
  select * into r from public.pickup_reservations where id = p_reservation_id for update;
  if not found then perform public.pickup_fail('予約が見つかりません。'); end if;
  if r.status <> 'pending' or r.group_id is not null then
    perform public.pickup_fail('未承認（調整中でない）の予約だけ承認できます。');
  end if;
  perform public.pickup_lock_date(r.pickup_date);

  if p_group is not null then
    select * into g from public.pickup_groups
     where id = p_group and pickup_date = r.pickup_date and status = 'confirmed' for update;
    if not found then perform public.pickup_fail('その便には追加できません。'); end if;
    if (select count(*) from public.pickup_reservations where group_id = g.id and status in ('pending', 'approved')) >= g.max_capacity then
      perform public.pickup_fail('その便は満席です。');
    end if;
    update public.pickup_reservations set group_id = g.id, status = 'approved', approved_time = g.approved_time where id = r.id;
    return g.id;
  end if;

  t := coalesce(p_time, r.pickup_time);
  begin
    insert into public.pickup_groups (pickup_date, approved_time, trip_minutes, max_capacity, status)
    values (r.pickup_date, t, (select trip_minutes from public.pickup_settings where id = 1),
            public.pickup_capacity_at(r.pickup_date, t), 'confirmed')
    returning id into gid;
  exception when exclusion_violation then
    perform public.pickup_fail(public.pickup_overlap_message(r.pickup_date, t));
  end;
  update public.pickup_reservations set group_id = gid, status = 'approved', approved_time = t where id = r.id;
  return gid;
end;
$$;

-- 却下する
create or replace function public.admin_reject_reservation(p_reservation_id uuid, p_reason text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.pickup_require_admin();
  update public.pickup_reservations set status = 'rejected', reject_reason = coalesce(p_reason, '')
   where id = p_reservation_id and status = 'pending';
  if not found then perform public.pickup_fail('未承認の予約だけ却下できます。'); end if;
end;
$$;

-- 相乗りを打診する
--   p_group なし：選んだ予約で新しい便（調整中）を p_time に作る
--   p_group あり：確定済みの便に追加する（時刻はその便のまま）
--   希望時刻と同じ人は最初から承認扱い。開発用の回答リンクのトークンを返す（本番では使わない）
create or replace function public.admin_propose_carpool(p_reservation_ids uuid[], p_time time default null, p_group uuid default null)
returns table (reservation_id uuid, proposal_id uuid, token text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  d date;
  n int := coalesce(array_length(p_reservation_ids, 1), 0);
  g public.pickup_groups;
  gid uuid;
  t time := p_time;
  exp timestamptz;
  r public.pickup_reservations;
  tok text;
  pid uuid;
begin
  perform public.pickup_require_admin();
  if n = 0 then perform public.pickup_fail('予約を選んでください。'); end if;
  select min(x.pickup_date) into d from public.pickup_reservations x where x.id = any(p_reservation_ids);
  perform public.pickup_lock_date(d);
  if (select count(*) from public.pickup_reservations x
       where x.id = any(p_reservation_ids) and x.pickup_date = d and x.status = 'pending' and x.group_id is null) <> n then
    perform public.pickup_fail('同じ日の、未承認（調整中でない）の予約だけを選んでください。');
  end if;

  if p_group is null then
    if t is null then perform public.pickup_fail('時刻を入力してください。'); end if;
    if n < 2 then perform public.pickup_fail('相乗りには2件以上の予約を選んでください。'); end if;
    if n > public.pickup_capacity_at(d, t) then perform public.pickup_fail('定員を超えています。'); end if;
    begin
      insert into public.pickup_groups (pickup_date, approved_time, trip_minutes, max_capacity, status)
      values (d, t, (select trip_minutes from public.pickup_settings where id = 1), public.pickup_capacity_at(d, t), 'proposing')
      returning id into gid;
    exception when exclusion_violation then
      perform public.pickup_fail(public.pickup_overlap_message(d, t));
    end;
  else
    select * into g from public.pickup_groups where id = p_group and pickup_date = d and status = 'confirmed' for update;
    if not found then perform public.pickup_fail('その便には追加できません。'); end if;
    if t is not null and t <> g.approved_time then perform public.pickup_fail('既存の便に追加するときは、時刻は変えられません。'); end if;
    t := g.approved_time;
    gid := g.id;
    if (select count(*) from public.pickup_reservations x where x.group_id = gid and x.status in ('pending', 'approved')) + n > g.max_capacity then
      perform public.pickup_fail('定員を超えています。');
    end if;
  end if;

  exp := ((d + t) - make_interval(mins => (select min_lead_minutes from public.pickup_settings where id = 1))) at time zone 'Asia/Tokyo';
  if exp <= now() then
    perform public.pickup_fail('送迎時刻が近すぎて、回答を待てません。電話で確認してから「承認」してください。');
  end if;

  update public.pickup_reservations x set group_id = gid where x.id = any(p_reservation_ids);
  for r in select * from public.pickup_reservations x where x.id = any(p_reservation_ids) order by x.pickup_time loop
    tok := case when r.pickup_time = t then null
                else replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '') end;
    insert into public.pickup_proposals as p (group_id, reservation_id, proposed_time, token_hash, response, responded_at, expires_at)
    values (gid, r.id, t, public.pickup_hash(tok),
            case when tok is null then 'accepted' else 'waiting' end,
            case when tok is null then now() end, exp)
    on conflict (group_id, reservation_id) do update
      set proposed_time = excluded.proposed_time, token_hash = excluded.token_hash, response = excluded.response,
          responded_at = excluded.responded_at, expires_at = excluded.expires_at
    returning p.id into pid;
    reservation_id := r.id; proposal_id := pid; token := tok;
    return next;
  end loop;
  perform public.pickup_sync_group(gid);   -- 全員が希望時刻どおりなら、ここで確定する
end;
$$;

-- 調整中の便の扱いを決める
--   confirm_all   : 電話などで確認できたので、未回答・辞退も含めて全員承認にする
--   drop_declined : 辞退・期限切れの人を便から外す（残りが全員承認なら確定）
--   cancel        : 調整をやめる（全員、便から外れて未承認に戻る）
create or replace function public.admin_resolve_group(p_group uuid, p_action text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.pickup_groups;
begin
  perform public.pickup_require_admin();
  select * into g from public.pickup_groups where id = p_group for update;
  if not found then perform public.pickup_fail('便が見つかりません。'); end if;

  if p_action = 'confirm_all' then
    if g.status = 'cancelled' then perform public.pickup_fail('取り消し済みの便です。'); end if;
    update public.pickup_proposals p set response = 'accepted', responded_at = now()
      from public.pickup_reservations r
     where p.group_id = g.id and p.response <> 'accepted'
       and r.id = p.reservation_id and r.group_id = g.id and r.status = 'pending';
    perform public.pickup_sync_group(g.id);
  elsif p_action = 'drop_declined' then
    if g.status <> 'proposing' then perform public.pickup_fail('調整中の便ではありません。'); end if;
    update public.pickup_reservations r set group_id = null
     where r.group_id = g.id and r.status = 'pending'
       and exists (select 1 from public.pickup_proposals p
                    where p.group_id = g.id and p.reservation_id = r.id
                      and (p.response = 'declined' or (p.response = 'waiting' and p.expires_at <= now()) or p.response = 'expired'));
    perform public.pickup_sync_group(g.id);
  elsif p_action = 'cancel' then
    if g.status <> 'proposing' then perform public.pickup_fail('調整中の便だけ、調整をやめられます。'); end if;
    update public.pickup_groups set status = 'cancelled' where id = g.id;
    update public.pickup_proposals set response = 'expired' where group_id = g.id and response = 'waiting';
    update public.pickup_reservations set group_id = null where group_id = g.id and status = 'pending';
  else
    perform public.pickup_fail('不明な操作です。');
  end if;
  return (select status from public.pickup_groups where id = g.id);
end;
$$;

------------------------------------------------------------
-- 9. 期限切れの処理（pg_cron で5分ごと）
--    ・期限を過ぎた打診 → expired
--    ・時刻を過ぎた調整中の便 → 取り消し（乗る人は未承認に戻る）
--    ・承認されないまま時刻を過ぎた予約 → 却下（期限切れ）
------------------------------------------------------------
create or replace function public.expire_pickups()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  update public.pickup_proposals set response = 'expired' where response = 'waiting' and expires_at <= now();
  with gone as (
    update public.pickup_groups set status = 'cancelled'
     where status = 'proposing' and pickup_date + approved_time <= public.pickup_now()
    returning id)
  update public.pickup_reservations r set group_id = null
    from gone where r.group_id = gone.id and r.status = 'pending';
  update public.pickup_reservations set status = 'rejected', reject_reason = '期限切れ'
   where status = 'pending' and pickup_date + pickup_time <= public.pickup_now();
  get diagnostics n = row_count;
  return n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
      perform cron.schedule('pickup-expire', '*/5 * * * *', 'select public.expire_pickups()');
    exception when others then
      raise notice 'pg_cron の登録に失敗しました（%）。Dashboard の Integrations → Cron で有効にしてから、もう一度実行してください。', sqlerrm;
    end;
  else
    raise notice 'pg_cron が使えないため、期限切れの自動処理は登録していません。';
  end if;
end $$;

------------------------------------------------------------
-- 10. 関数の実行権限
--     Postgres は関数を既定で誰でも実行できるので、全部剥がしてから与える。
------------------------------------------------------------
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'pickup\_%' or p.proname in (
        'get_pickup_slots', 'get_pickup_info', 'link_student', 'find_contact', 'submit_pickup_reservation',
        'my_pickup_reservations', 'cancel_pickup_reservation', 'respond_pickup_proposal',
        'get_pickup_proposal_by_token', 'respond_pickup_proposal_by_token', 'issue_link_code',
        'admin_approve_reservation', 'admin_reject_reservation', 'admin_propose_carpool', 'admin_resolve_group', 'expire_pickups'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('get_pickup_slots', 'get_pickup_info') then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    elsif f.proname in ('issue_link_code', 'admin_approve_reservation', 'admin_reject_reservation',
                        'admin_propose_carpool', 'admin_resolve_group') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;

------------------------------------------------------------
-- 11. Realtime（管理画面の通知用）
--     予約と打診の変更を、ログイン中の管理者の画面にすぐ届ける。届く行は RLS で管理者だけに絞られる。
------------------------------------------------------------
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime が無いため、Realtime の設定はしていません。';
    return;
  end if;
  foreach t in array array['pickup_reservations', 'pickup_proposals'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
