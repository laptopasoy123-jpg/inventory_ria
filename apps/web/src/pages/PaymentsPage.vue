<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { ArrowUpDown, CalendarRange, Download, Edit3, Eye, FileDown, ReceiptText, RotateCcw, Search, ShoppingBag, Trash2, Truck, Wallet } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import ReceiptModal, { type EditablePurchase } from '@/components/ReceiptModal.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, attachmentUrl, downloadCsv, formatCurrency, formatDate, getApiCacheVersion, imageUrlToDataUrl } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface ProcurementRecord {
  id: string
  procurement_no: string
  po_number: string | null
  pr_number?: string | null
  department_id?: string | null
  procurement_date: string
  expected_date?: string | null
  supplier_id?: string
  supplier_name: string
  vendor_type?: 'supplier' | 'online_shop'
  funding_source: 'company' | 'advanced'
  payment_method?: 'cash' | 'transfer'
  funder_id?: string | null
  funder_name?: string | null
  total_amount: number
  reason: string
  notes?: string | null
  status: string
  items?: Array<{ id?: string; variant_id: string; ordered_quantity: number; unit_price: number; notes?: string | null }>
}

interface DirectPurchaseRow extends EditablePurchase {
  transaction_no: string
  procurement_id?: string | null
  suppliers?: { name: string; vendor_type?: 'supplier' | 'online_shop' } | null
}

interface UnifiedTxRow {
  id: string
  rawId: string
  source: 'po' | 'non_po'
  date: string
  docNo: string
  refLabel: string
  vendor: string
  fundingSource: 'company' | 'advanced'
  fundingLabel: string
  paymentMethod: 'cash' | 'transfer'
  methodLabel: string
  amount: number | null
  note: string
  poRecord?: ProcurementRecord
  directRecord?: DirectPurchaseRow
}

const master = useMasterStore()
const toast = useToast()

const procurements = ref<ProcurementRecord[]>([])
const directPurchases = ref<DirectPurchaseRow[]>([])
const loading = ref(true)
const sourceTab = ref<'all' | 'po' | 'non_po'>('all')
const search = ref('')
const vendorFilter = ref('all')
const fundingFilter = ref('all')
const methodFilter = ref('all')
const dateFrom = ref('')
const dateTo = ref('')
const sortDir = ref<'desc' | 'asc'>('desc')
const page = ref(1)

// Edit PO modal
const showPoEditModal = ref(false)
const savingPoEdit = ref(false)
const editingPo = ref<ProcurementRecord | null>(null)
const poEditForm = reactive({
  procurementDate: '',
  poNumber: '',
  supplierId: '',
  fundingSource: 'company' as 'company' | 'advanced',
  paymentMethod: 'transfer' as 'cash' | 'transfer',
  funderId: '',
  totalAmount: 0,
  reason: '',
  notes: '',
})

// Edit Non-PO modal
const showReceiptEditModal = ref(false)
const editingDirectRow = ref<EditablePurchase | null>(null)

// Preview Modal
const showPreviewModal = ref(false)
const previewRow = ref<UnifiedTxRow | null>(null)

function openPreview(row: UnifiedTxRow) {
  previewRow.value = row
  showPreviewModal.value = true
}

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

