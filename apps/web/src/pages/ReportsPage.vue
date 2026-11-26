<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { AlertTriangle, CalendarRange, CheckSquare, Download, Edit3, Eye, FileDown, Printer, RefreshCw, RotateCcw, Search, Trash2 } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import { api, attachmentUrl, conditionLabel, downloadCsv, formatCurrency, formatDate, formatNumber, imageUrlToDataUrl, invalidateApiCache, variantLabel } from '@/lib/api'
import type { PdfSectionTable } from '@/lib/pdf-report'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

type ReportSectionKey = 'stock' | 'movements' | 'procurements' | 'opname' | 'liabilities' | 'payments'
type ReportTab = 'all' | ReportSectionKey

const router = useRouter()
const master = useMasterStore()
const toast = useToast()

const activeTab = ref<ReportTab>('all')
const loading = ref(true)
const loadError = ref('')

// Universal Row Preview Modal
const showRowPreview = ref(false)
const rowPreviewTitle = ref('')
const rowPreviewEyebrow = ref('')
const rowPreviewFields = ref<Array<{ label: string; value: string }>>([])

function openRowPreview(eyebrow: string, title: string, fields: Array<{ label: string; value: string }>) {
  rowPreviewEyebrow.value = eyebrow
  rowPreviewTitle.value = title
  rowPreviewFields.value = fields
  showRowPreview.value = true
}

const dateFrom = ref('')
const dateTo = ref('')
const activePreset = ref<'all' | 'month' | '30d' | 'custom'>('all')
const search = ref('')
const supplierFilter = ref('all')
const employeeFilter = ref('all')
const departmentFilter = ref('all')
const itemFilter = ref('all')

const selectedSections = reactive<Record<ReportSectionKey, boolean>>({
  stock: true,
  movements: true,
  procurements: true,
  liabilities: true,
  opname: true,
  payments: true,
})

const sectionList: Array<{ key: ReportSectionKey; label: string }> = [
  { key: 'stock', label: 'Stok Tersedia Saat Ini' },
  { key: 'movements', label: 'Mutasi / Arus APD' },
  { key: 'procurements', label: 'Pengadaan & Progress' },
  { key: 'opname', label: 'Stok Opname (+/-)' },
  { key: 'liabilities', label: 'Tanggungan Karyawan' },
  { key: 'payments', label: 'History Pembayaran' },
]

const allSectionsSelected = computed(() =>
  sectionList.every((s) => selectedSections[s.key]),
)

function toggleSelectAllSections() {
  const next = !allSectionsSelected.value
  for (const s of sectionList) {
    selectedSections[s.key] = next
  }
}

const movements = ref<Array<{ id: number; variant_id?: string; occurred_at: string; movement_type: string; condition: string; quantity_delta: number; balance_after: number; notes: string | null; item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null }>>([])
const procurements = ref<Array<{ id: string; procurement_no: string; procurement_date: string; po_number: string | null; supplier_name: string; department_name?: string | null; total_ordered: number; total_received: number; progress_percent: number; total_amount: number; paid_amount: number; payment_status: string; status: string }>>([])
const stocktakes = ref<Array<{ id: string; stocktake_no: string; reference_at: string; officer_name: string; status: string; stocktake_items: Array<{ variant_id?: string; condition: string; system_quantity: number; physical_quantity: number; reason: string | null; item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null }> }>>([])
const liabilities = ref<Array<{
  id?: string; issuance_id?: string; variant_id?: string; quantity: number; returned_quantity: number; resolved_lost_quantity: number; purpose: string;
  issuances?: { id?: string; transaction_no: string; issued_at: string; employee_id?: string; employees?: { id?: string; nik: string; name: string; departments?: { name: string } | null } | null } | null;
  item_variants?: { id?: string; size: string; items?: { code?: string; name: string; unit: string; return_required?: boolean } | null } | null
}>>([])

async function deleteFromReport(kind: 'item' | 'procurement' | 'stocktake' | 'issuance', id: string | undefined, label: string) {
  if (!id) return
  if (!window.confirm(`Hapus "${label}" secara permanen?`)) return
  const map = {
    item: `/api/master/items/${id}`,
    procurement: `/api/procurements/${id}`,
    stocktake: `/api/transactions/stocktakes/${id}`,
    issuance: `/api/transactions/issuances/${id}`,
  }
  try {
    await api(map[kind], { method: 'DELETE' })
    toast.success(`"${label}" berhasil dihapus`)
    await loadAll(true)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus data')
  }
}

const supplierFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const p of procurements.value) if (p.supplier_name) names.add(p.supplier_name)
  for (const s of master.suppliers) if (s.name) names.add(s.name)
  return [
    { value: 'all', label: 'Semua Supplier / Toko' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const employeeFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Karyawan' },
  ...master.employees.map((e) => ({ value: e.name, label: e.name, sublabel: e.nik })),
])

const departmentFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Departemen' },
  ...master.departments.map((d) => ({ value: d.name, label: d.name, sublabel: d.code })),
])

const itemFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Barang APD' },
  ...master.variants.map((v) => ({ value: v.name, label: variantLabel(v), sublabel: v.code })),
])

const hasExtraFilters = computed(() =>
  Boolean(search.value.trim() || supplierFilter.value !== 'all' || employeeFilter.value !== 'all' || departmentFilter.value !== 'all' || itemFilter.value !== 'all'),
)

function resetExtraFilters() {
  search.value = ''
  supplierFilter.value = 'all'
  employeeFilter.value = 'all'
  departmentFilter.value = 'all'
  itemFilter.value = 'all'
}

function inDateRange(dateStr?: string | null): boolean {
  if (!dateStr) return true
  const d = dateStr.slice(0, 10)
  if (dateFrom.value && d < dateFrom.value) return false
  if (dateTo.value && d > dateTo.value) return false
  return true
}

const filteredVariants = computed(() => {
  const q = search.value.trim().toLowerCase()
  return master.variants.filter((v) => {
    if (itemFilter.value !== 'all' && v.name !== itemFilter.value) return false
    if (!q) return true
    return v.name.toLowerCase().includes(q) || v.code.toLowerCase().includes(q) || (v.size || '').toLowerCase().includes(q)
  })
})

