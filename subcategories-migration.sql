-- CUPID'S SOCIETY — SUBCATEGORY UPDATE
-- Adds Two-piece (clothing) and splits Bikini Sets into Bikini + Monokini.
-- Run once: Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run.

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