const unifiedRows = computed<UnifiedTxRow[]>(() => {
  const poRows: UnifiedTxRow[] = procurements.value
    .filter((p) => p.status !== 'cancelled' && Number(p.total_amount || 0) > 0)
    .map((p) => ({
      id: `po-${p.id}`,
      rawId: p.id,
      source: 'po',
      date: p.procurement_date,
      docNo: p.procurement_no,
      refLabel: p.po_number
        ? `PO: ${p.po_number}`
        : p.vendor_type === 'online_shop'
          ? 'Via PO · Toko Online'
          : 'Via Pengadaan (PO)',
      vendor: p.supplier_name || '-',
      fundingSource: p.funding_source || 'company',
      fundingLabel: p.funding_source === 'advanced' ? `Talangan${p.funder_name ? ` (${p.funder_name})` : ''}` : 'Kas Perusahaan',
      paymentMethod: p.payment_method || 'transfer',
      methodLabel: p.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
      amount: Number(p.total_amount || 0),
      note: p.reason || p.notes || '-',
      poRecord: p,
    }))

  const nonPoRows: UnifiedTxRow[] = directPurchases.value
    .filter((d) => !d.procurement_id)
    .map((d) => {
      const totalItems = (d.purchase_items ?? []).reduce((s, it) => s + Number(it.quantity || 0), 0)
      return {
        id: `nonpo-${d.id}`,
        rawId: d.id,
        source: 'non_po',
        date: d.received_date,
        docNo: d.transaction_no,
        refLabel: d.suppliers?.vendor_type === 'online_shop' ? 'Non-PO · Toko Online' : 'Non-PO · Langsung',
        vendor: d.suppliers?.name || '-',
        fundingSource: d.funding_source || 'company',
        fundingLabel: d.funding_source === 'advanced' ? 'Talangan Langsung' : 'Pembelian Langsung',
        paymentMethod: d.payment_method || 'transfer',
        methodLabel: d.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
        amount: null,
        note: `${d.reason || 'Pembelian langsung'} (${totalItems} item)`,
        directRecord: d,
      }
    })

  return [...poRows, ...nonPoRows]
})

const vendorFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of unifiedRows.value) if (r.vendor && r.vendor !== '-') names.add(r.vendor)
  for (const s of master.suppliers) if (s.name) names.add(s.name)
  return [
    { value: 'all', label: 'Semua Supplier / Toko' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const fundingFilterOptions = [
  { value: 'all', label: 'Semua Sumber Dana' },
  { value: 'company', label: 'Kas Perusahaan' },
  { value: 'advanced', label: 'Talangan (Reimbursement)' },
]

const methodFilterOptions = [
  { value: 'all', label: 'Semua Metode Bayar' },
  { value: 'transfer', label: 'Transfer Bank' },
  { value: 'cash', label: 'Tunai / Kas' },
]

const supplierOptions = computed(() =>
  master.suppliers.map((s) => ({
    value: s.id,
    label: s.name,
    badge: s.vendor_type === 'online_shop' ? 'Online' : 'Supplier',
  })),
)

const funderOptions = computed(() =>
  master.funders.map((f) => ({ value: f.id, label: f.name, sublabel: f.notes || undefined })),
)

const hasActiveFilters = computed(() =>
  Boolean(search.value.trim() || vendorFilter.value !== 'all' || fundingFilter.value !== 'all' || methodFilter.value !== 'all' || dateFrom.value || dateTo.value),
)

function resetFilters() {
  search.value = ''
  vendorFilter.value = 'all'
  fundingFilter.value = 'all'
  methodFilter.value = 'all'
  dateFrom.value = ''
  dateTo.value = ''
}

const poCount = computed(() => unifiedRows.value.filter((r) => r.source === 'po').length)
const nonPoCount = computed(() => unifiedRows.value.filter((r) => r.source === 'non_po').length)
const totalRecordedNominal = computed(() =>
  unifiedRows.value.reduce((s, r) => s + Number(r.amount || 0), 0),
)

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  const list = unifiedRows.value.filter((r) => {
    if (sourceTab.value !== 'all' && r.source !== sourceTab.value) return false
    if (vendorFilter.value !== 'all' && r.vendor !== vendorFilter.value) return false
    if (fundingFilter.value !== 'all' && r.fundingSource !== fundingFilter.value) return false
    if (methodFilter.value !== 'all' && r.paymentMethod !== methodFilter.value) return false
    const d = (r.date || '').slice(0, 10)
    if (dateFrom.value && d < dateFrom.value) return false
    if (dateTo.value && d > dateTo.value) return false
    if (!q) return true
    return (
      r.docNo.toLowerCase().includes(q) ||
      r.refLabel.toLowerCase().includes(q) ||
      r.vendor.toLowerCase().includes(q) ||
      r.fundingLabel.toLowerCase().includes(q) ||
      r.note.toLowerCase().includes(q)
    )
  })
  return [...list].sort((a, b) => {
    const cmp = String(a.date || '').localeCompare(String(b.date || ''))
    const tie = cmp !== 0 ? cmp : a.docNo.localeCompare(b.docNo, undefined, { numeric: true })
    return sortDir.value === 'asc' ? tie : -tie
  })
})

