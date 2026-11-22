-- Seed Dummy Data Lengkap untuk Inventaris APD (PT Ria Industri)
-- Jalankan file ini di Supabase SQL Editor SETELAH menjalankan seluruh file di folder supabase/migrations/

do $$
declare
  v_cat_head uuid; v_cat_hand uuid; v_cat_foot uuid; v_cat_body uuid; v_cat_eye uuid; v_cat_fall uuid;
  v_dept_ops uuid; v_dept_hse uuid; v_dept_mtc uuid; v_dept_log uuid;
  v_sup_1 uuid; v_sup_2 uuid; v_sup_3 uuid;
  v_fund_1 uuid;
  v_emp_1 uuid; v_emp_2 uuid; v_emp_3 uuid; v_emp_4 uuid; v_emp_5 uuid;
  v_it_hlm uuid; v_it_spt uuid; v_it_srg uuid; v_it_rmp uuid; v_it_kcm uuid; v_it_hrn uuid;
  v_var_hlm uuid; v_var_spt41 uuid; v_var_spt42 uuid; v_var_srg uuid; v_var_rmp_l uuid; v_var_rmp_xl uuid; v_var_kcm uuid; v_var_hrn uuid;
  v_proc_1 uuid; v_proc_2 uuid; v_proc_3 uuid;
  v_pi_1a uuid; v_pi_2a uuid; v_pi_2b uuid;
  v_iss_1 uuid; v_iss_2 uuid;
  v_ii_1a uuid; v_ii_2a uuid;
