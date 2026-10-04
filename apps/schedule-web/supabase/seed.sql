-- 初期データ: 2026年度の1月分（= 2027年1月）＋冬期休暇
-- schema.sql の実行後に、SQL Editor で実行してください。
-- 高3=月木 / 高1=火金 / 高2=水土 / 1/29・30は休講 / 12/29〜1/4は冬期休暇
-- 授業時間 18:30〜21:40 は仮の値です。管理画面から修正できます。
-- ※ 2回実行すると重複するので、1回だけ実行してください。

-- 冬期休暇 2026-12-29 〜 2027-01-04
insert into public.events (event_date, type, title, is_published)
select d::date, '休暇', '冬期休暇', true
from generate_series('2026-12-29'::date, '2027-01-04'::date, interval '1 day') as d;

-- 休講 1/29・1/30
insert into public.events (event_date, type, title, is_published)
values ('2027-01-29', '休講', '休講', true),
       ('2027-01-30', '休講', '休講', true);

-- 授業（1/5〜1/31、日曜と休講日を除く）
insert into public.events (event_date, type, title, start_time, end_time, is_published)
select d::date,
       case extract(dow from d)::int
         when 1 then '高3授業' when 4 then '高3授業'
         when 2 then '高1授業' when 5 then '高1授業'
         when 3 then '高2授業' when 6 then '高2授業'
       end,
       case extract(dow from d)::int
         when 1 then '高3授業' when 4 then '高3授業'
         when 2 then '高1授業' when 5 then '高1授業'
         when 3 then '高2授業' when 6 then '高2授業'
       end,
       '18:30', '21:40', true
from generate_series('2027-01-05'::date, '2027-01-31'::date, interval '1 day') as d
where extract(dow from d)::int <> 0
  and d::date not in ('2027-01-29', '2027-01-30');