const filteredNominalTotal = computed(() =>
  filteredRows.value.reduce((s, r) => s + Number(r.amount || 0), 0),
)

const pagedRows = computed(() => {
  const maxPage = Math.max(1, Math.ceil(filteredRows.value.length / 10))
  const cur = Math.min(Math.max(1, page.value), maxPage)
  return filteredRows.value.slice((cur - 1) * 10, cur * 10)
})
watch([sourceTab, search, vendorFilter, fundingFilter, methodFilter, dateFrom, dateTo], () => { page.value = 1 })

function openStatHistory(kind: 'all' | 'po' | 'non_po' | 'nominal') {
  statModalOpen.value = true
  const list =
    kind === 'po' || kind === 'nominal'
      ? unifiedRows.value.filter((r) => r.source === 'po')
      : kind === 'non_po'
        ? unifiedRows.value.filter((r) => r.source === 'non_po')
        : unifiedRows.value

  statModalTitle.value =
    kind === 'po'
      ? 'History Pembayaran Via Pengadaan (PO)'
      : kind === 'non_po'
        ? 'History Pembelian Langsung (Non-PO)'
        : kind === 'nominal'
          ? 'Rincian Total Nominal Tercatat'
          : 'History Semua Transaksi Pembayaran'
  statModalSubtitle.value =
    kind === 'nominal'
      ? `Total nominal terjaring: ${formatCurrency(totalRecordedNominal.value)} dari ${list.length} transaksi PO`
      : `Menampilkan ${list.length} transaksi otomatis dari Pengadaan & Barang Masuk`
  statModalEmpty.value = 'Belum ada history pembayaran pada kategori ini.'
  statModalColumns.value = [
    { key: 'date', label: 'Tanggal' },
    { key: 'doc', label: 'Sumber & Dokumen' },
    { key: 'vendor', label: 'Supplier / Toko' },
    { key: 'type', label: 'Sumber Dana & Metode' },
    { key: 'amount', label: 'Nominal' },
    { key: 'note', label: 'Keterangan' },
  ]
  statModalRows.value = list.map((r) => ({
    date: formatDate(r.date),
    doc: { text: r.docNo, sub: r.refLabel, strong: true },
    vendor: r.vendor,
    type: { text: r.fundingLabel, sub: r.methodLabel },
    amount: r.amount !== null ? { text: formatCurrency(r.amount), strong: true } : { text: 'Non-PO', pill: 'neutral' },
    note: r.note,
  }))
}

function openEditRow(row: UnifiedTxRow) {
  if (row.source === 'non_po' && row.directRecord) {
    editingDirectRow.value = row.directRecord
    showReceiptEditModal.value = true
    return
  }
  if (row.source === 'po' && row.poRecord) {
    const p = row.poRecord
    editingPo.value = p
    poEditForm.procurementDate = (p.procurement_date || '').slice(0, 10)
    poEditForm.poNumber = p.po_number || ''
    poEditForm.supplierId = p.supplier_id || master.suppliers.find((s) => s.name === p.supplier_name)?.id || ''
    poEditForm.fundingSource = p.funding_source || 'company'
    poEditForm.paymentMethod = p.payment_method || 'transfer'
    poEditForm.funderId = p.funder_id || master.funders[0]?.id || ''
    poEditForm.totalAmount = Number(p.total_amount || 0)
    poEditForm.reason = p.reason || ''
    poEditForm.notes = p.notes || ''
    showPoEditModal.value = true
  }
}