const filteredMovements = computed(() => {
  const q = search.value.trim().toLowerCase()
  return movements.value.filter((m) => {
    if (!inDateRange(m.occurred_at)) return false
    const itemName = m.item_variants?.items?.name || ''
    if (itemFilter.value !== 'all' && itemName !== itemFilter.value) return false
    if (!q) return true
    return itemName.toLowerCase().includes(q) || (m.notes || '').toLowerCase().includes(q) || movementName(m.movement_type).toLowerCase().includes(q)
  })
})

const filteredProcurements = computed(() => {
  const q = search.value.trim().toLowerCase()
  return procurements.value.filter((p) => {
    if (!inDateRange(p.procurement_date)) return false
    if (supplierFilter.value !== 'all' && p.supplier_name !== supplierFilter.value) return false
    if (departmentFilter.value !== 'all' && (p.department_name || '') !== departmentFilter.value) return false
    if (!q) return true
    return p.procurement_no.toLowerCase().includes(q) || (p.po_number || '').toLowerCase().includes(q) || p.supplier_name.toLowerCase().includes(q)
  })
})

const filteredStocktakes = computed(() => {
  const q = search.value.trim().toLowerCase()
  return stocktakes.value
    .filter((s) => inDateRange(s.reference_at))
    .map((s) => ({
      ...s,
      stocktake_items: (s.stocktake_items ?? []).filter((it) => {
        const name = it.item_variants?.items?.name || ''
        if (itemFilter.value !== 'all' && name !== itemFilter.value) return false
        if (!q) return true
        return s.stocktake_no.toLowerCase().includes(q) || s.officer_name.toLowerCase().includes(q) || name.toLowerCase().includes(q) || (it.reason || '').toLowerCase().includes(q)
      }),
    }))
    .filter((s) => s.stocktake_items.length > 0)
})

const filteredLiabilities = computed(() => {
  const q = search.value.trim().toLowerCase()
  return liabilities.value.filter((l) => {
    const remaining = Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity)
    if (remaining <= 0) return false
    // Active employee liabilities remain active regardless of date range unless user explicitly picked custom dates
    if ((dateFrom.value || dateTo.value) && !inDateRange(l.issuances?.issued_at)) return false
    const empName = l.issuances?.employees?.name || ''
    const deptName = l.issuances?.employees?.departments?.name || ''
    const itemName = l.item_variants?.items?.name || ''
    if (employeeFilter.value !== 'all' && empName !== employeeFilter.value) return false
    if (departmentFilter.value !== 'all' && deptName !== departmentFilter.value) return false
    if (itemFilter.value !== 'all' && itemName !== itemFilter.value) return false
    if (!q) return true
    return (
      (l.issuances?.transaction_no || '').toLowerCase().includes(q) ||
      empName.toLowerCase().includes(q) ||
      (l.issuances?.employees?.nik || '').toLowerCase().includes(q) ||
      deptName.toLowerCase().includes(q) ||
      itemName.toLowerCase().includes(q) ||
      (l.purpose || '').toLowerCase().includes(q)
    )
  })
})

const filteredPayments = computed(() =>
  filteredProcurements.value.filter((p) => p.status !== 'cancelled' && Number(p.total_amount || 0) > 0),
)

const periodLabel = computed(() => {
  if (dateFrom.value && dateTo.value) return `${formatDate(dateFrom.value)} s/d ${formatDate(dateTo.value)}`
  if (dateFrom.value) return `Mulai ${formatDate(dateFrom.value)}`
  if (dateTo.value) return `Sampai ${formatDate(dateTo.value)}`
  return 'Semua Periode'
})

