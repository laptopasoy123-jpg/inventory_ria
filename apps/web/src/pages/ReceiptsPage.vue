<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowUpDown, Edit3, Plus, Search, Truck } from '@lucide/vue'
import PaginationBar from '@/components/PaginationBar.vue'
import ReceiptModal, { type EditablePurchase } from '@/components/ReceiptModal.vue'
import { api, conditionLabel, formatDate, formatNumber } from '@/lib/api'

interface PurchaseRow extends EditablePurchase {
  transaction_no: string
  po_number: string | null
  delivery_note_number: string | null
  suppliers?: { name: string; code?: string; vendor_type?: 'supplier' | 'online_shop' } | null
  procurements?: { procurement_no: string; po_number: string | null } | null
}

const route = useRoute()
const rows = ref<PurchaseRow[]>([])
const loading = ref(true)
const search = ref('')
const filterSource = ref('all')
const page = ref(1)
const showModal = ref(false)
const editingRow = ref<EditablePurchase | null>(null)

const sortDir = ref<'desc' | 'asc'>('desc')

const filtered = computed(() => {
  const list = rows.value.filter((r) => {
    if (filterSource.value === 'procurement' && !r.procurements) return false
    if (filterSource.value === 'direct' && r.procurements) return false
    if (!search.value.trim()) return true
    const q = search.value.toLowerCase()
    return (
      r.transaction_no.toLowerCase().includes(q) ||
      (r.procurements?.procurement_no || '').toLowerCase().includes(q) ||
      (r.po_number || '').toLowerCase().includes(q) ||
      (r.suppliers?.name || '').toLowerCase().includes(q)
    )
  })
  return [...list].sort((a, b) => {
    const dateCmp = String(a.received_date || '').localeCompare(String(b.received_date || ''))
    const cmp = dateCmp !== 0 ? dateCmp : a.transaction_no.localeCompare(b.transaction_no, undefined, { numeric: true })
    return sortDir.value === 'asc' ? cmp : -cmp
  })
})

const pagedRows = computed(() => filtered.value.slice((page.value - 1) * 10, page.value * 10))
watch([search, filterSource], () => { page.value = 1 })

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

async function load() {
  loading.value = true
  try {
    const res = await api<{ data: PurchaseRow[] }>('/api/transactions/purchases')
    rows.value = res.data
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  if (route.query.action === 'new') openAdd()
  void load()
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
        <button :class="{ active: filterSource === 'all' }" @click="filterSource = 'all'">Semua Penerimaan</button>
        <button :class="{ active: filterSource === 'procurement' }" @click="filterSource = 'procurement'">Dari Pengadaan (PO)</button>
        <button :class="{ active: filterSource === 'direct' }" @click="filterSource = 'direct'">Pembelian Langsung</button>
      </div>
      <div class="table-toolbar">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Penerimaan, No. Pengadaan, No. PO, atau supplier..." /></label>
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
                <button class="icon-button" title="Edit barang masuk" @click="openEdit(row)"><Edit3 :size="15" /></button>
              </td>
            </tr>
            <tr v-if="!loading && !filtered.length">
              <td colspan="6"><div class="empty-state"><Truck :size="32" /><strong>Belum ada barang masuk tercatat</strong><span>Klik "Catat Barang Masuk" dan pilih Pengadaan yang datang.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat riwayat barang masuk...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filtered.length" />
    </section>

    <ReceiptModal :open="showModal" :editing-purchase="editingRow" @close="showModal = false" @saved="load" />
  </div>
</template>