async function submitPoEdit() {
  if (!editingPo.value) return
  savingPoEdit.value = true
  try {
    const existingItems = editingPo.value.items?.length
      ? editingPo.value.items.map((it) => ({
          id: it.id,
          variantId: it.variant_id,
          orderedQuantity: Number(it.ordered_quantity),
          unitPrice: Number(it.unit_price || 0),
          notes: it.notes || null,
        }))
      : []

    if (!existingItems.length) {
      toast.error('Detail item pengadaan tidak ditemukan, silakan edit melalui menu Pengadaan Barang')
      return
    }

    await api(`/api/procurements/${editingPo.value.id}`, {
      method: 'PUT',
      body: JSON.stringify({
        procurementDate: poEditForm.procurementDate,
        expectedDate: editingPo.value.expected_date || null,
        prNumber: editingPo.value.pr_number || null,
        poNumber: poEditForm.poNumber || null,
        departmentId: editingPo.value.department_id || null,
        supplierId: poEditForm.supplierId,
        reason: poEditForm.reason,
        fundingSource: poEditForm.fundingSource,
        paymentMethod: poEditForm.paymentMethod,
        funderId: poEditForm.fundingSource === 'advanced' ? poEditForm.funderId : null,
        totalAmount: Number(poEditForm.totalAmount || 0),
        notes: poEditForm.notes || null,
        items: existingItems,
      }),
    })
    toast.success(`History pembayaran ${editingPo.value.procurement_no} berhasil diperbarui`)
    showPoEditModal.value = false
    await load()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memperbarui pembayaran')
  } finally {
    savingPoEdit.value = false
  }
}

async function deleteRow(row: UnifiedTxRow) {
  const msg = row.source === 'po'
    ? `Hapus data pengadaan & pembayaran "${row.docNo}" secara permanen?`
    : `Hapus transaksi pembelian langsung "${row.docNo}"? Stok barang masuk terkait juga akan disesuaikan.`
  if (!window.confirm(msg)) return
  try {
    if (row.source === 'po') {
      await api(`/api/procurements/${row.rawId}`, { method: 'DELETE' })
    } else {
      await api(`/api/transactions/purchases/${row.rawId}`, { method: 'DELETE' })
    }
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Data ${row.docNo} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus data')
  }
}

function exportCsv() {
  downloadCsv(
    `history-pembayaran-${new Date().toISOString().slice(0, 10)}.csv`,
    ['Tanggal', 'Sumber', 'Dokumen', 'Referensi', 'Supplier / Toko', 'Sumber Dana', 'Metode', 'Nominal', 'Keterangan'],
    filteredRows.value.map((r) => [
      r.date?.slice(0, 10) || '',
      r.source === 'po' ? 'PO' : 'Non-PO',
      r.docNo,
      r.refLabel,
      r.vendor,
      r.fundingLabel,
      r.methodLabel,
      r.amount ?? 0,
      r.note,
    ]),
  )
}

