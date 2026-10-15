-- 全民英檢初中級單字文法練習站（已套用在 Supabase 專案 daruma，所有表以 gept_ 開頭，此檔留作備份與重建用）
-- 重建時：在 Supabase 的 SQL Editor 貼上整份執行一次，再執行最後一段把老師 email 加進名單

create table public.gept_teachers (
  email text primary key
);
alter table public.gept_teachers enable row level security;  -- 刻意不開任何 policy：名單不能被 API 讀到

create or replace function public.gept_is_teacher() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.gept_teachers t
    where lower(t.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.gept_is_teacher() from public, anon;
grant execute on function public.gept_is_teacher() to authenticated;

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

-- 學生（匿名）：只能讀題庫、新增自己的成績；看不到任何成績
create policy "gept read words" on public.gept_words for select to anon, authenticated using (true);
create policy "gept read grammar" on public.gept_grammar_questions for select to anon, authenticated using (true);
create policy "gept student insert attempts" on public.gept_attempts for insert to anon, authenticated with check (true);
create policy "gept student insert answers" on public.gept_attempt_answers for insert to anon, authenticated with check (true);

-- 老師（email 在 teachers 名單內才算）：看成績、刪成績、管理題庫
-- 注意：Supabase 預設任何人都能註冊帳號，所以不能只用「已登入」當條件
create policy "gept teacher read attempts" on public.gept_attempts for select to authenticated using (public.gept_is_teacher());
create policy "gept teacher delete attempts" on public.gept_attempts for delete to authenticated using (public.gept_is_teacher());
create policy "gept teacher read answers" on public.gept_attempt_answers for select to authenticated using (public.gept_is_teacher());
create policy "gept teacher manage words" on public.gept_words for all to authenticated using (public.gept_is_teacher()) with check (public.gept_is_teacher());
create policy "gept teacher manage grammar" on public.gept_grammar_questions for all to authenticated using (public.gept_is_teacher()) with check (public.gept_is_teacher());

-- 先收回預設的過大權限，再只給需要的
revoke all on public.gept_teachers, public.gept_words, public.gept_grammar_questions, public.gept_attempts, public.gept_attempt_answers from anon, authenticated;

grant select on public.gept_words, public.gept_grammar_questions to anon, authenticated;
grant insert on public.gept_attempts, public.gept_attempt_answers to anon, authenticated;
grant select, delete on public.gept_attempts to authenticated;
grant select on public.gept_attempt_answers to authenticated;
grant insert, update, delete on public.gept_words, public.gept_grammar_questions to authenticated;

-- 最後一步：把老師登入用的 email 加進名單（改成你自己的信箱再執行）
-- insert into public.gept_teachers(email) values ('你的老師信箱@example.com');
