-- Click + Trend initial schema. Apply with: supabase db push
create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum ('super_admin', 'sales', 'content_manager', 'viewer');
create type public.account_type as enum ('client', 'staff');
create type public.lead_status as enum ('new', 'contacted', 'negotiation', 'won', 'lost');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  account_type public.account_type not null default 'client',
  role public.app_role not null default 'viewer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  slug text not null unique, created_at timestamptz not null default now()
);
create table public.portfolio_items (
  id uuid primary key default gen_random_uuid(), title text not null,
  description text, sector text not null default 'أخرى', project_type text not null default 'أخرى',
  category_id uuid references public.categories(id) on delete set null,
  cover_url text, media_urls text[] not null default '{}', is_published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.services (
  id uuid primary key default gen_random_uuid(), title text not null, description text,
  is_active boolean not null default true, sort_order int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.packages (
  id uuid primary key default gen_random_uuid(), title text not null, description text,
  price_label text, price numeric(12,2), currency text not null default 'EGP',
  features text[] not null default '{}', is_active boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint packages_price_nonnegative check (price is null or price >= 0)
);
create table public.leads (
  id uuid primary key default gen_random_uuid(), name text not null check (length(trim(name)) between 2 and 120),
  email text not null check (length(email) <= 254 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'), phone text, company text, sector text,
  message text not null check (length(trim(message)) between 2 and 5000),
  status public.lead_status not null default 'new', assigned_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.contact_requests (
  id uuid primary key default gen_random_uuid(), lead_id uuid references public.leads(id) on delete set null,
  name text not null, email text not null, phone text, message text not null,
  created_at timestamptz not null default now()
);
create table public.chat_rooms (
  id uuid primary key default gen_random_uuid(), client_id uuid not null references public.profiles(id) on delete cascade,
  portfolio_item_id uuid references public.portfolio_items(id) on delete set null,
  assigned_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index chat_rooms_client_project_unique on public.chat_rooms(client_id, coalesce(portfolio_item_id, '00000000-0000-0000-0000-000000000000'::uuid));
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(), room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(), read_at timestamptz
);
create index chat_messages_room_created_idx on public.chat_messages(room_id, created_at);
create table public.internal_notes (
  id uuid primary key default gen_random_uuid(), lead_id uuid references public.leads(id) on delete cascade,
  room_id uuid references public.chat_rooms(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  constraint internal_notes_target_required check (lead_id is not null or room_id is not null)
);
create table public.activity_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id) on delete set null,
  action text not null, entity_type text not null, entity_id uuid, details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index leads_status_created_idx on public.leads(status, created_at desc);
create index portfolio_published_created_idx on public.portfolio_items(is_published, created_at desc);

-- Per-email submission throttle (5 attempts in 10 minutes). Only a digest is retained.
create table public.lead_submission_limits (
  email_digest text primary key,
  window_started_at timestamptz not null default now(),
  request_count int not null default 1
);
alter table public.lead_submission_limits enable row level security;
revoke all on public.lead_submission_limits from anon, authenticated;
create index lead_submission_limits_window_idx on public.lead_submission_limits(window_started_at);
create or replace function public.enforce_lead_submission_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare current_count int;
        email_key text;
begin
  email_key := encode(extensions.digest(lower(trim(new.email)), 'sha256'), 'hex');
  insert into public.lead_submission_limits(email_digest) values (email_key)
    on conflict (email_digest) do update set
      request_count = case when public.lead_submission_limits.window_started_at < now() - interval '10 minutes' then 1 else public.lead_submission_limits.request_count + 1 end,
      window_started_at = case when public.lead_submission_limits.window_started_at < now() - interval '10 minutes' then now() else public.lead_submission_limits.window_started_at end
    returning request_count into current_count;
  if current_count > 5 then raise exception 'Submission limit reached'; end if;
  delete from public.lead_submission_limits where window_started_at < now() - interval '1 day';
  return new;
end;
$$;
create trigger leads_submission_rate_limit before insert on public.leads
  for each row execute function public.enforce_lead_submission_limit();
create trigger contact_requests_submission_rate_limit before insert on public.contact_requests
  for each row execute function public.enforce_lead_submission_limit();

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger portfolio_updated_at before update on public.portfolio_items for each row execute function public.set_updated_at();
create trigger services_updated_at before update on public.services for each row execute function public.set_updated_at();
create trigger packages_updated_at before update on public.packages for each row execute function public.set_updated_at();
create trigger leads_updated_at before update on public.leads for each row execute function public.set_updated_at();
create trigger chat_rooms_updated_at before update on public.chat_rooms for each row execute function public.set_updated_at();

-- User metadata cannot assign a role. New accounts always receive the least privileged role.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, account_type, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), 'client', 'viewer');
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.current_role()
returns public.app_role language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid())
$$;
create or replace function public.has_staff_role(allowed public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_role() = any(allowed), false)
$$;
revoke all on function public.current_role() from public;
revoke all on function public.has_staff_role(public.app_role[]) from public;
grant execute on function public.current_role() to authenticated;
grant execute on function public.has_staff_role(public.app_role[]) to anon, authenticated;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.portfolio_items enable row level security;
alter table public.services enable row level security;
alter table public.packages enable row level security;
alter table public.leads enable row level security;
alter table public.contact_requests enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_messages enable row level security;
alter table public.internal_notes enable row level security;
alter table public.activity_logs enable row level security;

create policy "Profiles are visible to self and sales or admins" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Admins update profiles and role assignments" on public.profiles for update to authenticated
  using (public.has_staff_role(array['super_admin']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin']::public.app_role[]));

create policy "Published portfolio is public" on public.portfolio_items for select to anon, authenticated
  using (is_published or public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Content team manages portfolio" on public.portfolio_items for insert to authenticated
  with check (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Content team updates portfolio" on public.portfolio_items for update to authenticated
  using (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Content team deletes portfolio" on public.portfolio_items for delete to authenticated
  using (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));

create policy "Categories are public" on public.categories for select to anon, authenticated using (true);
create policy "Admins manage categories" on public.categories for all to authenticated
  using (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Active services are public" on public.services for select to anon, authenticated
  using (is_active or public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Admins manage services" on public.services for all to authenticated
  using (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Active packages are public" on public.packages for select to anon, authenticated
  using (is_active or public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Admins manage packages" on public.packages for all to authenticated
  using (public.has_staff_role(array['super_admin']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin']::public.app_role[]));

-- Public intake is insert-only. The public role can never read or update submitted leads.
create policy "Anyone can submit a lead" on public.leads for insert to anon, authenticated
  with check (status = 'new' and assigned_to is null);
create policy "Sales and admins read leads" on public.leads for select to authenticated
  using (public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Sales and admins update leads" on public.leads for update to authenticated
  using (public.has_staff_role(array['super_admin','sales']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Anyone can submit contact request" on public.contact_requests for insert to anon, authenticated with check (true);
create policy "Admins read contact requests" on public.contact_requests for select to authenticated
  using (public.has_staff_role(array['super_admin','sales']::public.app_role[]));

create policy "Clients and staff read chat rooms" on public.chat_rooms for select to authenticated
  using (client_id = (select auth.uid()) or public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Clients and admins create chat rooms" on public.chat_rooms for insert to authenticated
  with check (client_id = (select auth.uid()));
create policy "Staff assign chat rooms" on public.chat_rooms for update to authenticated
  using (public.has_staff_role(array['super_admin','sales']::public.app_role[]))
  with check (public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Room members read messages" on public.chat_messages for select to authenticated
  using (exists (select 1 from public.chat_rooms r where r.id = room_id and (r.client_id = (select auth.uid()) or public.has_staff_role(array['super_admin','sales']::public.app_role[]))));
create policy "Room members send messages" on public.chat_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and exists (select 1 from public.chat_rooms r where r.id = room_id and (r.client_id = (select auth.uid()) or public.has_staff_role(array['super_admin','sales']::public.app_role[]))));
create policy "Staff read internal notes" on public.internal_notes for select to authenticated
  using (public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Staff write internal notes" on public.internal_notes for insert to authenticated
  with check (author_id = (select auth.uid()) and public.has_staff_role(array['super_admin','sales']::public.app_role[]));
create policy "Admins read activity logs" on public.activity_logs for select to authenticated
  using (public.has_staff_role(array['super_admin']::public.app_role[]));
create policy "Staff create activity logs" on public.activity_logs for insert to authenticated
  with check (actor_id = (select auth.uid()) and public.has_staff_role(array['super_admin','sales','content_manager']::public.app_role[]));

-- Avoid trusting a client supplied room id or user id for room creation.
create or replace function public.get_or_create_chat_room(p_portfolio_item_id uuid default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare room_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.chat_rooms(client_id, portfolio_item_id)
    values (auth.uid(), p_portfolio_item_id)
    on conflict (client_id, (coalesce(portfolio_item_id, '00000000-0000-0000-0000-000000000000'::uuid))) do nothing;
  select id into room_id from public.chat_rooms
    where client_id = auth.uid() and portfolio_item_id is not distinct from p_portfolio_item_id;
  return room_id;
end;
$$;
grant execute on function public.get_or_create_chat_room(uuid) to authenticated;

-- Media is public to display only; writes are restricted to the content team.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('portfolio', 'portfolio', true, 15728640, array['image/jpeg','image/png','image/webp','video/mp4'])
on conflict (id) do nothing;
create policy "Portfolio media is publicly readable" on storage.objects for select to anon, authenticated
  using (bucket_id = 'portfolio');
create policy "Content team uploads portfolio media" on storage.objects for insert to authenticated
  with check (bucket_id = 'portfolio' and public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Content team updates portfolio media" on storage.objects for update to authenticated
  using (bucket_id = 'portfolio' and public.has_staff_role(array['super_admin','content_manager']::public.app_role[]))
  with check (bucket_id = 'portfolio' and public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));
create policy "Content team deletes portfolio media" on storage.objects for delete to authenticated
  using (bucket_id = 'portfolio' and public.has_staff_role(array['super_admin','content_manager']::public.app_role[]));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages') then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end;
$$;
