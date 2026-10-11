-- CUPID'S SOCIETY — CUSTOMERS
-- Run once: Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run.

create table if not exists customers (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  handle        text,                -- @instagram
  phone         text,
  email         text,
  birthday      date,
  store_credit  numeric(10,2) not null default 0 check (store_credit >= 0),
  referral_code text unique,
  is_vip        boolean not null default false,
  notes         text,
  created_at    timestamptz not null default now()
);

-- Orders point at a customer. Kept nullable, and set null on delete, so
-- removing a customer never destroys the sales history.
alter table orders add column if not exists customer_id uuid
  references customers(id) on delete set null;

create index if not exists idx_cust_name on customers(lower(name));
create index if not exists idx_ord_cust  on orders(customer_id);

-- Build customers out of the orders already taken. Matches on handle where
-- there is one, otherwise on name, so the same shopper is not duplicated.
insert into customers (name, handle, phone, created_at)
select distinct on (coalesce(lower(o.customer_handle), lower(o.customer_name)))
       o.customer_name,
       o.customer_handle,
       o.customer_phone,
       min(o.created_at) over (
         partition by coalesce(lower(o.customer_handle), lower(o.customer_name)))
from orders o
where o.customer_name is not null
  and o.customer_id is null
  and not exists (
    select 1 from customers c
    where coalesce(lower(c.handle), lower(c.name))
        = coalesce(lower(o.customer_handle), lower(o.customer_name)))
order by coalesce(lower(o.customer_handle), lower(o.customer_name)), o.created_at;

-- Attach every existing order to its customer.
update orders o set customer_id = c.id
from customers c
where o.customer_id is null
  and coalesce(lower(o.customer_handle), lower(o.customer_name))
    = coalesce(lower(c.handle), lower(c.name));

alter table customers enable row level security;

drop policy if exists admin_all on customers;
create policy admin_all on customers for all to authenticated using(true) with check(true);
-- No anon policy: the shop never reads customer records.
