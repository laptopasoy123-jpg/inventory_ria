<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ArrowUpDown, Edit3, Plus, ReceiptText, Search, ShoppingBag, Truck, Wallet } from '@lucide/vue'
import PaginationBar from '@/components/PaginationBar.vue'
import PaymentModal, { type EditablePayment, type ProcurementPayItem } from '@/components/PaymentModal.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, formatCurrency, formatDate } from '@/lib/api'

interface ProcurementPayRow extends ProcurementPayItem {
  procurement_date: string
  progress_percent: number
  status: string
}

interface PaymentHistoryRow extends EditablePayment {
  procurements?: { procurement_no: string; po_number: string | null; suppliers?: { name: string } | null } | null
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
  typeLabel: string
  methodLabel: string
  amount: number | null
  note: string
  rawPayment?: PaymentHistoryRow
}

const procurements = ref<ProcurementPayRow[]>([])
const payments = ref<PaymentHistoryRow[]>([])
const directPurchases = ref<DirectPurchaseRow[]>([])
const loading = ref(true)
const sourceTab = ref<'all' | 'po' | 'non_po'>('all')
const search = ref('')
const sortDir = ref<'desc' | 'asc'>('desc')
const page = ref(1)

const showModal = ref(false)
const editingPay = ref<EditablePayment | null>(null)

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

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
      ? 'Riwayat Pembayaran Via Pengadaan (PO)'
      : kind === 'non_po'
        ? 'Riwayat Pembelian Langsung (Non-PO)'
        : kind === 'nominal'
          ? 'Rincian Nominal Pembayaran Tercatat'
          : 'Riwayat Semua Transaksi Pembayaran'
  statModalSubtitle.value =
    kind === 'nominal'
      ? `Total nominal tercatat: ${formatCurrency(totalPaidPo.value)} dari ${list.length} transaksi PO`
      : `Menampilkan ${list.length} riwayat transaksi`
  statModalEmpty.value = 'Belum ada riwayat transaksi pada kategori ini.'
  statModalColumns.value = [
    { key: 'date', label: 'Tanggal' },
    { key: 'doc', label: 'Sumber & Dokumen' },
    { key: 'vendor', label: 'Supplier / Toko' },
    { key: 'type', label: 'Jenis & Metode' },
    { key: 'amount', label: 'Nominal' },
    { key: 'note', label: 'Referensi / Catatan' },
  ]
  statModalRows.value = list.map((r) => ({
    date: formatDate(r.date),
    doc: { text: r.docNo, sub: r.refLabel, strong: true },
    vendor: r.vendor,
    type: { text: r.typeLabel, sub: r.methodLabel },
    amount: r.amount !== null ? { text: formatCurrency(r.amount), strong: true } : { text: 'Non-PO', pill: 'neutral' },
    note: r.note,
  }))
}

function payLabel(type: string) {
  const map: Record<string, string> = { dp: 'Uang Muka (DP)', installment: 'Termin / Cicilan', full: 'Pelunasan', reimbursement: 'Reimbursement' }
  return map[type] || type
}

const unifiedRows = computed<UnifiedTxRow[]>(() => {
  const poRows: UnifiedTxRow[] = payments.value.map((p) => ({
    id: `po-${p.id}`,
    source: 'po',
    date: p.paid_at,
    docNo: p.procurements?.procurement_no || '-',
    refLabel: p.procurements?.po_number ? `PO: ${p.procurements.po_number}` : 'Via Pengadaan (PO)',
    vendor: p.procurements?.suppliers?.name || '-',
    typeLabel: payLabel(p.payment_type),
    methodLabel: p.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
    amount: Number(p.amount || 0),
    note: p.reference_no || p.notes || '-',
    rawPayment: p,
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
        typeLabel: d.funding_source === 'advanced' ? 'Talangan Langsung' : 'Pembelian Langsung',
        methodLabel: d.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank',
        amount: null,
        note: `${d.reason || 'Pembelian langsung'} (${totalItems} item)`,
      }
    })

  return [...poRows, ...nonPoRows]
})

