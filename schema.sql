-- 全民英檢初中級單字文法練習站（已套用在 Supabase 專案 daruma，所有表以 gept_ 開頭，此檔留作備份與重建用）
-- 老師後台用「老師密碼」驗證（不需要帳號）。重建時：整份貼到 SQL Editor 執行，最後一段再設定密碼。
-- 注意：已在 daruma 套用的資料庫另外還留有舊版的 gept_teachers / gept_is_teacher（email 名單，已不使用），
-- 全新重建時不需要那兩個。

create table public.gept_words (
  id bigint generated always as identity primary key,
  word text not null,
  pos text default '',
  meaning text not null,
  level text not null default 'elementary' check (level in ('elementary','intermediate')),
  unique (word, meaning)
);

create table public.gept_grammar_questions (
  id bigint generated always as identity primary key,
  question text not null,
  opt_a text not null,
  opt_b text not null,
  opt_c text not null,
  opt_d text not null,
  answer smallint not null check (answer between 0 and 3), -- 0=A 1=B 2=C 3=D
  explanation text default '',
  topic text default '',
  level text not null default 'elementary' check (level in ('elementary','intermediate'))
);

create table public.gept_attempts (
  id uuid primary key default gen_random_uuid(),
  student_name text not null check (char_length(student_name) between 1 and 40),
  mode text not null,          -- vocab / grammar / mixed / wrong
  level text not null,         -- elementary / intermediate / all
  total int not null check (total between 1 and 200),
  correct int not null,
  score int not null check (score between 0 and 100),
  duration_sec int default 0,
  created_at timestamptz not null default now(),
  check (correct between 0 and total)
);

create table public.gept_attempt_answers (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.gept_attempts(id) on delete cascade,
  qtype text not null,         -- vocab_en2zh / vocab_zh2en / grammar
  qid bigint not null,
  prompt text not null check (char_length(prompt) <= 500),
  chosen text check (char_length(chosen) <= 500),
  correct_answer text not null check (char_length(correct_answer) <= 500),
  is_correct boolean not null
);

create index idx_gept_answers_attempt on public.gept_attempt_answers(attempt_id);
create index idx_gept_attempts_created on public.gept_attempts(created_at desc);

alter table public.gept_words enable row level security;
alter table public.gept_grammar_questions enable row level security;
alter table public.gept_attempts enable row level security;
alter table public.gept_attempt_answers enable row level security;

-- 學生（匿名）：只能讀題庫、新增自己的成績；完全看不到成績
create policy "gept read words" on public.gept_words for select to anon, authenticated using (true);
create policy "gept read grammar" on public.gept_grammar_questions for select to anon, authenticated using (true);
create policy "gept student insert attempts" on public.gept_attempts for insert to anon, authenticated with check (true);
create policy "gept student insert answers" on public.gept_attempt_answers for insert to anon, authenticated with check (true);

revoke all on public.gept_words, public.gept_grammar_questions, public.gept_attempts, public.gept_attempt_answers from anon, authenticated;
grant select on public.gept_words, public.gept_grammar_questions to anon, authenticated;
grant insert on public.gept_attempts, public.gept_attempt_answers to anon, authenticated;

-- 老師密碼（只存加密後的雜湊）與錯誤次數紀錄，API 完全讀不到
create table public.gept_admin_secret (id int primary key check (id = 1), hash text not null);
create table public.gept_admin_fail (id bigint generated always as identity primary key, ip text not null, ts timestamptz not null default now());
alter table public.gept_admin_secret enable row level security;
alter table public.gept_admin_fail enable row level security;
revoke all on public.gept_admin_secret, public.gept_admin_fail from anon, authenticated;
create index on public.gept_admin_fail (ip, ts);

