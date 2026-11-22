-- Seed Master Data & Pengaturan Referensi (Tanpa Kategori, Tanpa Transaksi / Stok Masih 0)
-- Aman dijalankan di Supabase SQL Editor setelah FULL_SETUP_ALL_IN_ONE.sql atau CLEAR_ALL_DATA.sql.

-- Hapus ketergantungan tabel/kolom kategori bila masih ada dari skema lama
drop view if exists public.inventory_view cascade;
alter table public.items drop column if exists category_id cascade;
drop table if exists public.categories cascade;

create or replace view public.inventory_view with (security_invoker = true) as
select
  v.id as variant_id,
  i.id as item_id,
  i.code,
  i.name,
  i.specification,
  v.size,
  i.unit,
  i.minimum_stock,
  i.return_required,
  i.photo_key,
  coalesce(sum(b.quantity) filter (where b.condition = 'new'), 0) as stock_new,
  coalesce(sum(b.quantity) filter (where b.condition = 'used_good'), 0) as stock_used_good,
  coalesce(sum(b.quantity) filter (where b.condition = 'quarantine'), 0) as stock_quarantine,
  coalesce(sum(b.quantity) filter (where b.condition = 'damaged'), 0) as stock_damaged,
  coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) as total_available,
  case
    when coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) = 0 then 'out'
    when coalesce(sum(b.quantity) filter (where b.condition in ('new', 'used_good')), 0) <= i.minimum_stock then 'low'
    else 'safe'
  end as stock_status
from public.item_variants v
join public.items i on i.id = v.item_id
left join public.stock_balances b on b.variant_id = v.id
where i.active = true and v.active = true
group by v.id, i.id;

grant select on public.inventory_view to authenticated;

do $$
declare
  v_dept_ops uuid;
  v_dept_hse uuid;
  v_dept_mtc uuid;
  v_dept_log uuid;
  v_dept_eng uuid;
  v_it uuid;
