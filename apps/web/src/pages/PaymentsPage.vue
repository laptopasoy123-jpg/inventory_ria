<script setup lang="ts">
import { computed, onActivated, onMounted, ref, watch } from 'vue'
import { ArrowUpDown, Download, ReceiptText, Search, ShoppingBag, Truck, Wallet } from '@lucide/vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, downloadCsv, formatCurrency, formatDate, getApiCacheVersion } from '@/lib/api'

interface ProcurementRecord {
  id: string
  procurement_no: string
  po_number: string | null
  procurement_date: string
  supplier_name: string
  vendor_type?: 'supplier' | 'online_shop'
  funding_source: 'company' | 'advanced'
  payment_method?: 'cash' | 'transfer'
  funder_name?: string | null
  total_amount: number
  reason: string
  notes?: string | null
  status: string
}

interface DirectPurchaseRow {
  id: string
  transaction_no: string
  procurement_id?: string | null
  received_date: string
  reason: string
  funding_source?: 'company' | 'advanced'
  payment_method?: 'cash' | 'transfer'
  suppliers?: { name: string; vendor_type?: 'supplier' | 'online_shop' } | null
  purchase_items: Array<{ quantity: number; item_variants?: { items?: { name: string; unit: string } | null } | null }>
}

interface UnifiedTxRow {
  id: string
  source: 'po' | 'non_po'
  date: string
  docNo: string
  refLabel: string
  vendor: string
  fundingLabel: string
  methodLabel: string
  amount: number | null
  note: string
}

const procurements = ref<ProcurementRecord[]>([])
const directPurchases = ref<DirectPurchaseRow[]>([])
const loading = ref(true)
const sourceTab = ref<'all' | 'po' | 'non_po'>('all')
const search = ref('')
const sortDir = ref<'desc' | 'asc'>('desc')
const page = ref(1)

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
      source: 'po',
      date: p.procurement_date,
      docNo: p.procurement_no,
      refLabel: p.po_number
        ? `PO: ${p.po_number}`
        : p.vendor_type === 'online_shop'
          ? 'Via PO · Toko Online'
          : 'Via Pengadaan (PO)',
      vendor: p.supplier_name || '-',
      fundingLabel: p.funding_source === 'advanced' ? `Talangan${p.funder_name ? ` (${p.funder_name})` : ''}` : 'Kas Perusahaan',
      methodLabel: p.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
      amount: Number(p.total_amount || 0),
      note: p.reason || p.notes || '-',
    }))

  const nonPoRows: UnifiedTxRow[] = directPurchases.value
    .filter((d) => !d.procurement_id)
    .map((d) => {
      const totalItems = (d.purchase_items ?? []).reduce((s, it) => s + Number(it.quantity || 0), 0)
      return {
        id: `nonpo-${d.id}`,
        source: 'non_po',
        date: d.received_date,
        docNo: d.transaction_no,
        refLabel: d.suppliers?.vendor_type === 'online_shop' ? 'Non-PO · Toko Online' : 'Non-PO · Langsung',
        vendor: d.suppliers?.name || '-',
        fundingLabel: d.funding_source === 'advanced' ? 'Talangan Langsung' : 'Pembelian Langsung',
        methodLabel: d.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
        amount: null,
        note: `${d.reason || 'Pembelian langsung'} (${totalItems} item)`,
      }
    })

  return [...poRows, ...nonPoRows]
})

const poCount = computed(() => unifiedRows.value.filter((r) => r.source === 'po').length)
const nonPoCount = computed(() => unifiedRows.value.filter((r) => r.source === 'non_po').length)
const totalRecordedNominal = computed(() =>
  unifiedRows.value.reduce((s, r) => s + Number(r.amount || 0), 0),
)

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  const list = unifiedRows.value.filter((r) => {
    if (sourceTab.value !== 'all' && r.source !== sourceTab.value) return false
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

const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * 10, page.value * 10))
watch([sourceTab, search], () => { page.value = 1 })

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

async function load() {
  loading.value = true
  try {
    const [pRes, purRes] = await Promise.all([
      api<{ data: ProcurementRecord[] }>('/api/procurements'),
      api<{ data: DirectPurchaseRow[] }>('/api/transactions/purchases'),
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
        <p>Semua pengadaan barang (PO) yang dimasukkan nominalnya dan pembelian langsung (Non-PO) otomatis terjaring di sini.</p>
      </div>
      <div class="intro-actions">
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

      <div class="table-toolbar">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari nomor dokumen, PO, supplier, sumber dana, atau keterangan..." /></label>
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
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="7"><div class="empty-state compact"><Wallet :size="28" /><strong>Belum ada history pembayaran</strong><span>Buat pengadaan barang dengan nominal harga atau catat pembelian langsung di Barang Masuk.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="7"><div class="loading-row">Memuat history pembayaran...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

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
