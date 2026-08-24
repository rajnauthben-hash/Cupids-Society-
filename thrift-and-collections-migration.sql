-- CUPID'S SOCIETY — THRIFT FLAG + LOOKBOOK COLLECTIONS
-- Run once: Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run.

-- =====================================================================
-- 1. THRIFT
-- The site marks thrift with a flag and still wants a real category
-- underneath (a thrifted bikini is swimwear AND thrift). The admin was
-- storing thrift as the category itself, so those pieces never showed
-- on the Thrift page. Add the flag and convert anything already saved.
-- =====================================================================
alter table products add column if not exists is_thrift boolean not null default false;

-- Anything filed as cat='thrift' becomes clothing + thrift flag.
update products set is_thrift = true,  cat = 'clothing' where cat = 'thrift';

-- Category is now only the two real ones.
alter table products drop constraint if exists products_cat_check;
alter table products add  constraint products_cat_check
  check (cat in ('clothing','swimwear'));

create index if not exists idx_prod_thrift on products(is_thrift);

-- =====================================================================
-- 2. LOOKBOOK COLLECTIONS
-- Photos are grouped into named collections shown on the Lookbook page.
-- =====================================================================
create table if not exists lookbook_collections (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  display_order int not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

alter table lookbook_images
  add column if not exists collection_id uuid
  references lookbook_collections(id) on delete cascade;

create index if not exists idx_lb_coll on lookbook_images(collection_id);
create index if not exists idx_lbc_order on lookbook_collections(display_order);

alter table lookbook_collections enable row level security;

drop policy if exists admin_all   on lookbook_collections;
create policy admin_all   on lookbook_collections for all    to authenticated using(true) with check(true);
drop policy if exists public_read on lookbook_collections;
create policy public_read on lookbook_collections for select to anon using(is_active);