begin
  -- 1. Departemen
  insert into public.departments (code, name, active) values
    ('OPS', 'Operasional Produksi', true),
    ('HSE', 'K3 & Keselamatan Kerja', true),
    ('MTC', 'Maintenance & Teknik', true),
    ('LOG', 'Logistik & Gudang', true),
    ('ENG', 'Engineering & Proyek', true)
  on conflict (code) do nothing;

  select id into v_dept_ops from public.departments where code = 'OPS';
  select id into v_dept_hse from public.departments where code = 'HSE';
  select id into v_dept_mtc from public.departments where code = 'MTC';
  select id into v_dept_log from public.departments where code = 'LOG';
  select id into v_dept_eng from public.departments where code = 'ENG';

  -- 2. Petugas Sistem (Penerima, Penyerah, Inspektor, Opname)
  insert into public.system_officers (name, role_label, active) values
    ('Budi Santoso', 'Petugas Gudang / Penerima', true),
    ('Rina Marlina', 'Inspektor K3', true),
    ('Agus Setiawan', 'Admin Inventaris & Opname', true),
    ('Hendra Pratama', 'Petugas Penyerah APD', true)
  on conflict (name) do nothing;

  -- 3. Karyawan
  insert into public.employees (nik, name, position, department_id, contract_status) values
    ('RIA-2024-001', 'Ahmad Fauzi', 'Teknisi Lapangan', v_dept_mtc, 'permanent'),
    ('RIA-2024-002', 'Dedi Kurniawan', 'Operator Produksi', v_dept_ops, 'permanent'),
    ('RIA-2025-014', 'Rina Marlina', 'Safety Inspector', v_dept_hse, 'contract'),
    ('RIA-2025-021', 'Wahyu Hidayat', 'Supervisor Gudang', v_dept_log, 'permanent'),
    ('RIA-2026-005', 'Fajar Nugroho', 'Welder / Teknisi', v_dept_mtc, 'contract'),
    ('RIA-2026-009', 'Rizky Ramadhan', 'Site Engineer', v_dept_eng, 'permanent'),
    ('RIA-2026-012', 'Surya Saputra', 'Helper Proyek', v_dept_ops, 'contract'),
    ('RIA-2026-015', 'Andi Wijaya', 'Mekanik Utility', v_dept_mtc, 'permanent')
  on conflict (nik) do nothing;

  -- 4. Supplier Resmi
  insert into public.suppliers (code, name, vendor_type, contact_name, phone, address, active) values
    ('SUP-01', 'PT Mitra Safety Nusantara', 'supplier', 'Hendra Wijaya', '0812-8890-1122', 'Kawasan Industri Jababeka Blok C2, Cikarang', true),
    ('SUP-02', 'CV Karya Pelindung Jaya', 'supplier', 'Siti Aminah', '0813-4421-9001', 'Jl. Raya Bekasi KM 21, Jakarta Timur', true),
    ('SUP-03', 'PT Proteksi Mandiri Utama', 'supplier', 'Dewi Lestari', '0811-7765-3300', 'Kawasan MM2100 Cikarang Barat', true)
  on conflict (code) do nothing;

  -- 5. Toko Online
  insert into public.suppliers (code, name, vendor_type, contact_name, phone, address, active) values
    ('OL-01', 'Shopee (Official Safety Store)', 'online_shop', 'CS Shopee', null, 'https://shopee.co.id', true),
    ('OL-02', 'Tokopedia (Safety Mart ID)', 'online_shop', 'CS Tokopedia', null, 'https://www.tokopedia.com', true),
    ('OL-03', 'Blibli (Industrial Flagship)', 'online_shop', 'CS Blibli', null, 'https://www.blibli.com', true),
    ('OL-04', 'Lazada (Safety Gear Official)', 'online_shop', 'CS Lazada', null, 'https://www.lazada.co.id', true)
  on conflict (code) do nothing;

  -- 6. Pihak Penalang
  if not exists (select 1 from public.funders where name = 'Kas Operasional Lapangan (Pak Budi)') then
    insert into public.funders (name, phone, notes, active) values
      ('Kas Operasional Lapangan (Pak Budi)', '0811-2233-4455', 'Dana talangan pembelian mendadak / toko online', true);
  end if;
  if not exists (select 1 from public.funders where name = 'Kas Kecil HSE') then
    insert into public.funders (name, phone, notes, active) values
      ('Kas Kecil HSE', '0812-3344-5566', 'Talangan kebutuhan APD K3 mendesak', true);
  end if;

  -- 7. Master Nama APD (tanpa kategori)
  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('HLM-01', 'Helm Safety Proyek ANSI Z89.1', 'Material HDPE tahan benturan + suspensi ratchet', 'pcs', 10, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'HLM-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('SRG-01', 'Sarung Tangan Kulit Las Argon', 'Kulit sapi tahan panas 14 inci', 'pasang', 15, false, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'SRG-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('SRG-02', 'Sarung Tangan Kerja Katun / Nitril', 'Anti slip untuk bongkar muat & assembling', 'pasang', 20, false, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'SRG-02';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('SPT-01', 'Sepatu Safety Steel Toe 200J', 'Kulit asli sol PU anti slip & tahan minyak', 'pasang', 8, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'SPT-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('RMP-01', 'Rompi Safety Reflektif High-Vis', 'Scotchlite 3M + resleting depan', 'pcs', 12, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'RMP-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('KCM-01', 'Kacamata Safety Anti-Fog Clear', 'Lensa polycarbonate UV400 anti gores', 'pcs', 10, false, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'KCM-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('HRN-01', 'Full Body Harness Double Lanyard', 'Absorber hook besar standar EN361', 'set', 4, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'HRN-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('MSK-01', 'Masker Respirator Half-Face + Cartridge', 'Pelindung uap cat, debu logam, dan bahan kimia', 'set', 6, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'MSK-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('EAR-01', 'Earplug Busa Dengan Tali NRR 32dB', 'Pelindung kebisingan area mesin & fabrikasi', 'pasang', 25, false, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'EAR-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;

  insert into public.items (code, name, specification, unit, minimum_stock, return_required, active)
  values ('WRP-01', 'Wearpack Safety Lengan Panjang Reflektif', 'Bahan American Drill dengan pita scotchlite', 'pcs', 8, true, true)
  on conflict (code) do nothing;
  select id into v_it from public.items where code = 'WRP-01';
  insert into public.item_variants (item_id, size, active) values (v_it, '-', true) on conflict (item_id, size) do nothing;
end $$;
