-- CUPID'S SOCIETY — SUPABASE SCHEMA  (SQL Editor → New query → Run)
create table if not exists products (
  id uuid primary key default gen_random_uuid(),slug text not null unique,name text not null,
  tag text,cat text not null default 'clothing' check(cat in('clothing','swimwear','thrift')),
  sub text not null default 'all' check(sub in('all','dresses','jumpsuits','two-piece','bikini','monokini','cover-ups')),
  color text,price_ttd numeric(10,2) not null default 0 check(price_ttd>=0),
  price_usd numeric(10,2) not null default 0 check(price_usd>=0),
  description text,details text,care text,featured boolean not null default false,sort_order int not null default 0,
  status text not null default 'active' check(status in('active','draft','archived')),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists variants (
  id uuid primary key default gen_random_uuid(),product_id uuid not null references products(id) on delete cascade,
  size text not null,stock int not null default 0 check(stock>=0),created_at timestamptz not null default now(),unique(product_id,size));
create table if not exists product_images (
  id uuid primary key default gen_random_uuid(),product_id uuid not null references products(id) on delete cascade,
  url text not null,storage_path text,is_primary boolean not null default false,sort_order int not null default 0,created_at timestamptz not null default now());
create sequence if not exists order_ref_seq;
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique default('CS-'||to_char(now(),'YYMMDD')||'-'||lpad(nextval('order_ref_seq')::text,4,'0')),
  source text not null default 'cart_checkout' check(source in('cart_checkout','product_page','instagram','manual','in_person')),
  status text not null default 'pending' check(status in('pending','confirmed','cancelled')),
  currency text not null default 'TTD' check(currency in('TTD','USD')),
  customer_name text,customer_handle text,customer_phone text,note text,
  subtotal numeric(10,2) not null default 0,created_at timestamptz not null default now(),confirmed_at timestamptz);
create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,variant_id uuid references variants(id) on delete set null,
  product_name text not null,size text,unit_price numeric(10,2) not null default 0,qty int not null default 1 check(qty>0));
create index if not exists idx_v_prod on variants(product_id);create index if not exists idx_i_prod on product_images(product_id);
create index if not exists idx_oi_ord on order_items(order_id);create index if not exists idx_ord_st on orders(status,created_at desc);
create or replace function touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now();return new;end $$;
drop trigger if exists trg_products_touch on products;create trigger trg_products_touch before update on products for each row execute function touch_updated_at();
create or replace function confirm_order(p_order_id uuid) returns orders language plpgsql security definer set search_path=public as $$
declare o orders;begin
  if auth.role() is distinct from 'authenticated' then raise exception 'Not authorised';end if;
  select * into o from orders where id=p_order_id for update;
  if not found then raise exception 'Order not found';end if;
  if o.status='confirmed' then return o;end if;
  update variants v set stock=greatest(0,v.stock-i.qty) from order_items i where i.order_id=p_order_id and i.variant_id=v.id;
  update orders set status='confirmed',confirmed_at=now() where id=p_order_id returning * into o;return o;end $$;
create or replace function unconfirm_order(p_order_id uuid) returns orders language plpgsql security definer set search_path=public as $$
declare o orders;begin
  if auth.role() is distinct from 'authenticated' then raise exception 'Not authorised';end if;
  select * into o from orders where id=p_order_id for update;
  if not found then raise exception 'Order not found';end if;
  if o.status<>'confirmed' then return o;end if;
  update variants v set stock=v.stock+i.qty from order_items i where i.order_id=p_order_id and i.variant_id=v.id;
  update orders set status='pending',confirmed_at=null where id=p_order_id returning * into o;return o;end $$;