async function downloadPdf() {
  try {
    const periodText = dateFrom.value && dateTo.value
      ? `${formatDate(dateFrom.value)} s/d ${formatDate(dateTo.value)}`
      : dateFrom.value
        ? `Mulai ${formatDate(dateFrom.value)}`
        : dateTo.value
          ? `Sampai ${formatDate(dateTo.value)}`
          : 'Semua Periode'
    const [{ generateInventoryPdf }, companyLogoDataUrl] = await Promise.all([
      import('@/lib/pdf-report'),
      master.company.logoKey ? imageUrlToDataUrl(attachmentUrl(master.company.logoKey)) : Promise.resolve(null),
    ])
    generateInventoryPdf({
      filename: `History-Pembayaran-${new Date().toISOString().slice(0, 10)}.pdf`,
      reportTitle: 'HISTORY PEMBAYARAN & PENGADAAN APD',
      periodLabel: periodText,
      companyName: master.company.name,
      companyTagline: `INVENTRA · ${master.company.tagline}`,
      companyLogoDataUrl,
      summaryStats: [
        { label: 'Transaksi Ditampilkan', value: `${filteredRows.value.length} transaksi` },
        { label: 'Via Pengadaan (PO)', value: `${filteredRows.value.filter((r) => r.source === 'po').length} PO` },
        { label: 'Pembelian Non-PO', value: `${filteredRows.value.filter((r) => r.source === 'non_po').length} Non-PO` },
        { label: 'Total Nominal', value: formatCurrency(filteredNominalTotal.value) },
      ],
      sections: [
        {
          title: 'Daftar History Pembayaran',
          subtitle: `Filter aktif: ${vendorFilter.value === 'all' ? 'Semua Supplier' : vendorFilter.value} · ${fundingFilter.value === 'all' ? 'Semua Dana' : fundingFilter.value === 'advanced' ? 'Talangan' : 'Kas Perusahaan'}`,
          headers: ['Tanggal', 'Sumber', 'No. Dokumen', 'Referensi', 'Supplier / Toko', 'Sumber Dana', 'Metode', 'Nominal', 'Keterangan'],
          rows: filteredRows.value.map((r) => [
            formatDate(r.date),
            r.source === 'po' ? 'PO' : 'Non-PO',
            r.docNo,
            r.refLabel,
            r.vendor,
            r.fundingLabel,
            r.methodLabel,
            r.amount !== null ? formatCurrency(r.amount) : 'Non-PO',
            r.note,
          ]),
        },
      ],
    })
    toast.success('PDF History Pembayaran berhasil diunduh!')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal membuat PDF history pembayaran')
  }
}

async function load() {
  loading.value = true
  try {
    const [pRes, purRes] = await Promise.all([
      api<{ data: ProcurementRecord[] }>('/api/procurements'),
      api<{ data: DirectPurchaseRow[] }>('/api/transactions/purchases'),
      master.refresh(),
    ])
    procurements.value = pRes.data
    directPurchases.value = purRes.data
  } finally {
    loading.value = false
  }
}

