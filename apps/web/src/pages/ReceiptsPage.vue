<script setup lang="ts">
import { computed, onActivated, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowUpDown, CalendarRange, Edit3, Eye, Plus, RotateCcw, Search, Trash2, Truck } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import ReceiptModal, { type EditablePurchase } from '@/components/ReceiptModal.vue'
import { api, attachmentUrl, conditionLabel, formatDate, formatNumber, getApiCacheVersion, variantLabel } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface PurchaseRow extends EditablePurchase {
  transaction_no: string
  po_number: string | null
  delivery_note_number: string | null
  suppliers?: { name: string; code?: string; vendor_type?: 'supplier' | 'online_shop' } | null
  procurements?: { procurement_no: string; po_number: string | null } | null
}

const route = useRoute()
const master = useMasterStore()
const toast = useToast()

const rows = ref<PurchaseRow[]>([])
const loading = ref(true)
const search = ref('')
const filterSource = ref('all')
const supplierFilter = ref('all')
const receiverFilter = ref('all')
const conditionFilter = ref('all')
const dateFrom = ref('')
const dateTo = ref('')
const page = ref(1)
const showModal = ref(false)
const editingRow = ref<EditablePurchase | null>(null)
const showPreviewModal = ref(false)
const previewRow = ref<PurchaseRow | null>(null)

function openPreview(row: PurchaseRow) {
  previewRow.value = row
  showPreviewModal.value = true
}

const sortDir = ref<'desc' | 'asc'>('desc')

const supplierFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) if (r.suppliers?.name) names.add(r.suppliers.name)
  for (const s of master.suppliers) if (s.name) names.add(s.name)
  return [
    { value: 'all', label: 'Semua Supplier / Toko' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const receiverFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) {
    for (const it of r.purchase_items) if (it.receiver_name) names.add(it.receiver_name)
  }
  for (const o of master.officers) if (o.name) names.add(o.name)
  return [
    { value: 'all', label: 'Semua Petugas Penerima' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const conditionFilterOptions = [
  { value: 'all', label: 'Semua Kondisi' },
  { value: 'new', label: 'Baru' },
  { value: 'used_good', label: 'Bekas Layak' },
  { value: 'quarantine', label: 'Karantina' },
  { value: 'damaged', label: 'Rusak' },
]

const hasActiveFilters = computed(() =>
  Boolean(search.value.trim() || supplierFilter.value !== 'all' || receiverFilter.value !== 'all' || conditionFilter.value !== 'all' || dateFrom.value || dateTo.value),
)

function resetFilters() {
  search.value = ''
  supplierFilter.value = 'all'
  receiverFilter.value = 'all'
  conditionFilter.value = 'all'
  dateFrom.value = ''
  dateTo.value = ''
}

const filtered = computed(() => {
  const list = rows.value.filter((r) => {
    if (filterSource.value === 'procurement' && !r.procurements) return false
    if (filterSource.value === 'direct' && r.procurements) return false
    if (supplierFilter.value !== 'all' && (r.suppliers?.name || '') !== supplierFilter.value) return false
    if (receiverFilter.value !== 'all' && !r.purchase_items.some((it) => it.receiver_name === receiverFilter.value)) return false
    if (conditionFilter.value !== 'all' && !r.purchase_items.some((it) => it.condition === conditionFilter.value)) return false
    const d = (r.received_date || '').slice(0, 10)
    if (dateFrom.value && d < dateFrom.value) return false
    if (dateTo.value && d > dateTo.value) return false
    if (!search.value.trim()) return true
    const q = search.value.toLowerCase()
    return (
      r.transaction_no.toLowerCase().includes(q) ||
      (r.procurements?.procurement_no || '').toLowerCase().includes(q) ||
      (r.po_number || '').toLowerCase().includes(q) ||
      (r.suppliers?.name || '').toLowerCase().includes(q) ||
      r.reason.toLowerCase().includes(q) ||
      r.purchase_items.some((it) => (it.item_variants?.items?.name || '').toLowerCase().includes(q))
    )
  })
  return [...list].sort((a, b) => {
    const dateCmp = String(a.received_date || '').localeCompare(String(b.received_date || ''))
    const cmp = dateCmp !== 0 ? dateCmp : a.transaction_no.localeCompare(b.transaction_no, undefined, { numeric: true })
    return sortDir.value === 'asc' ? cmp : -cmp
  })
})

const pagedRows = computed(() => {
  const maxPage = Math.max(1, Math.ceil(filtered.value.length / 10))
  const cur = Math.min(Math.max(1, page.value), maxPage)
  return filtered.value.slice((cur - 1) * 10, cur * 10)
})
watch([search, filterSource, supplierFilter, receiverFilter, conditionFilter, dateFrom, dateTo], () => { page.value = 1 })

function summarizePurchaseItems(items: PurchaseRow['purchase_items']) {
  const map = new Map<string, { name: string; unit: string; qty: number; conditions: Set<string> }>()
  for (const it of items) {
    const name = it.item_variants?.items?.name || 'Barang'
    const unit = it.item_variants?.items?.unit || ''
    const size = it.item_variants?.size
    const label = size && size !== '-' && size !== 'All Size' ? `${name} (${size})` : name
    const key = label.toLowerCase()
    const prev = map.get(key)
    if (prev) {
      prev.qty += Number(it.quantity)
      prev.conditions.add(conditionLabel(it.condition))
    } else {
      map.set(key, { name: label, unit, qty: Number(it.quantity), conditions: new Set([conditionLabel(it.condition)]) })
    }
  }
  return [...map.values()].map((v) => ({ ...v, condText: [...v.conditions].join(', ') }))
}

function openAdd() {
  editingRow.value = null
  showModal.value = true
}

function openEdit(row: PurchaseRow) {
  editingRow.value = row
  showModal.value = true
}

async function deletePurchase(row: PurchaseRow) {
  if (!window.confirm(`Hapus transaksi barang masuk "${row.transaction_no}"? Stok inventaris yang bertambah dari transaksi ini akan dikurangi kembali.`)) return
  try {
    await api(`/api/transactions/purchases/${row.id}`, { method: 'DELETE' })
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Barang masuk ${row.transaction_no} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus barang masuk')
  }
}

async function load() {
  loading.value = true
  try {
    const res = await api<{ data: PurchaseRow[] }>('/api/transactions/purchases')
    rows.value = res.data
  } finally {
    loading.value = false
  }
}

let lastCacheVer = -1
onMounted(() => {
  if (route.query.action === 'new') openAdd()
  lastCacheVer = getApiCacheVersion()
  void Promise.all([load(), master.refresh()])
})
onActivated(() => {
  if (route.query.action === 'new') openAdd()
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
        <p class="eyebrow">Penerimaan Gudang</p>
        <h2>Barang Masuk</h2>
        <p>Catat barang datang berdasarkan Pengadaan (PO) dengan pencocokan otomatis atau pembelian langsung.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openAdd"><Plus :size="17" /> Catat Barang Masuk</button>
      </div>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: filterSource === 'all' }" @click="filterSource = 'all'">Semua Penerimaan ({{ rows.length }})</button>
        <button :class="{ active: filterSource === 'procurement' }" @click="filterSource = 'procurement'">Dari Pengadaan (PO)</button>
        <button :class="{ active: filterSource === 'direct' }" @click="filterSource = 'direct'">Pembelian Langsung</button>
      </div>
      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Penerimaan, No. Pengadaan, PO, barang, atau supplier..." /></label>
        <div class="date-range-inline">
          <CalendarRange :size="15" />
          <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" />
          <span class="date-sep">s/d</span>
          <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" />
        </div>
        <ModernSelect v-model="supplierFilter" :options="supplierFilterOptions" compact searchable search-placeholder="Cari supplier / toko..." />
        <ModernSelect v-model="receiverFilter" :options="receiverFilterOptions" compact searchable search-placeholder="Cari petugas penerima..." />
        <ModernSelect v-model="conditionFilter" :options="conditionFilterOptions" compact searchable search-placeholder="Cari kondisi..." />
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
                  No. Penerimaan (Tgl) <ArrowUpDown :size="13" /> <span>{{ sortDir === 'asc' ? '↑' : '↓' }}</span>
                </button>
              </th>
              <th>Referensi Pengadaan</th><th>Toko Online / Supplier</th><th>Item Masuk</th><th>Petugas Penerima</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td>
                <strong>{{ row.transaction_no }}</strong>
                <small class="table-sub">{{ formatDate(row.received_date) }}</small>
              </td>
              <td>
                <template v-if="row.procurements">
                  <span class="status-pill safe">{{ row.procurements.procurement_no }}</span>
                  <small v-if="row.procurements.po_number" class="table-sub">PO: {{ row.procurements.po_number }}</small>
                </template>
                <span v-else class="tag-pill">Pembelian Langsung</span>
              </td>
              <td>
                <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                  <span class="tag-pill">{{ row.suppliers?.vendor_type === 'online_shop' ? 'Toko Online' : 'Supplier' }}</span>
                  <strong class="table-main">{{ row.suppliers?.name || '-' }}</strong>
                </div>
                <small class="table-sub">{{ row.reason }}</small>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="(it, iIdx) in summarizePurchaseItems(row.purchase_items)" :key="iIdx">
                    <strong>+{{ formatNumber(it.qty) }} {{ it.unit }}</strong>
                    {{ it.name }} · <em>{{ it.condText }}</em>
                  </span>
                </div>
              </td>
              <td>{{ row.purchase_items[0]?.receiver_name || '-' }}</td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Preview detail barang masuk" @click="openPreview(row)"><Eye :size="15" /></button>
                  <button class="icon-button" title="Edit barang masuk" @click="openEdit(row)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus barang masuk" @click="deletePurchase(row)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filtered.length">
              <td colspan="6"><div class="empty-state"><Truck :size="32" /><strong>Belum ada barang masuk yang cocok</strong><span>Ubah filter atau klik "Catat Barang Masuk".</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat riwayat barang masuk...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filtered.length" />
    </section>

    <BaseModal
      :open="showPreviewModal"
      :title="`Detail Barang Masuk · ${previewRow?.transaction_no || ''}`"
      eyebrow="Preview Penerimaan Gudang"
      :subtitle="previewRow ? `Tanggal Masuk: ${formatDate(previewRow.received_date)}` : ''"
      size="lg"
      @close="showPreviewModal = false"
    >
      <div v-if="previewRow" class="detail-stack">
        <div class="summary-banner">
          <div>
            <small>Referensi Pengadaan</small>
            <strong>{{ previewRow.procurements ? `${previewRow.procurements.procurement_no}${previewRow.procurements.po_number ? ` · PO: ${previewRow.procurements.po_number}` : ''}` : 'Pembelian Langsung (Non-PO)' }}</strong>
          </div>
          <div>
            <small>Supplier / Toko</small>
            <strong>{{ previewRow.suppliers?.name || '-' }}</strong>
          </div>
          <div>
            <small>Sumber Dana &amp; Metode</small>
            <strong>{{ previewRow.funding_source === 'advanced' ? 'Talangan' : 'Kas Perusahaan' }} · {{ previewRow.payment_method === 'cash' ? 'Tunai' : 'Transfer' }}</strong>
          </div>
        </div>
        <p class="muted-text" style="font-size:12.5px;"><strong>Keterangan:</strong> {{ previewRow.reason || '-' }}</p>
        <div v-if="previewRow.billing_proof_key">
          <a :href="attachmentUrl(previewRow.billing_proof_key)" target="_blank" rel="noopener noreferrer" class="secondary-button xs highlight">
            Lihat Dokumen / Bukti Lampiran ↗
          </a>
        </div>
        <div class="table-wrap" style="margin-top:0;">
          <table>
            <thead><tr><th>Barang &amp; Ukuran</th><th>Kondisi</th><th>Jumlah Masuk</th><th>Penerima</th><th>Catatan</th></tr></thead>
            <tbody>
              <tr v-for="it in previewRow.purchase_items" :key="it.id">
                <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }) }}</strong></td>
                <td><span class="tag-pill">{{ conditionLabel(it.condition) }}</span></td>
                <td><span class="delta-pill plus">+{{ formatNumber(it.quantity) }} {{ it.item_variants?.items?.unit }}</span></td>
                <td>{{ it.receiver_name || '-' }}</td>
                <td>{{ it.notes || '-' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showPreviewModal = false">Tutup</button>
        <button v-if="previewRow" type="button" class="primary-button" @click="showPreviewModal = false; openEdit(previewRow)">
          <Edit3 :size="15" /> Edit Barang Masuk
        </button>
      </template>
    </BaseModal>

    <ReceiptModal :open="showModal" :editing-purchase="editingRow" @close="showModal = false" @saved="load" />
  </div>
</template>