-- 驗證密碼：回傳 'ok' / 'bad' / 'locked'（同一個 IP 10 分鐘內錯 10 次就鎖住）；不分大小寫
create or replace function public.gept_code_ok(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_hash text; v_ip text; v_hdr text;
begin
  v_hdr := current_setting('request.headers', true);
  begin
    v_ip := nullif(btrim(split_part(coalesce((v_hdr::json) ->> 'x-forwarded-for', ''), ',', 1)), '');
  exception when others then
    v_ip := null;
  end;
  v_ip := coalesce(v_ip, 'unknown');
  if (select count(*) from public.gept_admin_fail where ip = v_ip and ts > now() - interval '10 minutes') >= 10 then
    return 'locked';
  end if;
  select s.hash into v_hash from public.gept_admin_secret s where s.id = 1;
  if v_hash is not null and p_code is not null and extensions.crypt(upper(btrim(p_code)), v_hash) = v_hash then
    return 'ok';
  end if;
  insert into public.gept_admin_fail(ip) values (v_ip);
  return 'bad';
end $$;

create or replace function public.gept_admin_login(p_code text) returns text
language sql security definer set search_path = '' as $$ select public.gept_code_ok(p_code); $$;

create or replace function public.gept_admin_list_attempts(p_code text) returns setof public.gept_attempts
language plpgsql security definer set search_path = '' as $$
begin
  if public.gept_code_ok(p_code) <> 'ok' then return; end if;
  return query select * from public.gept_attempts order by created_at desc limit 2000;
end $$;

create or replace function public.gept_admin_get_answers(p_code text, p_attempt uuid) returns setof public.gept_attempt_answers
language plpgsql security definer set search_path = '' as $$
begin
  if public.gept_code_ok(p_code) <> 'ok' then return; end if;
  return query select * from public.gept_attempt_answers a where a.attempt_id = p_attempt order by a.id;
end $$;

create or replace function public.gept_admin_wrong_stats(p_code text)
returns table(qtype text, qid bigint, prompt text, correct_answer text, n bigint, w bigint)
language plpgsql security definer set search_path = '' as $$
begin
  if public.gept_code_ok(p_code) <> 'ok' then return; end if;
  return query
    select a.qtype, a.qid, min(a.prompt), min(a.correct_answer), count(*), count(*) filter (where not a.is_correct)
    from public.gept_attempt_answers a
    group by a.qtype, a.qid;
end $$;

create or replace function public.gept_admin_import_words(p_code text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if public.gept_code_ok(p_code) <> 'ok' then return -1; end if;
  if jsonb_array_length(p_rows) > 1000 then return -2; end if;
  insert into public.gept_words(word, pos, meaning, level)
  select btrim(r ->> 'word'), coalesce(r ->> 'pos', ''), btrim(r ->> 'meaning'), coalesce(r ->> 'level', 'elementary')
  from jsonb_array_elements(p_rows) as r
  where nullif(btrim(r ->> 'word'), '') is not null and nullif(btrim(r ->> 'meaning'), '') is not null
  on conflict (word, meaning) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.gept_admin_import_grammar(p_code text, p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if public.gept_code_ok(p_code) <> 'ok' then return -1; end if;
  if jsonb_array_length(p_rows) > 1000 then return -2; end if;
  insert into public.gept_grammar_questions(question, opt_a, opt_b, opt_c, opt_d, answer, explanation, topic, level)
  select r ->> 'question', r ->> 'opt_a', r ->> 'opt_b', r ->> 'opt_c', r ->> 'opt_d', (r ->> 'answer')::smallint,
         coalesce(r ->> 'explanation', ''), coalesce(r ->> 'topic', ''), coalesce(r ->> 'level', 'elementary')
  from jsonb_array_elements(p_rows) as r
  where nullif(btrim(r ->> 'question'), '') is not null
    and not exists (select 1 from public.gept_grammar_questions g where g.question = r ->> 'question');
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.gept_code_ok(text), public.gept_admin_login(text), public.gept_admin_list_attempts(text),
  public.gept_admin_get_answers(text, uuid), public.gept_admin_wrong_stats(text),
  public.gept_admin_import_words(text, jsonb), public.gept_admin_import_grammar(text, jsonb) from public;
grant execute on function public.gept_admin_login(text), public.gept_admin_list_attempts(text),
  public.gept_admin_get_answers(text, uuid), public.gept_admin_wrong_stats(text),
  public.gept_admin_import_words(text, jsonb), public.gept_admin_import_grammar(text, jsonb) to anon, authenticated;

-- 最後一步：設定（或更換）老師密碼。把 你的新密碼 改掉再執行；英文不分大小寫
-- insert into public.gept_admin_secret(id, hash) values (1, extensions.crypt(upper('你的新密碼'), extensions.gen_salt('bf', 8)))
--   on conflict (id) do update set hash = excluded.hash;
