alter table public.purchases alter column created_by drop not null;
alter table public.issuances alter column created_by drop not null;
alter table public.returns alter column created_by drop not null;
alter table public.reimbursements alter column created_by drop not null;
alter table public.stocktakes alter column created_by drop not null;
alter table public.stock_movements alter column created_by drop not null;
