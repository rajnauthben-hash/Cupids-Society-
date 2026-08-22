-- CUPID'S SOCIETY — LOOKBOOK IMAGES
-- Run once: Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run; every statement guards itself.

create table if not exists lookbook_images (
  id            uuid primary key default gen_random_uuid(),
  image_url     text not null,
  caption       text,
  display_order int not null default 0,
  is_active     boolean not null default true,
  storage_path  text,                       -- lets the admin delete the file, not just the row
  created_at    timestamptz not null default now()
);

create index if not exists idx_lb_order on lookbook_images(display_order);

alter table lookbook_images enable row level security;

-- Admin (signed in) does everything; the public storefront reads only live rows.
drop policy if exists admin_all   on lookbook_images;
create policy admin_all   on lookbook_images for all    to authenticated using(true) with check(true);
drop policy if exists public_read on lookbook_images;
create policy public_read on lookbook_images for select to anon using(is_active);

-- Storage bucket for the lookbook files.
insert into storage.buckets(id,name,public)
  values('lookbook-images','lookbook-images',true) on conflict(id) do nothing;

drop policy if exists lb_anon_r on storage.objects;
create policy lb_anon_r on storage.objects for select to anon
  using(bucket_id='lookbook-images');
drop policy if exists lb_auth_r on storage.objects;
create policy lb_auth_r on storage.objects for select to authenticated
  using(bucket_id='lookbook-images');
drop policy if exists lb_auth_w on storage.objects;
create policy lb_auth_w on storage.objects for all to authenticated
  using(bucket_id='lookbook-images') with check(bucket_id='lookbook-images');