const poCount = computed(() => unifiedRows.value.filter((r) => r.source === 'po').length)
const nonPoCount = computed(() => unifiedRows.value.filter((r) => r.source === 'non_po').length)
const totalPaidPo = computed(() => payments.value.reduce((s, p) => s + Number(p.amount || 0), 0))

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  const list = unifiedRows.value.filter((r) => {
    if (sourceTab.value !== 'all' && r.source !== sourceTab.value) return false
    if (!q) return true
    return (
      r.docNo.toLowerCase().includes(q) ||
      r.refLabel.toLowerCase().includes(q) ||
      r.vendor.toLowerCase().includes(q) ||
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

async function load() {
  loading.value = true
  try {
    const [pRes, hRes, purRes] = await Promise.all([
      api<{ data: ProcurementPayRow[] }>('/api/procurements'),
      api<{ data: PaymentHistoryRow[] }>('/api/procurements/payments/all'),
      api<{ data: DirectPurchaseRow[] }>('/api/transactions/purchases'),
    ])
    procurements.value = pRes.data
    payments.value = hRes.data
    directPurchases.value = purRes.data
  } finally {
    loading.value = false
  }
}

function openAddTx() {
  editingPay.value = null
  showModal.value = true
}

function openEditTx(pay: PaymentHistoryRow) {
  editingPay.value = pay
  showModal.value = true
}

onMounted(load)
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Arsip Transaksi Keuangan</p>
        <h2>Data Transaksi Pembayaran</h2>
        <p>Rekap seluruh transaksi pembayaran baik melalui Pengadaan (PO) maupun Pembelian Langsung (Non-PO).</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" :disabled="!procurements.length" @click="openAddTx">
          <Plus :size="17" /> Catat Transaksi Pembayaran
        </button>
      </div>
    </section>

    <section class="inv-stats-grid">
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('all')">
        <div class="inv-stat-icon"><ReceiptText :size="22" /></div>
        <div>
          <span>Semua Transaksi</span>
          <strong>{{ unifiedRows.length }}</strong>
          <small>Klik riwayat PO &amp; Non-PO</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('po')">
        <div class="inv-stat-icon"><ShoppingBag :size="22" /></div>
        <div>
          <span>Transaksi Via PO</span>
          <strong>{{ poCount }}</strong>
          <small>Klik riwayat transaksi PO</small>
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
          <strong>{{ formatCurrency(totalPaidPo) }}</strong>
          <small>Klik rincian nominal bayar</small>
        </div>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: sourceTab === 'all' }" @click="sourceTab = 'all'">Semua Transaksi ({{ unifiedRows.length }})</button>
        <button :class="{ active: sourceTab === 'po' }" @click="sourceTab = 'po'">Via Pengadaan / PO ({{ poCount }})</button>
        <button :class="{ active: sourceTab === 'non_po' }" @click="sourceTab = 'non_po'">Non-PO / Pembelian Langsung ({{ nonPoCount }})</button>
      </div>

      <div class="table-toolbar">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari nomor dokumen, PO, supplier, atau catatan..." /></label>
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
              <th>Jenis Transaksi</th>
              <th>Metode</th>
              <th>Nominal</th>
              <th>Referensi / Keterangan</th>
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
              <td><span class="tag-pill">{{ row.typeLabel }}</span></td>
              <td>{{ row.methodLabel }}</td>
              <td>
                <strong v-if="row.amount !== null">{{ formatCurrency(row.amount) }}</strong>
                <span v-else class="muted-text">Pembelian Langsung</span>
              </td>
              <td>{{ row.note }}</td>
              <td>
                <button v-if="row.rawPayment" class="icon-button" title="Edit transaksi pembayaran" @click="openEditTx(row.rawPayment)">
                  <Edit3 :size="15" />
                </button>
                <span v-else class="muted-text">—</span>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="8"><div class="empty-state compact"><Wallet :size="28" /><strong>Belum ada data transaksi pembayaran</strong><span>Catat transaksi pembayaran PO atau pembelian langsung di Barang Masuk.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="8"><div class="loading-row">Memuat data transaksi pembayaran...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <PaymentModal :open="showModal" :procurements="procurements" :editing-payment="editingPay" @close="showModal = false" @saved="load" />

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
