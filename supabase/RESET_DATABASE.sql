-- RESET DATABASE SUPABASE (Menghapus seluruh tabel, view, fungsi, sequence, & enum Inventaris APD)
-- Aman dijalankan di Supabase SQL Editor karena tidak menghapus skema internal auth/storage.
-- Setelah menjalankan script ini, jalankan FULL_SETUP_ALL_IN_ONE.sql untuk membuat ulang dari awal.

drop trigger if exists on_auth_user_created on auth.users;

drop view if exists public.procurement_progress_view cascade;
drop view if exists public.inventory_view cascade;

drop table if exists public.procurement_payments cascade;
drop table if exists public.procurement_items cascade;
drop table if exists public.procurements cascade;
drop table if exists public.opening_stock_items cascade;
drop table if exists public.opening_stocks cascade;
drop table if exists public.system_officers cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.stocktake_items cascade;
drop table if exists public.stocktakes cascade;
drop table if exists public.reimbursements cascade;
drop table if exists public.return_items cascade;
drop table if exists public.returns cascade;
drop table if exists public.issuance_items cascade;
drop table if exists public.issuances cascade;
drop table if exists public.purchase_items cascade;
drop table if exists public.purchases cascade;
drop table if exists public.stock_balances cascade;
drop table if exists public.item_variants cascade;
drop table if exists public.items cascade;
drop table if exists public.categories cascade;
drop table if exists public.funders cascade;
drop table if exists public.suppliers cascade;
drop table if exists public.employees cascade;
drop table if exists public.departments cascade;
drop table if exists public.profiles cascade;

drop function if exists public.allocate_issuance_line(uuid, uuid, text, numeric, text, text, timestamptz, uuid) cascade;
drop function if exists public.update_procurement_payment(uuid, jsonb, uuid) cascade;
drop function if exists public.update_stocktake(uuid, jsonb, uuid) cascade;
drop function if exists public.update_return(uuid, jsonb, uuid) cascade;
drop function if exists public.update_issuance(uuid, jsonb, uuid) cascade;
drop function if exists public.update_purchase_receipt(uuid, jsonb, uuid) cascade;
drop function if exists public.update_procurement(uuid, jsonb, uuid) cascade;
drop function if exists public.update_opening_stock(uuid, jsonb, uuid) cascade;
drop function if exists public.create_stocktake(jsonb, uuid) cascade;
drop function if exists public.transfer_stock_condition(jsonb, uuid) cascade;
drop function if exists public.create_procurement_payment(jsonb, uuid) cascade;
drop function if exists public.create_procurement(jsonb, uuid) cascade;
drop function if exists public.create_opening_stock(jsonb, uuid) cascade;
drop function if exists public.dashboard_summary(int, int) cascade;
drop function if exists public.finalize_stocktake(uuid, uuid) cascade;
drop function if exists public.create_reimbursement(jsonb, uuid) cascade;
drop function if exists public.create_return(jsonb, uuid) cascade;
drop function if exists public.create_issuance(jsonb, uuid) cascade;
drop function if exists public.create_purchase_receipt(jsonb, uuid) cascade;
drop function if exists public.apply_stock_movement(uuid, public.stock_condition, numeric, text, text, uuid, uuid, text, timestamptz) cascade;
drop function if exists public.next_document_no(text, regclass) cascade;
drop function if exists public.current_user_role() cascade;
drop function if exists public.handle_new_user() cascade;
drop function if exists public.touch_updated_at() cascade;

drop sequence if exists public.po_no_seq cascade;
drop sequence if exists public.procurement_no_seq cascade;
drop sequence if exists public.opening_stock_no_seq cascade;
drop sequence if exists public.stocktake_no_seq cascade;
drop sequence if exists public.return_no_seq cascade;
drop sequence if exists public.issuance_no_seq cascade;
drop sequence if exists public.purchase_no_seq cascade;

drop type if exists public.inspection_result cascade;
drop type if exists public.stocktake_status cascade;
drop type if exists public.reimbursement_status cascade;
drop type if exists public.payment_method cascade;
drop type if exists public.funding_source cascade;
drop type if exists public.stock_condition cascade;
drop type if exists public.user_role cascade;