begin
  -- Cegah duplikasi jika seed sudah pernah dijalankan
  if exists (select 1 from public.items where code = 'HLM-01') then
    raise notice 'Dummy data sudah ada, melewati seed.';
    return;
  end if;

  -- 1. Kategori APD
  insert into public.categories (code, name) values ('APD-KPL', 'Pelindung Kepala') returning id into v_cat_head;
  insert into public.categories (code, name) values ('APD-TGN', 'Pelindung Tangan') returning id into v_cat_hand;
  insert into public.categories (code, name) values ('APD-KKI', 'Pelindung Kaki') returning id into v_cat_foot;
  insert into public.categories (code, name) values ('APD-BDN', 'Pelindung Tubuh & Rompi') returning id into v_cat_body;
  insert into public.categories (code, name) values ('APD-MTA', 'Pelindung Mata & Wajah') returning id into v_cat_eye;
  insert into public.categories (code, name) values ('APD-KTG', 'Pelindung Ketinggian') returning id into v_cat_fall;

  -- 2. Departemen
  insert into public.departments (code, name, active) values ('OPS', 'Operasional Produksi', true) returning id into v_dept_ops;
  insert into public.departments (code, name, active) values ('HSE', 'K3 & Keselamatan Kerja', true) returning id into v_dept_hse;
  insert into public.departments (code, name, active) values ('MTC', 'Maintenance & Teknik', true) returning id into v_dept_mtc;
  insert into public.departments (code, name, active) values ('LOG', 'Logistik & Gudang', true) returning id into v_dept_log;

  -- 3. Petugas Sistem
  insert into public.system_officers (name, role_label, active) values
    ('Budi Santoso', 'Petugas Gudang / Penerima', true),
    ('Rina Marlina', 'Inspektor K3', true),
    ('Agus Setiawan', 'Admin Inventaris & Opname', true),
    ('Hendra Pratama', 'Petugas Penyerah APD', true)
  on conflict (name) do nothing;

  -- 4. Supplier
  insert into public.suppliers (code, name, contact_name, phone, address, active)
  values ('SUP-01', 'PT Mitra Safety Nusantara', 'Hendra Wijaya', '0812-8890-1122', 'Kawasan Industri Jababeka Blok C2', true)
  returning id into v_sup_1;
  insert into public.suppliers (code, name, contact_name, phone, address, active)
  values ('SUP-02', 'CV Karya Pelindung Jaya', 'Siti Aminah', '0813-4421-9001', 'Jl. Raya Bekasi KM 21', true)
  returning id into v_sup_2;
  insert into public.suppliers (code, name, contact_name, phone, address, active)
  values ('SUP-03', 'PT Proteksi Mandiri Utama', 'Dewi Lestari', '0811-7765-3300', 'Kawasan MM2100 Cikarang', true)
  returning id into v_sup_3;

  -- 5. Pihak Penalang
  insert into public.funders (name, phone, notes, active)
  values ('Kas Operasional Lapangan (Pak Budi)', '0811-2233-4455', 'Talangan pembelian cepat proyek', true)
  returning id into v_fund_1;

  -- 6. Karyawan
  insert into public.employees (nik, name, position, department_id, contract_status)
  values ('RIA-2024-001', 'Ahmad Fauzi', 'Teknisi Lapangan', v_dept_mtc, 'permanent') returning id into v_emp_1;
  insert into public.employees (nik, name, position, department_id, contract_status)
  values ('RIA-2024-002', 'Dedi Kurniawan', 'Operator Produksi', v_dept_ops, 'permanent') returning id into v_emp_2;
  insert into public.employees (nik, name, position, department_id, contract_status)
  values ('RIA-2025-014', 'Rina Marlina', 'Safety Inspector', v_dept_hse, 'contract') returning id into v_emp_3;
  insert into public.employees (nik, name, position, department_id, contract_status)
  values ('RIA-2025-021', 'Wahyu Hidayat', 'Supervisor Gudang', v_dept_log, 'permanent') returning id into v_emp_4;
  insert into public.employees (nik, name, position, department_id, contract_status)
  values ('RIA-2026-005', 'Fajar Nugroho', 'Welder / Teknisi', v_dept_mtc, 'contract') returning id into v_emp_5;

  -- 7. Master Barang & Varian Ukuran
  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('HLM-01', 'Helm Safety Proyek ANSI Z89.1', v_cat_head, 'HDPE tahan benturan + suspensi ratchet', 'pcs', 10, true, true) returning id into v_it_hlm;
  insert into public.item_variants (item_id, size) values (v_it_hlm, 'All Size') returning id into v_var_hlm;

  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('SPT-01', 'Sepatu Safety Steel Toe 200J', v_cat_foot, 'Kulit asli anti slip & tahan minyak', 'pasang', 8, true, true) returning id into v_it_spt;
  insert into public.item_variants (item_id, size) values (v_it_spt, '41') returning id into v_var_spt41;
  insert into public.item_variants (item_id, size) values (v_it_spt, '42') returning id into v_var_spt42;

  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('SRG-01', 'Sarung Tangan Kulit Las Argon', v_cat_hand, 'Kulit sapi tahan panas 14 inci', 'pasang', 15, false, true) returning id into v_it_srg;
  insert into public.item_variants (item_id, size) values (v_it_srg, 'L') returning id into v_var_srg;

  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('RMP-01', 'Rompi Safety Reflektif High-Vis', v_cat_body, 'Scotchlite 3M + resleting depan', 'pcs', 12, true, true) returning id into v_it_rmp;
  insert into public.item_variants (item_id, size) values (v_it_rmp, 'L') returning id into v_var_rmp_l;
  insert into public.item_variants (item_id, size) values (v_it_rmp, 'XL') returning id into v_var_rmp_xl;

  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('KCM-01', 'Kacamata Safety Anti-Fog Clear', v_cat_eye, 'Polycarbonate UV400 anti gores', 'pcs', 10, false, true) returning id into v_it_kcm;
  insert into public.item_variants (item_id, size) values (v_it_kcm, 'All Size') returning id into v_var_kcm;

  insert into public.items (code, name, category_id, specification, unit, minimum_stock, return_required, active)
  values ('HRN-01', 'Full Body Harness Double Lanyard', v_cat_fall, 'Absorber hook besar standar EN361', 'set', 4, true, true) returning id into v_it_hrn;
  insert into public.item_variants (item_id, size) values (v_it_hrn, 'All Size') returning id into v_var_hrn;

  -- 8. Stok Awal (Saldo yang sudah ada sebelumnya)
  perform public.create_opening_stock(jsonb_build_object(
    'recordedAt', (current_date - interval '14 days')::date,
    'officerName', 'Agus Setiawan',
    'notes', 'Saldo awal gudang APD sebelum implementasi sistem',
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_hlm, 'condition', 'new', 'quantity', 25, 'notes', 'Rak A-01'),
      jsonb_build_object('variantId', v_var_hlm, 'condition', 'used_good', 'quantity', 6, 'notes', 'Bekas layak siap pakai'),
      jsonb_build_object('variantId', v_var_spt41, 'condition', 'new', 'quantity', 12, 'notes', 'Rak B-01'),
      jsonb_build_object('variantId', v_var_spt42, 'condition', 'new', 'quantity', 6, 'notes', 'Stok menipis perlu restock'),
      jsonb_build_object('variantId', v_var_srg, 'condition', 'new', 'quantity', 30, 'notes', 'Rak C-02'),
      jsonb_build_object('variantId', v_var_rmp_l, 'condition', 'new', 'quantity', 18, 'notes', 'Rak D-01'),
      jsonb_build_object('variantId', v_var_rmp_xl, 'condition', 'new', 'quantity', 9, 'notes', 'Menipis'),
      jsonb_build_object('variantId', v_var_kcm, 'condition', 'new', 'quantity', 20, 'notes', 'Rak E-01'),
      jsonb_build_object('variantId', v_var_hrn, 'condition', 'new', 'quantity', 5, 'notes', 'Lemari K3')
    )
  ), null);

  -- 9. Pengadaan Barang (3 skenario: Selesai & Lunas, Sebagian & DP, Menunggu & Talangan)
  v_proc_1 := public.create_procurement(jsonb_build_object(
    'procurementDate', (current_date - interval '10 days')::date,
    'expectedDate', (current_date - interval '5 days')::date,
    'poNumber', 'PO-2026-101',
    'prNumber', 'PR-2026-041',
    'departmentId', v_dept_hse,
    'supplierId', v_sup_1,
    'reason', 'Restock Helm Safety & Rompi Proyek Q4',
    'fundingSource', 'company',
    'paymentMethod', 'transfer',
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_hlm, 'orderedQuantity', 15, 'unitPrice', 125000),
      jsonb_build_object('variantId', v_var_rmp_xl, 'orderedQuantity', 10, 'unitPrice', 85000)
    )
  ), null);

  v_proc_2 := public.create_procurement(jsonb_build_object(
    'procurementDate', (current_date - interval '4 days')::date,
    'expectedDate', (current_date + interval '3 days')::date,
    'poNumber', 'PO-2026-108',
    'prNumber', 'PR-2026-048',
    'departmentId', v_dept_mtc,
    'supplierId', v_sup_2,
    'reason', 'Pengadaan Sepatu Safety Steel Toe & Body Harness',
    'fundingSource', 'company',
    'paymentMethod', 'transfer',
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_spt42, 'orderedQuantity', 10, 'unitPrice', 385000),
      jsonb_build_object('variantId', v_var_hrn, 'orderedQuantity', 4, 'unitPrice', 650000)
    )
  ), null);

  v_proc_3 := public.create_procurement(jsonb_build_object(
    'procurementDate', (current_date - interval '1 day')::date,
    'expectedDate', (current_date + interval '4 days')::date,
    'poNumber', 'PO-2026-112',
    'departmentId', v_dept_ops,
    'supplierId', v_sup_3,
    'reason', 'Pembelian Mendesak Kacamata & Sarung Tangan Las',
    'fundingSource', 'advanced',
    'paymentMethod', 'cash',
    'funderId', v_fund_1,
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_kcm, 'orderedQuantity', 20, 'unitPrice', 45000),
      jsonb_build_object('variantId', v_var_srg, 'orderedQuantity', 15, 'unitPrice', 65000)
    )
  ), null);

  -- 10. Barang Masuk dari Pengadaan 1 (100% Lengkap) & Pengadaan 2 (Parsial 7/14 -> 50%)
  select id into v_pi_1a from public.procurement_items where procurement_id = v_proc_1 and variant_id = v_var_hlm limit 1;
  perform public.create_purchase_receipt(jsonb_build_object(
    'procurementId', v_proc_1,
    'receivedDate', (current_date - interval '6 days')::date,
    'supplierId', v_sup_1,
    'reason', 'Penerimaan lengkap PO-2026-101',
    'items', (
      select jsonb_agg(jsonb_build_object(
        'procurementItemId', pi.id,
        'variantId', pi.variant_id,
        'quantity', pi.ordered_quantity,
        'condition', 'new',
        'receiverName', 'Budi Santoso'
      )) from public.procurement_items pi where pi.procurement_id = v_proc_1
    )
  ), null);

  select id into v_pi_2a from public.procurement_items where procurement_id = v_proc_2 and variant_id = v_var_spt42 limit 1;
  select id into v_pi_2b from public.procurement_items where procurement_id = v_proc_2 and variant_id = v_var_hrn limit 1;
  perform public.create_purchase_receipt(jsonb_build_object(
    'procurementId', v_proc_2,
    'receivedDate', (current_date - interval '2 days')::date,
    'supplierId', v_sup_2,
    'reason', 'Penerimaan tahap 1 PO-2026-108',
    'items', jsonb_build_array(
      jsonb_build_object('procurementItemId', v_pi_2a, 'variantId', v_var_spt42, 'quantity', 5, 'condition', 'new', 'receiverName', 'Budi Santoso'),
      jsonb_build_object('procurementItemId', v_pi_2b, 'variantId', v_var_hrn, 'quantity', 2, 'condition', 'new', 'receiverName', 'Budi Santoso')
    )
  ), null);

  -- 11. Pembayaran Pengadaan (Pengadaan 1 Lunas, Pengadaan 2 DP 40%)
  perform public.create_procurement_payment(jsonb_build_object(
    'procurementId', v_proc_1, 'paidAt', (current_date - interval '5 days')::date,
    'amount', 2725000, 'paymentMethod', 'transfer', 'paymentType', 'full',
    'referenceNo', 'TRF-BCA-20261114', 'notes', 'Pelunasan PO-2026-101'
  ), null);

  perform public.create_procurement_payment(jsonb_build_object(
    'procurementId', v_proc_2, 'paidAt', (current_date - interval '3 days')::date,
    'amount', 2500000, 'paymentMethod', 'transfer', 'paymentType', 'dp',
    'referenceNo', 'TRF-MDR-20261116', 'notes', 'DP termin 1 PO-2026-108'
  ), null);

  -- 12. Barang Keluar ke Karyawan
  v_iss_1 := public.create_issuance(jsonb_build_object(
    'issuedAt', (current_date - interval '5 days')::date,
    'employeeId', v_emp_1,
    'officerName', 'Hendra Pratama',
    'notes', 'Pemakaian proyek maintenance panel',
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_hlm, 'condition', 'new', 'quantity', 3, 'purpose', 'Tim Maintenance Area B'),
      jsonb_build_object('variantId', v_var_hrn, 'condition', 'new', 'quantity', 2, 'purpose', 'Pekerjaan ketinggian atap')
    )
  ), null);

  v_iss_2 := public.create_issuance(jsonb_build_object(
    'issuedAt', (current_date - interval '3 days')::date,
    'employeeId', v_emp_5,
    'officerName', 'Hendra Pratama',
    'notes', 'Perlengkapan kerja las',
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_srg, 'condition', 'new', 'quantity', 4, 'purpose', 'Pengelasan struktur'),
      jsonb_build_object('variantId', v_var_spt41, 'condition', 'new', 'quantity', 2, 'purpose', 'Sepatu kerja bengkel')
    )
  ), null);

  -- 13. Pengembalian APD (1 Layak Pakai masuk Bekas Layak, 1 Karantina)
  select id into v_ii_1a from public.issuance_items where issuance_id = v_iss_1 and variant_id = v_var_hlm limit 1;
  select id into v_ii_2a from public.issuance_items where issuance_id = v_iss_2 and variant_id = v_var_spt41 limit 1;

  perform public.create_return(jsonb_build_object(
    'returnedAt', (current_date - interval '2 days')::date,
    'employeeId', v_emp_1,
    'inspectorName', 'Rina Marlina',
    'items', jsonb_build_array(
      jsonb_build_object('issuanceItemId', v_ii_1a, 'quantity', 1, 'inspectionResult', 'used_good', 'reason', 'Selesai tugas, kondisi bersih layak pakai'),
      jsonb_build_object('issuanceItemId', v_ii_1a, 'quantity', 1, 'inspectionResult', 'maintenance', 'reason', 'Tali suspensi perlu dicuci')
    )
  ), null);

  perform public.create_return(jsonb_build_object(
    'returnedAt', (current_date - interval '1 day')::date,
    'employeeId', v_emp_5,
    'inspectorName', 'Rina Marlina',
    'items', jsonb_build_array(
      jsonb_build_object('issuanceItemId', v_ii_2a, 'quantity', 1, 'inspectionResult', 'damaged', 'reason', 'Sol sepatu robek terkena percikan las')
    )
  ), null);

  -- 14. Stok Opname (+/-) dengan selisih Surplus (+) dan Hilang (-)
  perform public.create_stocktake(jsonb_build_object(
    'officerName', 'Agus Setiawan',
    'finalizeNow', true,
    'items', jsonb_build_array(
      jsonb_build_object('variantId', v_var_kcm, 'condition', 'new', 'physicalQuantity', 22, 'reason', 'Ditemukan 2 pcs cadangan di lemari HSE (+)'),
      jsonb_build_object('variantId', v_var_rmp_l, 'condition', 'new', 'physicalQuantity', 16, 'reason', 'Selisih 2 pcs hilang di area loading (-)')
    )
  ), null);

  raise notice 'Dummy data APD lengkap berhasil dimasukkan!';
end $$;
