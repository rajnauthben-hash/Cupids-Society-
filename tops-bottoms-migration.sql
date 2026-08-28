-- CUPID'S SOCIETY — ADD TOPS & BOTTOMS
-- Run once: Supabase → SQL Editor → New query → paste → Run.
-- Safe to re-run.

alter table products drop constraint if exists products_sub_check;
alter table products add  constraint products_sub_check
  check (sub in ('all','dresses','tops','bottoms','jumpsuits','two-piece',
                 'bikini','monokini','cover-ups'));
