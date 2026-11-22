-- KOSONGKAN SEMUA ISI TABEL (Tanpa menghapus struktur tabel, view, fungsi, atau enum)
-- Jalankan di Supabase SQL Editor untuk mengosongkan seluruh data transaksi & master data.

truncate table
  public.procurement_payments,
  public.procurement_items,
  public.procurements,
  public.opening_stock_items,
  public.opening_stocks,
  public.stock_movements,
  public.stocktake_items,
  public.stocktakes,
  public.reimbursements,
  public.return_items,
  public.returns,
  public.issuance_items,
  public.issuances,
  public.purchase_items,
  public.purchases,
  public.stock_balances,
  public.item_variants,
  public.items,
  public.funders,
  public.suppliers,
  public.employees,
  public.departments,
  public.system_officers
restart identity cascade;

-- Reset penomoran dokumen kembali ke 1
alter sequence if exists public.purchase_no_seq restart with 1;
alter sequence if exists public.issuance_no_seq restart with 1;
alter sequence if exists public.return_no_seq restart with 1;
alter sequence if exists public.stocktake_no_seq restart with 1;
alter sequence if exists public.opening_stock_no_seq restart with 1;
alter sequence if exists public.procurement_no_seq restart with 1;
alter sequence if exists public.po_no_seq restart with 1;
