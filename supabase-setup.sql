create table if not exists public.student_responses (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references auth.users(id) on delete set null,
  student_email text not null,
  student_name text not null,
  classroom text not null,
  quest_id text not null,
  quest_title text not null,
  score numeric not null check (score >= 0),
  max_score numeric not null check (max_score > 0),
  score_percent numeric not null check (score_percent >= 0 and score_percent <= 100),
  competencies jsonb not null default '{}'::jsonb,
  answers jsonb,
  source text not null check (source in ('game', 'teacher')),
  created_at timestamptz not null default now(),
  constraint student_responses_score_limit check (score <= max_score)
);

alter table public.student_responses
  add column if not exists student_id uuid references auth.users(id) on delete set null;

create index if not exists student_responses_student_id_created_at_idx
  on public.student_responses (student_id, created_at desc);

alter table public.student_responses enable row level security;

revoke all on table public.student_responses from public, anon, authenticated;
grant select, insert on table public.student_responses to authenticated;

drop policy if exists "Allow anonymous response submissions" on public.student_responses;
drop policy if exists "Allow authenticated response submissions" on public.student_responses;

create table if not exists public.hub_games (
  id text primary key,
  title text not null,
  description text not null default '',
  game_type text not null default 'quiz',
  classrooms text[] not null default array['*']::text[],
  code text,
  url text,
  image_data text,
  updated_at timestamptz not null default now()
);

alter table public.hub_games
  add column if not exists description text not null default '',
  add column if not exists game_type text not null default 'quiz';

alter table public.hub_games enable row level security;
revoke all on table public.hub_games from public, anon, authenticated;
grant select on table public.hub_games to anon, authenticated;
grant insert, update, delete on table public.hub_games to authenticated;

drop policy if exists "Anyone can view published games" on public.hub_games;
create policy "Anyone can view published games"
  on public.hub_games
  for select
  to anon, authenticated
  using (true);

create table if not exists public.hub_teacher_access (
  email text primary key check (email = lower(email))
);

alter table public.hub_teacher_access enable row level security;
revoke all on table public.hub_teacher_access from public, anon, authenticated;

create or replace function public.is_hub_teacher()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.hub_teacher_access
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.is_hub_teacher() from public, anon;
grant execute on function public.is_hub_teacher() to authenticated;

create table if not exists public.game_exercises (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.hub_games(id) on delete cascade,
  level int4 not null,
  problem text not null,
  content jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists game_exercises_game_id_level_idx
  on public.game_exercises (game_id, level);

alter table public.game_exercises enable row level security;
revoke all on table public.game_exercises from public, anon, authenticated;
grant select on table public.game_exercises to anon, authenticated;
grant insert, update, delete on table public.game_exercises to authenticated;

drop policy if exists "Anyone can read game exercises" on public.game_exercises;
create policy "Anyone can read game exercises"
  on public.game_exercises
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Teachers can manage game exercises" on public.game_exercises;
create policy "Teachers can manage game exercises"
  on public.game_exercises
  for all
  to authenticated
  using (public.is_hub_teacher())
  with check (public.is_hub_teacher());

create table if not exists public.student_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.hub_games(id) on delete cascade,
  exercise_id uuid not null references public.game_exercises(id) on delete cascade,
  score int4 not null check (score >= 0),
  student_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists student_answers_user_id_created_at_idx
  on public.student_answers (user_id, created_at desc);

create index if not exists student_answers_game_id_created_at_idx
  on public.student_answers (game_id, created_at desc);

create index if not exists student_answers_exercise_id_idx
  on public.student_answers (exercise_id);

alter table public.student_answers enable row level security;
revoke all on table public.student_answers from public, anon, authenticated;
grant select, insert on table public.student_answers to authenticated;

drop policy if exists "Students can read their own answers" on public.student_answers;
create policy "Students can read their own answers"
  on public.student_answers
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Teachers can read all student answers" on public.student_answers;
create policy "Teachers can read all student answers"
  on public.student_answers
  for select
  to authenticated
  using (public.is_hub_teacher());

drop policy if exists "Students can save their own answers" on public.student_answers;
create policy "Students can save their own answers"
  on public.student_answers
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.game_exercises
      where game_exercises.id = student_answers.exercise_id
        and game_exercises.game_id = student_answers.game_id
    )
  );

create table if not exists public.student_roster (
  email text primary key check (email = lower(email)),
  name text not null,
  classroom text not null,
  updated_at timestamptz not null default now()
);

alter table public.student_roster enable row level security;
revoke all on table public.student_roster from public, anon, authenticated;
grant select, insert, update on table public.student_roster to authenticated;

drop policy if exists "Students and teachers can read authorized roster rows" on public.student_roster;
create policy "Students and teachers can read authorized roster rows"
  on public.student_roster
  for select
  to authenticated
  using (
    public.is_hub_teacher()
    or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );

drop policy if exists "Teachers can add roster rows" on public.student_roster;
create policy "Teachers can add roster rows"
  on public.student_roster
  for insert
  to authenticated
  with check (public.is_hub_teacher());

drop policy if exists "Teachers can update roster rows" on public.student_roster;
create policy "Teachers can update roster rows"
  on public.student_roster
  for update
  to authenticated
  using (public.is_hub_teacher())
  with check (public.is_hub_teacher());

drop policy if exists "Students can read their own responses" on public.student_responses;
create policy "Students can read their own responses"
  on public.student_responses
  for select
  to authenticated
  using (student_id = (select auth.uid()));

drop policy if exists "Teachers can read all responses" on public.student_responses;
create policy "Teachers can read all responses"
  on public.student_responses
  for select
  to authenticated
  using (public.is_hub_teacher());

drop policy if exists "Students can submit their own game responses" on public.student_responses;
create policy "Students can submit their own game responses"
  on public.student_responses
  for insert
  to authenticated
  with check (
    student_id = (select auth.uid())
    and lower(student_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and source = 'game'
    and exists (
      select 1
      from public.student_roster
      where lower(student_roster.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  );

drop policy if exists "Teachers can submit responses" on public.student_responses;
create policy "Teachers can submit responses"
  on public.student_responses
  for insert
  to authenticated
  with check (public.is_hub_teacher());

create or replace function public.link_response_student_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.student_id is null then
    select users.id
      into new.student_id
      from auth.users as users
      where lower(users.email) = lower(new.student_email)
      order by users.created_at
      limit 1;
  end if;
  return new;
end;
$$;

revoke all on function public.link_response_student_account() from public, anon, authenticated;

drop trigger if exists student_responses_link_student_account on public.student_responses;
create trigger student_responses_link_student_account
  before insert on public.student_responses
  for each row
  execute function public.link_response_student_account();

update public.student_responses as responses
  set student_id = users.id
  from auth.users as users
  where responses.student_id is null
    and lower(responses.student_email) = lower(users.email);

drop policy if exists "Teachers can add games" on public.hub_games;
create policy "Teachers can add games"
  on public.hub_games
  for insert
  to authenticated
  with check (public.is_hub_teacher());

drop policy if exists "Teachers can update games" on public.hub_games;
create policy "Teachers can update games"
  on public.hub_games
  for update
  to authenticated
  using (public.is_hub_teacher())
  with check (public.is_hub_teacher());

drop policy if exists "Teachers can delete games" on public.hub_games;
create policy "Teachers can delete games"
  on public.hub_games
  for delete
  to authenticated
  using (public.is_hub_teacher());

insert into public.hub_teacher_access (email)
values ('droeven.jennifer@thillorrain.be')
on conflict (email) do nothing;