let lastCacheVer = -1
onMounted(() => { lastCacheVer = getApiCacheVersion(); void load() })
onActivated(() => {
  if (getApiCacheVersion() !== lastCacheVer) {
    lastCacheVer = getApiCacheVersion()
    void load()
  }
})
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Arsip Nominal &amp; Transaksi Keuangan</p>
        <h2>History Pembayaran</h2>
        <p>Semua pengadaan barang (PO) bernominal dan pembelian langsung (Non-PO) tercatat di sini. Mendukung edit, hapus, serta ekspor PDF &amp; CSV.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="downloadPdf"><FileDown :size="16" /> Download PDF</button>
        <button class="secondary-button" @click="exportCsv"><Download :size="16" /> Ekspor CSV</button>
      </div>
    </section>

    <section class="inv-stats-grid">
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('all')">
        <div class="inv-stat-icon"><ReceiptText :size="22" /></div>
        <div>
          <span>Semua History</span>
          <strong>{{ unifiedRows.length }}</strong>
          <small>Klik rincian PO &amp; Non-PO</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('po')">
        <div class="inv-stat-icon"><ShoppingBag :size="22" /></div>
        <div>
          <span>Via Pengadaan (PO)</span>
          <strong>{{ poCount }}</strong>
          <small>Klik riwayat nominal PO</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('non_po')">
        <div class="inv-stat-icon"><Truck :size="22" /></div>
        <div>
          <span>Pembelian Non-PO</span>
          <strong>{{ nonPoCount }}</strong>
          <small>Klik riwayat Non-PO / online</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('nominal')">
        <div class="inv-stat-icon"><Wallet :size="22" /></div>
        <div>
          <span>Total Nominal Tercatat</span>
          <strong>{{ formatCurrency(totalRecordedNominal) }}</strong>
          <small>Klik rincian seluruh nominal</small>
        </div>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: sourceTab === 'all' }" @click="sourceTab = 'all'">Semua History ({{ unifiedRows.length }})</button>
        <button :class="{ active: sourceTab === 'po' }" @click="sourceTab = 'po'">Via Pengadaan / PO ({{ poCount }})</button>
        <button :class="{ active: sourceTab === 'non_po' }" @click="sourceTab = 'non_po'">Non-PO / Pembelian Langsung ({{ nonPoCount }})</button>
      </div>

      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari nomor dokumen, PO, supplier, sumber dana, atau keterangan..." /></label>
        <div class="date-range-inline">
          <CalendarRange :size="15" />
          <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" />
          <span class="date-sep">s/d</span>
          <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" />
        </div>
        <ModernSelect v-model="vendorFilter" :options="vendorFilterOptions" compact searchable search-placeholder="Cari supplier / toko..." />
        <ModernSelect v-model="fundingFilter" :options="fundingFilterOptions" compact searchable search-placeholder="Cari sumber dana..." />
        <ModernSelect v-model="methodFilter" :options="methodFilterOptions" compact searchable search-placeholder="Cari metode..." />
        <button v-if="hasActiveFilters" type="button" class="secondary-button xs" @click="resetFilters">
          <RotateCcw :size="13" /> Reset
        </button>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>
                <button type="button" class="th-sort-btn" @click="sortDir = sortDir === 'asc' ? 'desc' : 'asc'">
                  Tanggal <ArrowUpDown :size="13" /> <span>{{ sortDir === 'asc' ? '↑' : '↓' }}</span>
                </button>
              </th>
              <th>Sumber &amp; Dokumen</th>
              <th>Supplier / Toko</th>
              <th>Sumber Dana</th>
              <th>Metode</th>
              <th>Nominal</th>
              <th>Keterangan</th>
              <th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td>{{ formatDate(row.date) }}</td>
              <td>
                <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                  <span class="status-pill" :class="row.source === 'po' ? 'safe' : 'neutral'">{{ row.source === 'po' ? 'PO' : 'Non-PO' }}</span>
                  <strong>{{ row.docNo }}</strong>
                </div>
                <small class="table-sub">{{ row.refLabel }}</small>
              </td>
              <td><strong class="table-main">{{ row.vendor }}</strong></td>
              <td><span class="tag-pill">{{ row.fundingLabel }}</span></td>
              <td>{{ row.methodLabel }}</td>
              <td>
                <strong v-if="row.amount !== null">{{ formatCurrency(row.amount) }}</strong>
                <span v-else class="muted-text">Pembelian Langsung</span>
              </td>
              <td>{{ row.note }}</td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Preview detail pembayaran" @click="openPreview(row)"><Eye :size="15" /></button>
                  <button class="icon-button" title="Edit transaksi pembayaran" @click="openEditRow(row)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus transaksi pembayaran" @click="deleteRow(row)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="8"><div class="empty-state compact"><Wallet :size="28" /><strong>Belum ada history pembayaran yang cocok</strong><span>Ubah filter atau buat pengadaan barang / pembelian langsung.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="8"><div class="loading-row">Memuat history pembayaran...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <!-- Preview Payment Modal -->
    <BaseModal
      :open="showPreviewModal"
      :title="`Detail Pembayaran · ${previewRow?.docNo || ''}`"
      eyebrow="Preview History Pembayaran"
      :subtitle="previewRow ? `${previewRow.refLabel} · Tanggal ${formatDate(previewRow.date)}` : ''"
      size="md"
      @close="showPreviewModal = false"
    >
      <div v-if="previewRow" class="detail-stack">
        <div class="summary-banner">
          <div><small>Sumber Transaksi</small><strong>{{ previewRow.source === 'po' ? 'Pengadaan (PO)' : 'Pembelian Langsung (Non-PO)' }}</strong></div>
          <div><small>Supplier / Toko</small><strong>{{ previewRow.vendor }}</strong></div>
          <div><small>Nominal Tercatat</small><strong class="text-primary">{{ previewRow.amount !== null ? formatCurrency(previewRow.amount) : 'Non-PO' }}</strong></div>
        </div>
        <div class="table-wrap" style="margin-top:0;">
          <table>
            <tbody>
              <tr><th style="width:36%;">No. Dokumen</th><td><strong>{{ previewRow.docNo }}</strong></td></tr>
              <tr><th>Referensi</th><td>{{ previewRow.refLabel }}</td></tr>
              <tr><th>Tanggal</th><td>{{ formatDate(previewRow.date) }}</td></tr>
              <tr><th>Sumber Dana</th><td><span class="tag-pill">{{ previewRow.fundingLabel }}</span></td></tr>
              <tr><th>Metode Pembayaran</th><td>{{ previewRow.methodLabel }}</td></tr>
              <tr><th>Keterangan / Alasan</th><td>{{ previewRow.note }}</td></tr>
            </tbody>
          </table>
        </div>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showPreviewModal = false">Tutup</button>
        <button v-if="previewRow" type="button" class="primary-button" @click="showPreviewModal = false; openEditRow(previewRow)">
          <Edit3 :size="15" /> Edit Pembayaran
        </button>
      </template>
    </BaseModal>

    <!-- Edit PO Payment Modal -->
    <BaseModal
      :open="showPoEditModal"
      :title="`Edit Pembayaran · ${editingPo?.procurement_no || ''}`"
      eyebrow="Revisi History Pembayaran"
      size="md"
      @close="showPoEditModal = false"
    >
      <form id="po-pay-edit-form" class="modal-form" @submit.prevent="submitPoEdit">
        <div class="form-grid-2">
          <label class="field"><span>Tanggal *</span><input v-model="poEditForm.procurementDate" type="date" required /></label>
          <label class="field"><span>Nomor PO</span><input v-model="poEditForm.poNumber" placeholder="PO-..." /></label>
        </div>
        <label class="field"><span>Supplier / Toko Online *</span>
          <ModernSelect v-model="poEditForm.supplierId" :options="supplierOptions" searchable required />
        </label>
        <div class="form-grid-3">
          <label class="field"><span>Sumber Dana</span>
            <ModernSelect v-model="poEditForm.fundingSource" :options="[{ value: 'company', label: 'Kas Perusahaan' }, { value: 'advanced', label: 'Talangan' }]" :searchable="false" />
          </label>
          <label class="field"><span>Metode Bayar</span>
            <ModernSelect v-model="poEditForm.paymentMethod" :options="[{ value: 'transfer', label: 'Transfer Bank' }, { value: 'cash', label: 'Tunai / Kas' }]" :searchable="false" />
          </label>
          <label class="field"><span>Total Nominal (Rp) *</span>
            <input v-model.number="poEditForm.totalAmount" type="number" min="0" step="100" required />
          </label>
        </div>
        <label v-if="poEditForm.fundingSource === 'advanced'" class="field"><span>Pihak Penalang *</span>
          <ModernSelect v-model="poEditForm.funderId" :options="funderOptions" searchable required />
        </label>
        <label class="field"><span>Keperluan / Keterangan *</span><input v-model="poEditForm.reason" required /></label>
        <label class="field"><span>Catatan Tambahan</span><input v-model="poEditForm.notes" placeholder="Opsional" /></label>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showPoEditModal = false">Batal</button>
        <button type="submit" form="po-pay-edit-form" class="primary-button" :disabled="savingPoEdit">
          {{ savingPoEdit ? 'Menyimpan...' : 'Simpan Perubahan' }}
        </button>
      </template>
    </BaseModal>

    <ReceiptModal :open="showReceiptEditModal" :editing-purchase="editingDirectRow" @close="showReceiptEditModal = false" @saved="load" />

    <StatHistoryModal
      :open="statModalOpen"
      :title="statModalTitle"
      :subtitle="statModalSubtitle"
      :columns="statModalColumns"
      :rows="statModalRows"
      :empty-text="statModalEmpty"
      @close="statModalOpen = false"
    />
  </div>
</template>