const printedTimestamp = computed(() =>
  new Intl.DateTimeFormat('id-ID', {
    day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date()),
)

const printStats = computed(() => {
  const checkedCount = Object.values(selectedSections).filter(Boolean).length
  const totalIn = filteredMovements.value.filter((m) => m.quantity_delta > 0).reduce((s, m) => s + Number(m.quantity_delta), 0)
  const totalOut = filteredMovements.value.filter((m) => m.quantity_delta < 0).reduce((s, m) => s + Math.abs(Number(m.quantity_delta)), 0)
  return [
    { label: 'Sesi Laporan Dipilih', value: `${checkedCount} sesi aktif` },
    { label: 'Arus Masuk (Periode)', value: `+${formatNumber(totalIn)}` },
    { label: 'Arus Keluar (Periode)', value: `-${formatNumber(totalOut)}` },
  ]
})

function setPreset(preset: 'month' | '30d' | 'all') {
  activePreset.value = preset
  const today = new Date()
  if (preset === 'all') {
    dateFrom.value = ''
    dateTo.value = ''
  } else if (preset === 'month') {
    dateFrom.value = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`
    dateTo.value = today.toISOString().slice(0, 10)
  } else {
    const past = new Date(today)
    past.setDate(past.getDate() - 30)
    dateFrom.value = past.toISOString().slice(0, 10)
    dateTo.value = today.toISOString().slice(0, 10)
  }
}

async function loadAll(force = false) {
  if (force) invalidateApiCache()
  loading.value = true
  loadError.value = ''
  try {
    const results = await Promise.allSettled([
      api<{ data: typeof movements.value }>('/api/inventory/movements?limit=300'),
      api<{ data: typeof procurements.value }>('/api/procurements'),
      api<{ data: typeof stocktakes.value }>('/api/transactions/stocktakes'),
      api<{ data: typeof liabilities.value }>('/api/transactions/liabilities'),
      api<{
        data: Array<{
          transaction_no: string; issued_at: string; employee_id: string;
          employees?: { nik: string; name: string; departments?: { name: string } | null } | null;
          issuance_items: Array<{
            id: string; variant_id: string; quantity: number; returned_quantity: number; resolved_lost_quantity: number; purpose: string;
            item_variants?: { size: string; items?: { code?: string; name: string; unit: string; return_required?: boolean } | null } | null
          }>
        }>
      }>('/api/transactions/issuances'),
      master.refresh(force),
    ])

    const errors: string[] = []
    if (results[0].status === 'fulfilled') movements.value = results[0].value.data
    else errors.push('Mutasi')

    if (results[1].status === 'fulfilled') procurements.value = results[1].value.data
    else errors.push('Pengadaan')

    if (results[2].status === 'fulfilled') stocktakes.value = results[2].value.data
    else errors.push('Stok Opname')

    // Primary liabilities endpoint + fallback from issuances so employee liabilities NEVER show empty when active issuances exist
    let loadedLiabilities: typeof liabilities.value = []
    if (results[3].status === 'fulfilled' && Array.isArray(results[3].value.data)) {
      loadedLiabilities = results[3].value.data
    }
    if (!loadedLiabilities.length && results[4].status === 'fulfilled' && Array.isArray(results[4].value.data)) {
      const derived: typeof liabilities.value = []
      for (const iss of results[4].value.data) {
        for (const it of iss.issuance_items ?? []) {
          const rem = Number(it.quantity) - Number(it.returned_quantity) - Number(it.resolved_lost_quantity)
          if (rem > 0) {
            derived.push({
              id: it.id,
              variant_id: it.variant_id,
              quantity: it.quantity,
              returned_quantity: it.returned_quantity,
              resolved_lost_quantity: it.resolved_lost_quantity,
              purpose: it.purpose,
              issuances: {
                transaction_no: iss.transaction_no,
                issued_at: iss.issued_at,
                employee_id: iss.employee_id,
                employees: iss.employees,
              },
              item_variants: it.item_variants,
            })
          }
        }
      }
      loadedLiabilities = derived
    }
    liabilities.value = loadedLiabilities

    if (errors.length) {
      loadError.value = `Sebagian data gagal dimuat (${errors.join(', ')}). Klik muat ulang untuk mencoba lagi.`
    }
  } catch (e) {
    loadError.value = e instanceof Error ? e.message : 'Gagal memuat data laporan'
  } finally {
    loading.value = false
  }
}

function movementName(t: string) {
  const map: Record<string, string> = {
    opening_stock: 'Stok Awal', receipt: 'Barang Masuk', issuance: 'Barang Keluar',
    return: 'Pengembalian', stocktake_adjustment: 'Opname', condition_transfer: 'Pindah Kondisi',
  }
  return map[t] || t
}

const checkedSections = computed<PdfSectionTable[]>(() => {
  const sections: PdfSectionTable[] = []

  if (selectedSections.stock) {
    sections.push({
      title: '1. Stok Tersedia Saat Ini (Sampai Hari Ini)',
      subtitle: `Total ${filteredVariants.value.length} item APD aktif terdaftar di gudang`,
      headers: ['Kode', 'Nama Barang', 'Satuan', 'Baru', 'Bekas Layak', 'Karantina', 'Rusak', 'Stok Tersedia Saat Ini'],
      rows: filteredVariants.value.map((v) => [
        v.code,
        variantLabel(v),
        v.unit,
        `${formatNumber(v.stock_new)} ${v.unit}`,
        `${formatNumber(v.stock_used_good)} ${v.unit}`,
        `${formatNumber(v.stock_quarantine)} ${v.unit}`,
        `${formatNumber(v.stock_damaged)} ${v.unit}`,
        `${formatNumber(v.total_available)} ${v.unit}`,
      ]),
    })
  }

  if (selectedSections.movements) {
    sections.push({
      title: '2. Mutasi Stok & Arus APD',
      subtitle: `Menampilkan ${filteredMovements.value.length} aktivitas mutasi`,
      headers: ['Tanggal', 'Nama Barang', 'Jenis Mutasi', 'Kondisi', 'Perubahan', 'Stok Setelah Mutasi', 'Keterangan'],
      rows: filteredMovements.value.map((m) => {
        const u = m.item_variants?.items?.unit || 'unit'
        return [
          formatDate(m.occurred_at),
          variantLabel({ name: m.item_variants?.items?.name || '-', size: m.item_variants?.size }),
          movementName(m.movement_type),
          conditionLabel(m.condition),
          `${m.quantity_delta >= 0 ? '+' : ''}${formatNumber(m.quantity_delta)} ${u}`,
          `${formatNumber(m.balance_after)} ${u}`,
          m.notes || '-',
        ]
      }),
    })
  }

  if (selectedSections.procurements) {
    sections.push({
      title: '3. Pengadaan Barang & Progress Kedatangan',
      subtitle: `${filteredProcurements.value.length} dokumen pengadaan`,
      headers: ['No. Pengadaan', 'Tanggal', 'No. PO', 'Supplier', 'Progress Barang', 'Nilai Pengadaan', 'Status'],
      rows: filteredProcurements.value.map((p) => [
        p.procurement_no,
        formatDate(p.procurement_date),
        p.po_number || '-',
        p.supplier_name,
        `${formatNumber(p.total_received)} / ${formatNumber(p.total_ordered)} unit (${p.progress_percent}%)`,
        formatCurrency(p.total_amount),
        p.status === 'completed' ? 'Terpenuhi' : p.status === 'partial' ? 'Sebagian' : p.status === 'cancelled' ? 'Dibatalkan' : 'Menunggu',
      ]),
    })
  }

  if (selectedSections.opname) {
    const flatOpname = filteredStocktakes.value.flatMap((st) =>
      st.stocktake_items.map((it) => {
        const diff = Number(it.physical_quantity) - Number(it.system_quantity)
        const u = it.item_variants?.items?.unit || 'unit'
        return [
          st.stocktake_no,
          formatDate(st.reference_at),
          st.officer_name,
          variantLabel({ name: it.item_variants?.items?.name || '-', size: it.item_variants?.size }),
          conditionLabel(it.condition),
          `${formatNumber(it.system_quantity)} ${u}`,
          `${formatNumber(it.physical_quantity)} ${u}`,
          `${diff > 0 ? '+' : ''}${formatNumber(diff)} ${u}`,
          it.reason || '-',
        ]
      }),
    )
    sections.push({
      title: '4. Laporan Stok Opname (+/-)',
      subtitle: `${filteredStocktakes.value.length} sesi opname`,
      headers: ['No. SO', 'Tanggal SO', 'Petugas', 'Nama Barang', 'Kondisi', 'Sistem', 'Fisik', 'Selisih (+/-)', 'Alasan'],
      rows: flatOpname,
    })
  }

  if (selectedSections.liabilities) {
    sections.push({
      title: '5. Tanggungan APD Karyawan',
      subtitle: `${filteredLiabilities.value.length} item masih dibawa karyawan`,
      headers: ['No. Keluar', 'Tanggal', 'NIK & Nama Karyawan', 'Departemen', 'Nama Barang', 'Sisa Tanggungan', 'Keperluan'],
      rows: filteredLiabilities.value.map((l) => [
        l.issuances?.transaction_no || '-',
        formatDate(l.issuances?.issued_at),
        `${l.issuances?.employees?.name || '-'} (${l.issuances?.employees?.nik || '-'})`,
        l.issuances?.employees?.departments?.name || '-',
        variantLabel({ name: l.item_variants?.items?.name || '-', size: l.item_variants?.size }),
        `${formatNumber(Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity))} ${l.item_variants?.items?.unit || ''}`,
        l.purpose,
      ]),
    })
  }

  if (selectedSections.payments) {
    sections.push({
      title: '6. History Pembayaran (Nominal Pengadaan Tercatat)',
      subtitle: `${filteredPayments.value.length} transaksi pengadaan bernominal`,
      headers: ['Tanggal', 'No. Pengadaan', 'No. PO', 'Supplier', 'Nominal', 'Progress'],
      rows: filteredPayments.value.map((p) => [
        formatDate(p.procurement_date),
        p.procurement_no,
        p.po_number || '-',
        p.supplier_name,
        formatCurrency(p.total_amount),
        `${p.progress_percent}%`,
      ]),
    })
  }

  return sections
})

async function downloadPdfReport() {
  const sections = checkedSections.value
  if (!sections.length) {
    toast.error('Ceklis minimal 1 sesi laporan terlebih dahulu')
    return
  }
  const [{ generateInventoryPdf }, companyLogoDataUrl] = await Promise.all([
    import('@/lib/pdf-report'),
    master.company.logoKey ? imageUrlToDataUrl(attachmentUrl(master.company.logoKey)) : Promise.resolve(null),
  ])
  generateInventoryPdf({
    filename: `Laporan-Inventaris-APD-${new Date().toISOString().slice(0, 10)}.pdf`,
    reportTitle: 'LAPORAN TERPADU INVENTARIS APD',
    periodLabel: periodLabel.value,
    companyName: master.company.name,
    companyTagline: `INVENTRA · ${master.company.tagline}`,
    companyLogoDataUrl,
    summaryStats: printStats.value,
    sections,
  })
  toast.success('File PDF laporan berhasil diunduh!')
}

function printReport() {
  if (!Object.values(selectedSections).some(Boolean)) {
    toast.error('Ceklis minimal 1 sesi laporan terlebih dahulu')
    return
  }
  window.print()
}

function exportActiveCsv() {
  const d = new Date().toISOString().slice(0, 10)
  if (activeTab.value === 'all') {
    const sections = checkedSections.value
    if (!sections.length) {
      toast.error('Ceklis minimal 1 sesi laporan terlebih dahulu')
      return
    }
    const combinedRows: Array<Array<string | number>> = []
    for (const sec of sections) {
      combinedRows.push([sec.title, sec.subtitle || ''])
      combinedRows.push(sec.headers)
      for (const r of sec.rows) combinedRows.push(r)
      combinedRows.push([])
    }
    downloadCsv(`laporan-lengkap-apd-${d}.csv`, ['LAPORAN TERPADU INVENTARIS APD', periodLabel.value], combinedRows)
    return
  }
  if (activeTab.value === 'stock') {
    downloadCsv(`laporan-stok-saat-ini-${d}.csv`, ['Kode', 'Nama', 'Ukuran', 'Baru', 'Bekas Layak', 'Karantina', 'Rusak', 'Stok Tersedia Saat Ini'],
      filteredVariants.value.map(v => [v.code, v.name, v.size, v.stock_new, v.stock_used_good, v.stock_quarantine, v.stock_damaged, v.total_available]))
  } else if (activeTab.value === 'movements') {
    downloadCsv(`laporan-mutasi-${d}.csv`, ['Tanggal', 'Barang', 'Ukuran', 'Jenis', 'Kondisi', 'Perubahan', 'Stok Setelah Mutasi', 'Keterangan'],
      filteredMovements.value.map(m => [m.occurred_at.slice(0, 10), m.item_variants?.items?.name, m.item_variants?.size, movementName(m.movement_type), conditionLabel(m.condition), m.quantity_delta, m.balance_after, m.notes]))
  } else if (activeTab.value === 'procurements') {
    downloadCsv(`laporan-pengadaan-${d}.csv`, ['No Pengadaan', 'Tanggal', 'PO', 'Supplier', 'Dipesan', 'Diterima', 'Progress %', 'Total Tagihan', 'Terbayar', 'Status Bayar'],
      filteredProcurements.value.map(p => [p.procurement_no, p.procurement_date, p.po_number, p.supplier_name, p.total_ordered, p.total_received, p.progress_percent, p.total_amount, p.paid_amount, p.payment_status]))
  } else if (activeTab.value === 'opname') {
    const flat = filteredStocktakes.value.flatMap(st => st.stocktake_items.map(it => {
      const diff = Number(it.physical_quantity) - Number(it.system_quantity)
      return [st.stocktake_no, st.reference_at.slice(0, 10), st.officer_name, it.item_variants?.items?.name, it.item_variants?.size, conditionLabel(it.condition), it.system_quantity, it.physical_quantity, diff > 0 ? `+${diff}` : String(diff), it.reason]
    }))
    downloadCsv(`laporan-opname-plus-minus-${d}.csv`, ['No Opname', 'Tanggal SO', 'Petugas', 'Barang', 'Ukuran', 'Kondisi', 'Sistem', 'Fisik', 'Selisih (+/-)', 'Alasan'], flat)
  } else if (activeTab.value === 'liabilities') {
    downloadCsv(`laporan-tanggungan-${d}.csv`, ['No Keluar', 'Tanggal', 'NIK', 'Karyawan', 'Departemen', 'Barang', 'Ukuran', 'Sisa Tanggungan'],
      filteredLiabilities.value.map(l => [l.issuances?.transaction_no, l.issuances?.issued_at, l.issuances?.employees?.nik, l.issuances?.employees?.name, l.issuances?.employees?.departments?.name, l.item_variants?.items?.name, l.item_variants?.size, Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity)]))
  } else {
    downloadCsv(`history-pembayaran-${d}.csv`, ['Tanggal', 'No Pengadaan', 'PO', 'Supplier', 'Nominal', 'Status'],
      filteredPayments.value.map(p => [p.procurement_date, p.procurement_no, p.po_number || '-', p.supplier_name, p.total_amount, p.status]))
  }
}

onMounted(() => { void loadAll(true) })
onActivated(() => { void loadAll(true) })
</script>

<template>
  <div class="report-page-root">
    <!-- Official Executive PDF Print Letterhead (Visible in Print) -->
    <header class="print-letterhead">
      <div class="print-brand-block">
        <div class="print-company-badge">
          <img v-if="master.company.logoKey" :src="attachmentUrl(master.company.logoKey)" alt="Logo PT" style="width:100%;height:100%;object-fit:cover;border-radius:10px;" />
          <template v-else>{{ master.companyInitials }}</template>
        </div>
        <div>
          <strong>{{ master.company.name.toUpperCase() }}</strong>
          <small>INVENTRA · {{ master.company.tagline }}</small>
        </div>
      </div>
      <div class="print-title-block">
        <h1>LAPORAN TERPADU INVENTARIS APD</h1>
        <small>Periode: {{ periodLabel }} · Dicetak {{ printedTimestamp }} WIB</small>
      </div>
    </header>

    <section class="print-summary-strip">
      <div v-for="stat in printStats" :key="stat.label" class="print-stat-box">
        <small>{{ stat.label }}</small>
        <strong>{{ stat.value }}</strong>
      </div>
    </section>

    <section class="page-intro screen-only-intro report-intro">
      <div>
        <p class="eyebrow">Analitik, Cetak &amp; Ekspor</p>
        <h2>Laporan Inventaris</h2>
        <p>Tampilkan semua sesi sekaligus atau pilih sesi tertentu untuk ditinjau, difilter, dicetak, dan diunduh ke PDF/CSV.</p>
      </div>
      <div class="intro-actions report-actions-bar">
        <button class="primary-button report-pdf-btn" @click="downloadPdfReport"><FileDown :size="16" /> Download PDF</button>
        <button class="secondary-button" @click="exportActiveCsv"><Download :size="16" /> {{ activeTab === 'all' ? 'Ekspor CSV' : 'CSV Tab' }}</button>
        <button class="secondary-button" @click="printReport"><Printer :size="16" /> Cetak</button>
        <button class="secondary-button square" aria-label="Muat ulang" @click="loadAll(true)"><RefreshCw :size="16" :class="{ spinning: loading }" /></button>
      </div>
    </section>

    <div v-if="loadError" class="inline-alert screen-only-intro">
      <AlertTriangle :size="18" /> {{ loadError }}
      <button @click="loadAll(true)">Coba lagi</button>
    </div>

    <!-- Checklist & Date Range Builder -->
    <section class="panel report-builder-panel screen-only-intro">
      <div class="builder-row">
        <div class="builder-block">
          <div class="builder-title builder-title-spread">
            <span class="builder-title-label"><CheckSquare :size="15" /> <strong>Pilih Sesi Laporan</strong></span>
            <button type="button" class="secondary-button xs" @click="toggleSelectAllSections">
              {{ allSectionsSelected ? 'Hapus Semua' : 'Pilih Semua' }}
            </button>
          </div>
          <div class="checklist-pills">
            <label v-for="sec in sectionList" :key="sec.key" class="check-pill" :class="{ checked: selectedSections[sec.key] }">
              <input v-model="selectedSections[sec.key]" type="checkbox" />
              <span>{{ sec.label }}</span>
            </label>
          </div>
        </div>

        <div class="builder-block">
          <div class="builder-title"><CalendarRange :size="15" /> <strong>Rentang Tanggal Laporan</strong></div>
          <div class="date-range-stack">
            <div class="date-inputs-row">
              <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" @input="activePreset = 'custom'" />
              <span class="date-sep">s/d</span>
              <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" @input="activePreset = 'custom'" />
            </div>
            <div class="date-presets-row">
              <button type="button" class="secondary-button xs" :class="{ highlight: activePreset === 'all' }" @click="setPreset('all')">Semua</button>
              <button type="button" class="secondary-button xs" :class="{ highlight: activePreset === 'month' }" @click="setPreset('month')">Bulan Ini</button>
              <button type="button" class="secondary-button xs" :class="{ highlight: activePreset === '30d' }" @click="setPreset('30d')">30 Hari</button>
            </div>
          </div>
        </div>
      </div>

      <div class="table-toolbar filter-toolbar-rich" style="margin-top:12px;padding:12px 0 0;border-bottom:0;border-top:1px solid var(--border);">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari barang, karyawan, supplier, nomor dokumen..." /></label>
        <ModernSelect v-model="itemFilter" :options="itemFilterOptions" compact searchable search-placeholder="Cari barang APD..." />
        <ModernSelect v-model="supplierFilter" :options="supplierFilterOptions" compact searchable search-placeholder="Cari supplier / toko..." />
        <ModernSelect v-model="employeeFilter" :options="employeeFilterOptions" compact searchable search-placeholder="Cari karyawan..." />
        <ModernSelect v-model="departmentFilter" :options="departmentFilterOptions" compact searchable search-placeholder="Cari departemen..." />
        <button v-if="hasExtraFilters" type="button" class="secondary-button xs" @click="resetExtraFilters">
          <RotateCcw :size="13" /> Reset
        </button>
      </div>
    </section>

    <!-- Screen Tab View -->
    <section class="panel data-panel report-screen-panel">
      <div class="record-tabs">
        <button :class="{ active: activeTab === 'all' }" @click="activeTab = 'all'">Semua Laporan ({{ checkedSections.length }} Sesi)</button>
        <button :class="{ active: activeTab === 'movements' }" @click="activeTab = 'movements'">Mutasi / Arus APD ({{ filteredMovements.length }})</button>
        <button :class="{ active: activeTab === 'procurements' }" @click="activeTab = 'procurements'">Pengadaan ({{ filteredProcurements.length }})</button>
        <button :class="{ active: activeTab === 'opname' }" @click="activeTab = 'opname'">Stok Opname (+/-)</button>
        <button :class="{ active: activeTab === 'liabilities' }" @click="activeTab = 'liabilities'">Tanggungan ({{ filteredLiabilities.length }})</button>
        <button :class="{ active: activeTab === 'payments' }" @click="activeTab = 'payments'">History Pembayaran ({{ filteredPayments.length }})</button>
        <button :class="{ active: activeTab === 'stock' }" @click="activeTab = 'stock'">Stok Saat Ini ({{ filteredVariants.length }})</button>
      </div>

      <div v-if="loading" class="loading-row">Memuat data laporan...</div>

      <div v-else-if="activeTab === 'all'" style="display:grid;gap:22px;padding:16px;">
        <div v-if="!checkedSections.length" class="empty-state compact">
          <strong>Belum ada sesi yang diceklis.</strong>
          <span>Klik "Pilih Semua" atau ceklis minimal satu sesi di atas.</span>
        </div>
        <div v-for="sec in checkedSections" :key="sec.title" style="display:grid;gap:8px;">
          <div style="display:flex;align-items:baseline;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:6px 2px;border-bottom:1px solid var(--border);">
            <strong style="font-size:15px;color:var(--text);">{{ sec.title }}</strong>
            <small class="muted-text">{{ sec.subtitle }}</small>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr><th v-for="h in sec.headers" :key="h">{{ h }}</th><th class="screen-only-cell">Aksi</th></tr>
              </thead>
              <tbody>
                <tr v-for="(row, rIdx) in sec.rows.slice(0, 50)" :key="rIdx">
                  <td v-for="(cell, cIdx) in row" :key="cIdx">{{ cell }}</td>
                  <td class="screen-only-cell">
                    <button
                      class="icon-button"
                      title="Preview detail baris"
                      @click="openRowPreview(sec.title, String(row[0] || 'Detail Data'), sec.headers.map((h, i) => ({ label: h, value: String(row[i] ?? '-') })))"
                    >
                      <Eye :size="15" />
                    </button>
                  </td>
                </tr>
                <tr v-if="sec.rows.length > 50">
                  <td :colspan="sec.headers.length + 1" class="muted-text" style="text-align:center;">
                    Menampilkan 50 dari {{ sec.rows.length }} baris. Gunakan Download PDF / Ekspor CSV untuk seluruh baris.
                  </td>
                </tr>
                <tr v-if="!sec.rows.length">
                  <td :colspan="sec.headers.length + 1"><div class="empty-state compact">Tidak ada data pada filter/periode ini.</div></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div v-else-if="activeTab === 'stock'" class="table-wrap">
        <table>
          <thead><tr><th>Kode &amp; Barang</th><th>Satuan</th><th>Baru</th><th>Bekas Layak</th><th>Karantina</th><th>Rusak</th><th>Stok Tersedia Saat Ini</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <tr v-for="v in filteredVariants" :key="v.variant_id">
              <td><strong>{{ variantLabel(v) }}</strong><small class="table-sub">{{ v.code }}</small></td>
              <td><span class="tag-pill">{{ v.unit }}</span></td>
              <td>{{ formatNumber(v.stock_new) }} {{ v.unit }}</td>
              <td>{{ formatNumber(v.stock_used_good) }} {{ v.unit }}</td>
              <td>{{ formatNumber(v.stock_quarantine) }} {{ v.unit }}</td>
              <td>{{ formatNumber(v.stock_damaged) }} {{ v.unit }}</td>
              <td><strong>{{ formatNumber(v.total_available) }} {{ v.unit }}</strong></td>
              <td class="screen-only-cell">
                <div class="row-actions">
                  <button
                    class="icon-button"
                    title="Preview stok barang"
                    @click="openRowPreview('Preview Stok Saat Ini', variantLabel(v), [
                      { label: 'Kode', value: v.code },
                      { label: 'Nama Barang', value: variantLabel(v) },
                      { label: 'Satuan', value: v.unit },
                      { label: 'Baru', value: `${formatNumber(v.stock_new)} ${v.unit}` },
                      { label: 'Bekas Layak', value: `${formatNumber(v.stock_used_good)} ${v.unit}` },
                      { label: 'Karantina', value: `${formatNumber(v.stock_quarantine)} ${v.unit}` },
                      { label: 'Rusak', value: `${formatNumber(v.stock_damaged)} ${v.unit}` },
                      { label: 'Stok Tersedia Saat Ini', value: `${formatNumber(v.total_available)} ${v.unit}` },
                    ])"
                  >
                    <Eye :size="15" />
                  </button>
                  <button class="icon-button" title="Kelola di Stok Inventaris" @click="router.push({ name: 'inventory' })"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus barang" @click="deleteFromReport('item', v.item_id, v.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredVariants.length"><td colspan="8"><div class="empty-state compact">Tidak ada barang yang cocok.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'movements'" class="table-wrap">
        <table>
          <thead><tr><th>Tanggal</th><th>Barang</th><th>Jenis Mutasi</th><th>Kondisi</th><th>Perubahan</th><th>Stok Setelah Mutasi</th><th>Catatan</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <tr v-for="m in filteredMovements" :key="m.id">
              <td>{{ formatDate(m.occurred_at) }}</td>
              <td><strong>{{ variantLabel({ name: m.item_variants?.items?.name, size: m.item_variants?.size }) }}</strong></td>
              <td>{{ movementName(m.movement_type) }}</td>
              <td>{{ conditionLabel(m.condition) }}</td>
              <td><span class="delta-pill" :class="m.quantity_delta >= 0 ? 'plus' : 'minus'">{{ m.quantity_delta >= 0 ? '+' : '' }}{{ formatNumber(m.quantity_delta) }} {{ m.item_variants?.items?.unit || '' }}</span></td>
              <td><strong>{{ formatNumber(m.balance_after) }} {{ m.item_variants?.items?.unit || '' }}</strong></td>
              <td>{{ m.notes || '-' }}</td>
              <td class="screen-only-cell">
                <button
                  class="icon-button"
                  title="Preview mutasi"
                  @click="openRowPreview('Preview Mutasi Stok', variantLabel({ name: m.item_variants?.items?.name || '-', size: m.item_variants?.size }), [
                    { label: 'Tanggal', value: formatDate(m.occurred_at) },
                    { label: 'Jenis Mutasi', value: movementName(m.movement_type) },
                    { label: 'Kondisi', value: conditionLabel(m.condition) },
                    { label: 'Perubahan', value: `${m.quantity_delta >= 0 ? '+' : ''}${formatNumber(m.quantity_delta)} ${m.item_variants?.items?.unit || ''}` },
                    { label: 'Stok Setelah Mutasi', value: `${formatNumber(m.balance_after)} ${m.item_variants?.items?.unit || ''}` },
                    { label: 'Catatan', value: m.notes || '-' },
                  ])"
                >
                  <Eye :size="15" />
                </button>
              </td>
            </tr>
            <tr v-if="!filteredMovements.length"><td colspan="8"><div class="empty-state compact">Tidak ada mutasi pada rentang tanggal/filter ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'procurements'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengadaan</th><th>Supplier</th><th>Progress Barang</th><th>Nilai Pengadaan</th><th>Status</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <tr v-for="p in filteredProcurements" :key="p.procurement_no">
              <td><strong>{{ p.procurement_no }}</strong><small class="table-sub">{{ formatDate(p.procurement_date) }} {{ p.po_number ? `· PO: ${p.po_number}` : '' }}</small></td>
              <td>{{ p.supplier_name }}</td>
              <td><strong>{{ p.progress_percent }}%</strong> ({{ formatNumber(p.total_received) }} / {{ formatNumber(p.total_ordered) }})</td>
              <td><strong>{{ formatCurrency(p.total_amount) }}</strong></td>
              <td><span class="status-pill" :class="p.status === 'completed' ? 'safe' : p.status === 'cancelled' ? 'out' : 'amber'">{{ p.status === 'completed' ? 'Terpenuhi' : p.status === 'partial' ? 'Sebagian' : p.status === 'cancelled' ? 'Dibatalkan' : 'Menunggu' }}</span></td>
              <td class="screen-only-cell">
                <div class="row-actions">
                  <button
                    class="icon-button"
                    title="Preview pengadaan"
                    @click="openRowPreview('Preview Pengadaan', p.procurement_no, [
                      { label: 'No. Pengadaan', value: p.procurement_no },
                      { label: 'No. PO', value: p.po_number || '-' },
                      { label: 'Tanggal', value: formatDate(p.procurement_date) },
                      { label: 'Supplier', value: p.supplier_name },
                      { label: 'Progress', value: `${formatNumber(p.total_received)} / ${formatNumber(p.total_ordered)} (${p.progress_percent}%)` },
                      { label: 'Nilai Pengadaan', value: formatCurrency(p.total_amount) },
                      { label: 'Status', value: p.status === 'completed' ? 'Terpenuhi' : p.status === 'partial' ? 'Sebagian' : p.status === 'cancelled' ? 'Dibatalkan' : 'Menunggu' },
                    ])"
                  >
                    <Eye :size="15" />
                  </button>
                  <button class="icon-button" title="Kelola di Pengadaan Barang" @click="router.push({ name: 'procurements' })"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus pengadaan" @click="deleteFromReport('procurement', p.id, p.procurement_no)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredProcurements.length"><td colspan="6"><div class="empty-state compact">Tidak ada pengadaan pada rentang tanggal/filter ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'opname'" class="table-wrap">
        <table>
          <thead><tr><th>No. SO</th><th>Barang</th><th>Kondisi</th><th>Sistem</th><th>Fisik</th><th>Selisih (+/-)</th><th>Alasan</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <template v-for="st in filteredStocktakes" :key="st.stocktake_no">
              <tr v-for="(it, idx) in st.stocktake_items" :key="`${st.stocktake_no}-${idx}`">
                <td><strong>{{ st.stocktake_no }}</strong><small class="table-sub">{{ formatDate(st.reference_at) }}</small></td>
                <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name, size: it.item_variants?.size }) }}</strong></td>
                <td>{{ conditionLabel(it.condition) }}</td>
                <td>{{ formatNumber(it.system_quantity) }}</td>
                <td>{{ formatNumber(it.physical_quantity) }}</td>
                <td>
                  <span class="delta-pill" :class="it.physical_quantity - it.system_quantity > 0 ? 'plus' : it.physical_quantity - it.system_quantity < 0 ? 'minus' : 'zero'">
                    {{ it.physical_quantity - it.system_quantity > 0 ? '+' : '' }}{{ formatNumber(it.physical_quantity - it.system_quantity) }}
                  </span>
                </td>
                <td>{{ it.reason || '-' }}</td>
                <td class="screen-only-cell">
                  <div class="row-actions">
                    <button
                      class="icon-button"
                      title="Preview baris opname"
                      @click="openRowPreview('Preview Stok Opname', `${st.stocktake_no} · ${variantLabel({ name: it.item_variants?.items?.name || '-', size: it.item_variants?.size })}`, [
                        { label: 'No. SO', value: st.stocktake_no },
                        { label: 'Tanggal SO', value: formatDate(st.reference_at) },
                        { label: 'Petugas', value: st.officer_name },
                        { label: 'Barang', value: variantLabel({ name: it.item_variants?.items?.name || '-', size: it.item_variants?.size }) },
                        { label: 'Kondisi', value: conditionLabel(it.condition) },
                        { label: 'Stok Sistem', value: formatNumber(it.system_quantity) },
                        { label: 'Stok Fisik', value: formatNumber(it.physical_quantity) },
                        { label: 'Selisih (+/-)', value: `${it.physical_quantity - it.system_quantity > 0 ? '+' : ''}${formatNumber(it.physical_quantity - it.system_quantity)}` },
                        { label: 'Alasan', value: it.reason || '-' },
                      ])"
                    >
                      <Eye :size="15" />
                    </button>
                    <button class="icon-button" title="Kelola di Stok Opname" @click="router.push({ name: 'stocktakes' })"><Edit3 :size="15" /></button>
                    <button class="icon-button danger" title="Hapus sesi SO" @click="deleteFromReport('stocktake', st.id, st.stocktake_no)"><Trash2 :size="15" /></button>
                  </div>
                </td>
              </tr>
            </template>
            <tr v-if="!filteredStocktakes.length"><td colspan="8"><div class="empty-state compact">Tidak ada laporan stok opname pada rentang tanggal/filter ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'liabilities'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengeluaran</th><th>Karyawan</th><th>Departemen</th><th>Barang</th><th>Sisa Dibawa</th><th>Keperluan</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <tr v-for="(l, idx) in filteredLiabilities" :key="l.id || idx">
              <td><strong>{{ l.issuances?.transaction_no || '-' }}</strong><small class="table-sub">{{ formatDate(l.issuances?.issued_at) }}</small></td>
              <td><strong>{{ l.issuances?.employees?.name || '-' }}</strong><small class="table-sub">{{ l.issuances?.employees?.nik || '-' }}</small></td>
              <td>{{ l.issuances?.employees?.departments?.name || '-' }}</td>
              <td>{{ variantLabel({ name: l.item_variants?.items?.name, size: l.item_variants?.size }) }}</td>
              <td><strong class="text-amber">{{ formatNumber(Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity)) }} {{ l.item_variants?.items?.unit }}</strong></td>
              <td>{{ l.purpose }}</td>
              <td class="screen-only-cell">
                <div class="row-actions">
                  <button
                    class="icon-button"
                    title="Preview tanggungan karyawan"
                    @click="openRowPreview('Preview Tanggungan Karyawan', l.issuances?.employees?.name || '-', [
                      { label: 'No. Pengeluaran', value: l.issuances?.transaction_no || '-' },
                      { label: 'Tanggal Keluar', value: formatDate(l.issuances?.issued_at) },
                      { label: 'Karyawan', value: `${l.issuances?.employees?.name || '-'} (${l.issuances?.employees?.nik || '-'})` },
                      { label: 'Departemen', value: l.issuances?.employees?.departments?.name || '-' },
                      { label: 'Barang APD', value: variantLabel({ name: l.item_variants?.items?.name || '-', size: l.item_variants?.size }) },
                      { label: 'Sisa Tanggungan', value: `${formatNumber(Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity))} ${l.item_variants?.items?.unit || ''}` },
                      { label: 'Keperluan', value: l.purpose || '-' },
                    ])"
                  >
                    <Eye :size="15" />
                  </button>
                  <button class="icon-button" title="Kelola di Barang Keluar" @click="router.push({ name: 'issuances' })"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus pengeluaran terkait" @click="deleteFromReport('issuance', l.issuance_id || l.issuances?.id, l.issuances?.transaction_no || 'Barang Keluar')"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredLiabilities.length"><td colspan="7"><div class="empty-state compact">Tidak ada tanggungan aktif yang cocok dengan filter/rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>Tanggal</th><th>No. Pengadaan</th><th>No. PO</th><th>Supplier</th><th>Nominal</th><th>Progress</th><th class="screen-only-cell">Aksi</th></tr></thead>
          <tbody>
            <tr v-for="(p, idx) in filteredPayments" :key="idx">
              <td>{{ formatDate(p.procurement_date) }}</td>
              <td><strong>{{ p.procurement_no }}</strong></td>
              <td>{{ p.po_number || '-' }}</td>
              <td>{{ p.supplier_name }}</td>
              <td><strong>{{ formatCurrency(p.total_amount) }}</strong></td>
              <td>{{ p.progress_percent }}%</td>
              <td class="screen-only-cell">
                <div class="row-actions">
                  <button
                    class="icon-button"
                    title="Preview pembayaran"
                    @click="openRowPreview('Preview History Pembayaran', p.procurement_no, [
                      { label: 'Tanggal', value: formatDate(p.procurement_date) },
                      { label: 'No. Pengadaan', value: p.procurement_no },
                      { label: 'No. PO', value: p.po_number || '-' },
                      { label: 'Supplier', value: p.supplier_name },
                      { label: 'Nominal', value: formatCurrency(p.total_amount) },
                      { label: 'Progress Kedatangan', value: `${p.progress_percent}%` },
                    ])"
                  >
                    <Eye :size="15" />
                  </button>
                  <button class="icon-button" title="Kelola di History Pembayaran" @click="router.push({ name: 'payments' })"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus pembayaran / pengadaan" @click="deleteFromReport('procurement', p.id, p.procurement_no)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredPayments.length"><td colspan="7"><div class="empty-state compact">Tidak ada history pembayaran pada rentang tanggal/filter ini.</div></td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <BaseModal :open="showRowPreview" :title="rowPreviewTitle" :eyebrow="rowPreviewEyebrow" size="sm" @close="showRowPreview = false">
      <div class="table-wrap" style="margin-top:0;">
        <table>
          <tbody>
            <tr v-for="f in rowPreviewFields" :key="f.label">
              <th style="width:42%;">{{ f.label }}</th>
              <td><strong>{{ f.value }}</strong></td>
            </tr>
          </tbody>
        </table>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showRowPreview = false">Tutup</button>
      </template>
    </BaseModal>

    <!-- Print-Only Multi-Section View (renders ONLY checked sections cleanly when printing!) -->
    <div class="print-multi-sections">
      <div v-for="sec in checkedSections" :key="sec.title" class="print-section-block">
        <div class="print-sec-head">
          <h3>{{ sec.title }}</h3>
          <small v-if="sec.subtitle">{{ sec.subtitle }}</small>
        </div>
        <table>
          <thead>
            <tr><th v-for="h in sec.headers" :key="h">{{ h }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="(row, rIdx) in sec.rows" :key="rIdx">
              <td v-for="(cell, cIdx) in row" :key="cIdx">{{ cell }}</td>
            </tr>
            <tr v-if="!sec.rows.length"><td :colspan="sec.headers.length">Tidak ada data pada periode ini.</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Print Signature & Copyright Footer (Visible in Print) -->
    <section class="print-signatures">
      <div><small>Disiapkan oleh,</small><span>Admin Gudang APD</span></div>
      <div><small>Diperiksa oleh,</small><span>Safety Inspector (K3)</span></div>
      <div><small>Disetujui oleh,</small><span>Manajemen {{ master.company.name }}</span></div>
    </section>

    <footer class="print-copyright-footer">
      <div class="print-copy-brand">
        <img src="/daysheet-logo.png" alt="DaySheet" />
        <span>Copyright © {{ new Date().getFullYear() }} by <strong>DaySheet.id</strong> · INVENTRA APD Asset Control</span>
      </div>
      <span>Dokumen sistem resmi {{ master.company.name }}</span>
    </footer>
  </div>
</template>
