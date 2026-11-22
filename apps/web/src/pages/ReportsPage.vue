<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref } from 'vue'
import { AlertTriangle, CalendarRange, CheckSquare, Download, FileDown, Printer, RefreshCw } from '@lucide/vue'
import { api, attachmentUrl, conditionLabel, downloadCsv, formatCurrency, formatDate, formatNumber, getApiCacheVersion, imageUrlToDataUrl, invalidateApiCache, variantLabel } from '@/lib/api'
import type { PdfSectionTable } from '@/lib/pdf-report'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

type ReportSectionKey = 'stock' | 'movements' | 'procurements' | 'opname' | 'liabilities' | 'payments'
type ReportTab = 'all' | ReportSectionKey

const master = useMasterStore()
const toast = useToast()

const activeTab = ref<ReportTab>('all')
const loading = ref(true)
const loadError = ref('')

const dateFrom = ref('')
const dateTo = ref('')
const activePreset = ref<'all' | 'month' | '30d' | 'custom'>('all')

const selectedSections = reactive<Record<ReportSectionKey, boolean>>({
  stock: true,
  movements: true,
  procurements: true,
  liabilities: true,
  opname: true,
  payments: true,
})

const sectionList: Array<{ key: ReportSectionKey; label: string }> = [
  { key: 'stock', label: 'Saldo Stok Saat Ini' },
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

const movements = ref<Array<{ id: number; occurred_at: string; movement_type: string; condition: string; quantity_delta: number; balance_after: number; notes: string | null; item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null }>>([])
const procurements = ref<Array<{ procurement_no: string; procurement_date: string; po_number: string | null; supplier_name: string; total_ordered: number; total_received: number; progress_percent: number; total_amount: number; paid_amount: number; payment_status: string; status: string }>>([])
const stocktakes = ref<Array<{ stocktake_no: string; reference_at: string; officer_name: string; status: string; stocktake_items: Array<{ condition: string; system_quantity: number; physical_quantity: number; reason: string | null; item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null }> }>>([])
const liabilities = ref<Array<{ quantity: number; returned_quantity: number; resolved_lost_quantity: number; purpose: string; issuances?: { transaction_no: string; issued_at: string; employees?: { nik: string; name: string; departments?: { name: string } | null } | null } | null; item_variants?: { size: string; items?: { name: string; unit: string } | null } | null }>>([])

function inDateRange(dateStr?: string | null): boolean {
  if (!dateStr) return true
  const d = dateStr.slice(0, 10)
  if (dateFrom.value && d < dateFrom.value) return false
  if (dateTo.value && d > dateTo.value) return false
  return true
}

const filteredMovements = computed(() => movements.value.filter((m) => inDateRange(m.occurred_at)))
const filteredProcurements = computed(() => procurements.value.filter((p) => inDateRange(p.procurement_date)))
const filteredStocktakes = computed(() => stocktakes.value.filter((s) => inDateRange(s.reference_at)))
const filteredLiabilities = computed(() => liabilities.value.filter((l) => inDateRange(l.issuances?.issued_at)))
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
    const [m, pr, st, lb] = await Promise.all([
      api<{ data: typeof movements.value }>('/api/inventory/movements?limit=300'),
      api<{ data: typeof procurements.value }>('/api/procurements'),
      api<{ data: typeof stocktakes.value }>('/api/transactions/stocktakes'),
      api<{ data: typeof liabilities.value }>('/api/transactions/liabilities'),
      master.refresh(force),
    ])
    movements.value = m.data
    procurements.value = pr.data
    stocktakes.value = st.data
    liabilities.value = lb.data
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
      title: '1. Saldo Stok Inventaris APD Saat Ini',
      subtitle: `Total ${master.variants.length} item APD aktif terdaftar di gudang`,
      headers: ['Kode', 'Nama Barang', 'Baru', 'Bekas Layak', 'Karantina', 'Rusak', 'Total Tersedia'],
      rows: master.variants.map((v) => [
        v.code, variantLabel(v),
        formatNumber(v.stock_new), formatNumber(v.stock_used_good),
        formatNumber(v.stock_quarantine), formatNumber(v.stock_damaged),
        `${formatNumber(v.total_available)} ${v.unit}`,
      ]),
    })
  }

  if (selectedSections.movements) {
    sections.push({
      title: '2. Mutasi Stok & Arus APD',
      subtitle: `Menampilkan ${filteredMovements.value.length} aktivitas mutasi`,
      headers: ['Tanggal', 'Nama Barang', 'Jenis Mutasi', 'Kondisi', 'Perubahan', 'Stok Akhir', 'Keterangan'],
      rows: filteredMovements.value.map((m) => [
        formatDate(m.occurred_at),
        variantLabel({ name: m.item_variants?.items?.name || '-', size: m.item_variants?.size }),
        movementName(m.movement_type),
        conditionLabel(m.condition),
        `${m.quantity_delta >= 0 ? '+' : ''}${formatNumber(m.quantity_delta)}`,
        formatNumber(m.balance_after),
        m.notes || '-',
      ]),
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
        `${p.progress_percent}% (${formatNumber(p.total_received)}/${formatNumber(p.total_ordered)})`,
        formatCurrency(p.total_amount),
        p.status === 'completed' ? 'Terpenuhi' : p.status === 'partial' ? 'Sebagian' : p.status === 'cancelled' ? 'Dibatalkan' : 'Menunggu',
      ]),
    })
  }

  if (selectedSections.opname) {
    const flatOpname = filteredStocktakes.value.flatMap((st) =>
      st.stocktake_items.map((it) => {
        const diff = Number(it.physical_quantity) - Number(it.system_quantity)
        return [
          st.stocktake_no,
          formatDate(st.reference_at),
          st.officer_name,
          variantLabel({ name: it.item_variants?.items?.name || '-', size: it.item_variants?.size }),
          conditionLabel(it.condition),
          formatNumber(it.system_quantity),
          formatNumber(it.physical_quantity),
          diff > 0 ? `+${formatNumber(diff)}` : formatNumber(diff),
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
    downloadCsv(`laporan-stok-${d}.csv`, ['Kode', 'Nama', 'Ukuran', 'Baru', 'Bekas Layak', 'Karantina', 'Rusak', 'Tersedia'],
      master.variants.map(v => [v.code, v.name, v.size, v.stock_new, v.stock_used_good, v.stock_quarantine, v.stock_damaged, v.total_available]))
  } else if (activeTab.value === 'movements') {
    downloadCsv(`laporan-mutasi-${d}.csv`, ['Tanggal', 'Barang', 'Ukuran', 'Jenis', 'Kondisi', 'Perubahan', 'Stok Akhir', 'Keterangan'],
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

let lastCacheVer = -1
onMounted(() => { lastCacheVer = getApiCacheVersion(); void loadAll() })
onActivated(() => {
  if (getApiCacheVersion() !== lastCacheVer) {
    lastCacheVer = getApiCacheVersion()
    void loadAll()
  }
})
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
        <p>Tampilkan semua sesi sekaligus atau pilih sesi tertentu untuk ditinjau, dicetak, dan diunduh ke PDF/CSV.</p>
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
        <button :class="{ active: activeTab === 'stock' }" @click="activeTab = 'stock'">Saldo Stok ({{ master.variants.length }})</button>
      </div>

      <div v-if="loading" class="loading-row">Memuat data laporan...</div>

      <div v-else-if="activeTab === 'all'" style="display:grid;gap:22px;">
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
                <tr><th v-for="h in sec.headers" :key="h">{{ h }}</th></tr>
              </thead>
              <tbody>
                <tr v-for="(row, rIdx) in sec.rows.slice(0, 50)" :key="rIdx">
                  <td v-for="(cell, cIdx) in row" :key="cIdx">{{ cell }}</td>
                </tr>
                <tr v-if="sec.rows.length > 50">
                  <td :colspan="sec.headers.length" class="muted-text" style="text-align:center;">
                    Menampilkan 50 dari {{ sec.rows.length }} baris. Gunakan Download PDF / Ekspor CSV untuk seluruh baris.
                  </td>
                </tr>
                <tr v-if="!sec.rows.length">
                  <td :colspan="sec.headers.length"><div class="empty-state compact">Tidak ada data pada periode ini.</div></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div v-else-if="activeTab === 'stock'" class="table-wrap">
        <table>
          <thead><tr><th>Kode &amp; Barang</th><th>Baru</th><th>Bekas Layak</th><th>Karantina</th><th>Rusak</th><th>Total Tersedia</th></tr></thead>
          <tbody>
            <tr v-for="v in master.variants" :key="v.variant_id">
              <td><strong>{{ variantLabel(v) }}</strong><small class="table-sub">{{ v.code }}</small></td>
              <td>{{ formatNumber(v.stock_new) }}</td>
              <td>{{ formatNumber(v.stock_used_good) }}</td>
              <td>{{ formatNumber(v.stock_quarantine) }}</td>
              <td>{{ formatNumber(v.stock_damaged) }}</td>
              <td><strong>{{ formatNumber(v.total_available) }} {{ v.unit }}</strong></td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'movements'" class="table-wrap">
        <table>
          <thead><tr><th>Tanggal</th><th>Barang</th><th>Jenis Mutasi</th><th>Kondisi</th><th>Perubahan</th><th>Stok Akhir</th><th>Catatan</th></tr></thead>
          <tbody>
            <tr v-for="m in filteredMovements" :key="m.id">
              <td>{{ formatDate(m.occurred_at) }}</td>
              <td><strong>{{ variantLabel({ name: m.item_variants?.items?.name, size: m.item_variants?.size }) }}</strong></td>
              <td>{{ movementName(m.movement_type) }}</td>
              <td>{{ conditionLabel(m.condition) }}</td>
              <td><span class="delta-pill" :class="m.quantity_delta >= 0 ? 'plus' : 'minus'">{{ m.quantity_delta >= 0 ? '+' : '' }}{{ formatNumber(m.quantity_delta) }}</span></td>
              <td><strong>{{ formatNumber(m.balance_after) }}</strong></td>
              <td>{{ m.notes || '-' }}</td>
            </tr>
            <tr v-if="!filteredMovements.length"><td colspan="7"><div class="empty-state compact">Tidak ada mutasi pada rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'procurements'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengadaan</th><th>Supplier</th><th>Progress Barang</th><th>Nilai Pengadaan</th><th>Status</th></tr></thead>
          <tbody>
            <tr v-for="p in filteredProcurements" :key="p.procurement_no">
              <td><strong>{{ p.procurement_no }}</strong><small class="table-sub">{{ formatDate(p.procurement_date) }} {{ p.po_number ? `· PO: ${p.po_number}` : '' }}</small></td>
              <td>{{ p.supplier_name }}</td>
              <td><strong>{{ p.progress_percent }}%</strong> ({{ formatNumber(p.total_received) }} / {{ formatNumber(p.total_ordered) }})</td>
              <td><strong>{{ formatCurrency(p.total_amount) }}</strong></td>
              <td><span class="status-pill" :class="p.status === 'completed' ? 'safe' : p.status === 'cancelled' ? 'out' : 'amber'">{{ p.status === 'completed' ? 'Terpenuhi' : p.status === 'partial' ? 'Sebagian' : p.status === 'cancelled' ? 'Dibatalkan' : 'Menunggu' }}</span></td>
            </tr>
            <tr v-if="!filteredProcurements.length"><td colspan="5"><div class="empty-state compact">Tidak ada pengadaan pada rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'opname'" class="table-wrap">
        <table>
          <thead><tr><th>No. SO</th><th>Barang</th><th>Kondisi</th><th>Sistem</th><th>Fisik</th><th>Selisih (+/-)</th><th>Alasan</th></tr></thead>
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
              </tr>
            </template>
            <tr v-if="!filteredStocktakes.length"><td colspan="7"><div class="empty-state compact">Tidak ada laporan stok opname pada rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="activeTab === 'liabilities'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengeluaran</th><th>Karyawan</th><th>Departemen</th><th>Barang</th><th>Sisa Dibawa</th><th>Keperluan</th></tr></thead>
          <tbody>
            <tr v-for="(l, idx) in filteredLiabilities" :key="idx">
              <td><strong>{{ l.issuances?.transaction_no }}</strong><small class="table-sub">{{ formatDate(l.issuances?.issued_at) }}</small></td>
              <td><strong>{{ l.issuances?.employees?.name }}</strong><small class="table-sub">{{ l.issuances?.employees?.nik }}</small></td>
              <td>{{ l.issuances?.employees?.departments?.name || '-' }}</td>
              <td>{{ variantLabel({ name: l.item_variants?.items?.name, size: l.item_variants?.size }) }}</td>
              <td><strong class="text-amber">{{ formatNumber(Number(l.quantity) - Number(l.returned_quantity) - Number(l.resolved_lost_quantity)) }} {{ l.item_variants?.items?.unit }}</strong></td>
              <td>{{ l.purpose }}</td>
            </tr>
            <tr v-if="!filteredLiabilities.length"><td colspan="6"><div class="empty-state compact">Tidak ada tanggungan aktif pada rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>

      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>Tanggal</th><th>No. Pengadaan</th><th>No. PO</th><th>Supplier</th><th>Nominal</th><th>Progress</th></tr></thead>
          <tbody>
            <tr v-for="(p, idx) in filteredPayments" :key="idx">
              <td>{{ formatDate(p.procurement_date) }}</td>
              <td><strong>{{ p.procurement_no }}</strong></td>
              <td>{{ p.po_number || '-' }}</td>
              <td>{{ p.supplier_name }}</td>
              <td><strong>{{ formatCurrency(p.total_amount) }}</strong></td>
              <td>{{ p.progress_percent }}%</td>
            </tr>
            <tr v-if="!filteredPayments.length"><td colspan="6"><div class="empty-state compact">Tidak ada history pembayaran pada rentang tanggal ini.</div></td></tr>
          </tbody>
        </table>
      </div>
    </section>

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
