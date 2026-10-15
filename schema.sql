-- 全民英檢初中級單字文法練習站：在 Supabase 的 SQL Editor 貼上整份執行一次即可

create table if not exists words (
  id bigint generated always as identity primary key,
  word text not null,
  pos text default '',
  meaning text not null,
  level text not null default 'elementary' check (level in ('elementary','intermediate')),
  unique (word, meaning)
);

create table if not exists grammar_questions (
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

create table if not exists attempts (
  id bigint generated always as identity primary key,
  student_name text not null,
  mode text not null,          -- vocab / grammar / mixed
  level text not null,         -- elementary / intermediate / all
  total int not null,
  correct int not null,
  score int not null,          -- 0~100
  duration_sec int default 0,
  created_at timestamptz not null default now()
);

create table if not exists attempt_answers (
  id bigint generated always as identity primary key,
  attempt_id bigint not null references attempts(id) on delete cascade,
  qtype text not null,         -- vocab_en2zh / vocab_zh2en / grammar
  qid bigint not null,
  prompt text not null,
  chosen text,
  correct_answer text not null,
  is_correct boolean not null
);

create index if not exists idx_answers_attempt on attempt_answers(attempt_id);
create index if not exists idx_attempts_created on attempts(created_at desc);

alter table words enable row level security;
alter table grammar_questions enable row level security;
alter table attempts enable row level security;
alter table attempt_answers enable row level security;

-- 學生（匿名）：可讀題庫、可新增成績，不能讀別人的成績
create policy "anon read words" on words for select to anon, authenticated using (true);
create policy "anon read grammar" on grammar_questions for select to anon, authenticated using (true);
create policy "anon insert attempts" on attempts for insert to anon, authenticated with check (true);
create policy "anon insert answers" on attempt_answers for insert to anon, authenticated with check (true);

-- 老師（登入後）：可看全部成績、可管理題庫
create policy "teacher read attempts" on attempts for select to authenticated using (true);
create policy "teacher delete attempts" on attempts for delete to authenticated using (true);
create policy "teacher read answers" on attempt_answers for select to authenticated using (true);
create policy "teacher write words" on words for all to authenticated using (true) with check (true);
create policy "teacher write grammar" on grammar_questions for all to authenticated using (true) with check (true);