alter table products enable row level security;alter table product_images enable row level security;
alter table variants enable row level security;alter table orders enable row level security;alter table order_items enable row level security;
drop policy if exists admin_all on products;create policy admin_all on products for all to authenticated using(true) with check(true);
drop policy if exists admin_all on product_images;create policy admin_all on product_images for all to authenticated using(true) with check(true);
drop policy if exists admin_all on variants;create policy admin_all on variants for all to authenticated using(true) with check(true);
drop policy if exists admin_all on orders;create policy admin_all on orders for all to authenticated using(true) with check(true);
drop policy if exists admin_all on order_items;create policy admin_all on order_items for all to authenticated using(true) with check(true);
drop policy if exists public_read on products;create policy public_read on products for select to anon using(status='active');
drop policy if exists public_read on product_images;create policy public_read on product_images for select to anon using(exists(select 1 from products p where p.id=product_id and p.status='active'));
drop policy if exists public_read on variants;create policy public_read on variants for select to anon using(exists(select 1 from products p where p.id=product_id and p.status='active'));
drop policy if exists public_create_pending on orders;create policy public_create_pending on orders for insert to anon with check(status='pending' and source in('cart_checkout','product_page') and confirmed_at is null);
drop policy if exists public_create_items on order_items;create policy public_create_items on order_items for insert to anon with check(exists(select 1 from orders o where o.id=order_id and o.status='pending'));
insert into storage.buckets(id,name,public) values('product-images','product-images',true) on conflict(id) do nothing;
drop policy if exists img_anon_r on storage.objects;create policy img_anon_r on storage.objects for select to anon using(bucket_id='product-images');
drop policy if exists img_auth_r on storage.objects;create policy img_auth_r on storage.objects for select to authenticated using(bucket_id='product-images');
drop policy if exists img_auth_w on storage.objects;create policy img_auth_w on storage.objects for all to authenticated using(bucket_id='product-images') with check(bucket_id='product-images');
insert into products(slug,name,tag,cat,sub,color,price_ttd,price_usd,featured,sort_order,description,details,care) values
('crystal-night-mini','Crystal Night Mini','New In','clothing','dresses','Silver',850,125,true,1,'Turn every waterfront into your runway. This crystal-encrusted mini dress catches light with every move — designed for those who refuse to go unnoticed.','Crystal embellished mini dress. Fully lined. Square neckline with chain-link shoulder straps.','Dry clean only. Store flat to protect crystals.'),
('blush-bandage','Blush Bandage Dress','Bestseller','clothing','dresses','Blush Pink',750,110,true,2,'Daydream in pink. Walk like you know it. The structured bandage silhouette hugs with intention — built for the woman who commands every room she enters.','Bandage mini dress. Stretch construction. V-neckline. Body-con fit.','Hand wash cold. Lay flat to dry.'),
('white-ruched-mini','White Ruched Mini','New In','clothing','dresses','White',720,106,true,3,'Clean lines. Bold silhouette. The white ruched mini brings sophistication to every occasion — structured where it counts, effortless where it matters.','Ruched bodycon mini dress. Underwire bust. Spaghetti straps. Fully lined.','Hand wash cold. Do not tumble dry.'),
('black-cat-unitard','Black Cat Unitard','New In','clothing','jumpsuits','Black',780,115,true,4,'Own every room, every street, every moment. The Black Cat Unitard pairs with anything and commands everything. For the woman who moves like she knows she''s the main character.','Full-length unitard. Sweetheart neckline. Spaghetti straps. Stretch fabric.','Machine wash cold. Hang dry.'),
('stripe-paradise','Stripe Paradise Set','Resort Wear','swimwear','bikini-sets','Pink/White',650,95,false,5,'Pool days, your way. Pink and white stripe triangle set with the Cupid Society signature — chosen for those who bring the energy wherever they go.','Triangle bikini top with adjustable ties. Matching brief bottoms. CS logo patch.','Hand wash. Rinse after salt or chlorinated water.'),
('pink-horizon','Pink Horizon Bikini','New In','swimwear','bikini-sets','Pink/Black',700,103,false,6,'Emerge from the water like the main character. Bold pink with black trim — for the woman who makes dusk look like golden hour.','Scoop neck bikini top with black binding. High-cut briefs with ring hardware. Cupid''s Society logo.','Hand wash. Do not tumble dry.'),
('thrifted-slip','Thrifted Silk Slip','One of One','thrift','all','Champagne',400,59,false,7,'A one-of-one find, hand-selected and restyled. Pre-loved with the same Cupid Society standard — because sustainable can still be sexy.','Secondhand silk slip dress, thrifted and quality-checked. Only one available.','Hand wash cold. Hang dry.')
on conflict(slug) do nothing;
insert into variants(product_id,size,stock) select p.id,s.size,case when p.slug='thrifted-slip' then 1 else 5 end
  from products p cross join lateral(select unnest(case when p.slug='thrifted-slip' then array['S','M'] else array['XS','S','M','L','XL'] end) as size) s
on conflict(product_id,size) do nothing;

-- LOOKBOOK (see lookbook-migration.sql; kept here so the schema file stays complete)
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

-- SUBCATEGORY UPDATE (see subcategories-migration.sql)

-- 1. Widen the allowed values first, so nothing is rejected mid-way.
alter table products drop constraint if exists products_sub_check;
alter table products add  constraint products_sub_check
  check (sub in ('all','dresses','jumpsuits','two-piece',
                 'bikini','monokini','cover-ups','bikini-sets'));

-- 2. Move anything still filed under the retired value.
update products set sub = 'bikini' where sub = 'bikini-sets';

-- 3. Now drop the retired value for good.
alter table products drop constraint if exists products_sub_check;
alter table products add  constraint products_sub_check
  check (sub in ('all','dresses','jumpsuits','two-piece',
                 'bikini','monokini','cover-ups'));

-- TOPS & BOTTOMS (see tops-bottoms-migration.sql)
alter table products drop constraint if exists products_sub_check;
alter table products add  constraint products_sub_check
  check (sub in ('all','dresses','tops','bottoms','jumpsuits','two-piece',
                 'bikini','monokini','cover-ups'));
