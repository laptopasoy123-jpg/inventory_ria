<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  ArrowRightLeft, ClipboardList, Download,
  History, PackageOpen, Plus, Printer, Search, Trash2,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { api, attachmentUrl, conditionLabel, downloadCsv, formatDate, formatNumber, generateUuid, variantLabel } from '@/lib/api'
import { flaticonAssets, itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

type StockRow = {
  variant_id: string; item_id: string; code: string; name: string; category_id?: string; category_name: string;
  size: string; unit: string; photo_key?: string | null; stock_new: number; stock_used_good: number; stock_quarantine: number; stock_damaged: number;
  total_available: number; minimum_stock: number; stock_status: 'safe' | 'low' | 'out'
}

type MovementRow = {
  id: number; condition: string; quantity_delta: number; balance_after: number;
  movement_type: string; notes: string | null; occurred_at: string; profiles?: { full_name: string } | null
}

const route = useRoute()
const master = useMasterStore()
const toast = useToast()

const rows = ref<StockRow[]>([])
const search = ref('')
const debouncedSearch = ref('')
const status = ref('all')
const page = ref(1)
const totalPages = ref(1)
const total = ref(0)
const loading = ref(true)
let timer: number | undefined

const showItemModal = ref(false)

// Opening Stock Modal
const showOpeningModal = ref(false)
const savingOpening = ref(false)
const editingOpeningId = ref<string | null>(null)
const openingHistory = ref<Array<{
  id: string; transaction_no: string; recorded_at: string; officer_name: string; notes: string | null;
  opening_stock_items: Array<{ variant_id: string; condition: 'new' | 'used_good' | 'quarantine' | 'damaged'; quantity: number; notes: string | null }>
}>>([])
const openingForm = reactive({
  recordedAt: new Date().toISOString().slice(0, 10),
  officerName: 'Admin Gudang',
  notes: 'Stok fisik yang sudah ada sebelum sistem berjalan',
  items: [] as Array<{ variantId: string; condition: 'new' | 'used_good' | 'quarantine' | 'damaged'; quantity: number; notes: string }>,
})

// History Modal
const showHistoryModal = ref(false)
const historyRow = ref<StockRow | null>(null)
const movements = ref<MovementRow[]>([])
const loadingHistory = ref(false)

// Quarantine Transfer Modal
const showTransferModal = ref(false)
const transferRow = ref<StockRow | null>(null)
const savingTransfer = ref(false)
const transferForm = reactive({
  fromCondition: 'quarantine' as 'quarantine' | 'used_good' | 'new' | 'damaged',
  toCondition: 'used_good' as 'used_good' | 'damaged' | 'quarantine' | 'new',
  quantity: 1,
  notes: 'Selesai pembersihan / inspeksi karantina',
})

const filteredRows = computed(() => {
  return rows.value.filter((row) => {
    if (status.value !== 'all' && row.stock_status !== status.value) return false
    return true
  })
})

const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * 10, page.value * 10))

async function load() {
  loading.value = true
  try {
    const result = await api<{ data: StockRow[]; pagination: { total: number; totalPages: number } }>(
      `/api/inventory?page=1&limit=200&search=${encodeURIComponent(debouncedSearch.value)}`,
    )
    rows.value = result.data
    total.value = result.pagination.total
    totalPages.value = Math.max(1, Math.ceil(filteredRows.value.length / 10))
  } finally {
    loading.value = false
  }
}

const activeOfficers = computed(() => master.officers.filter((o) => o.active))

const statusFilterOptions = [
  { value: 'all', label: 'Semua Status Stok' },
  { value: 'safe', label: 'Aman', badge: 'Tersedia' },
  { value: 'low', label: 'Menipis', badge: 'Perhatian' },
  { value: 'out', label: 'Habis', badge: 'Kosong' },
]

const officerOptions = computed(() =>
  activeOfficers.value.map((off) => ({ value: off.name, label: off.name, sublabel: off.role_label })),
)

const variantOptions = computed(() =>
  master.variants.map((v) => ({
    value: v.variant_id,
    label: variantLabel(v),
    sublabel: `Kode ${v.code} · Tersedia ${formatNumber(v.total_available)} ${v.unit}`,
    icon: v.photo_key ? attachmentUrl(v.photo_key) : itemFlaticonIcon(v.name),
  })),
)

const conditionOptions = [
  { value: 'new', label: 'Baru', badge: 'Segel / Siap Pakai' },
  { value: 'used_good', label: 'Bekas Layak', badge: 'Siap Pakai' },
  { value: 'quarantine', label: 'Karantina', badge: 'Periksa / Rawat' },
  { value: 'damaged', label: 'Rusak', badge: 'Afval' },
]

const transferFromOptions = computed(() => [
  { value: 'used_good', label: 'Bekas Layak', badge: `${formatNumber(transferRow.value?.stock_used_good || 0)} ${transferRow.value?.unit || ''}` },
  { value: 'quarantine', label: 'Karantina', badge: `${formatNumber(transferRow.value?.stock_quarantine || 0)} ${transferRow.value?.unit || ''}` },
  { value: 'new', label: 'Baru', badge: `${formatNumber(transferRow.value?.stock_new || 0)} ${transferRow.value?.unit || ''}` },
  { value: 'damaged', label: 'Rusak', badge: `${formatNumber(transferRow.value?.stock_damaged || 0)} ${transferRow.value?.unit || ''}` },
])

const transferToOptions = [
  { value: 'quarantine', label: 'Karantina', sublabel: 'Butuh inspeksi / pembersihan' },
  { value: 'used_good', label: 'Bekas Layak (Siap Pakai)', sublabel: 'Masuk stok tersedia kembali' },
  { value: 'damaged', label: 'Rusak (Afval)', sublabel: 'Tidak layak pakai' },
  { value: 'new', label: 'Baru', sublabel: 'Kembalikan ke kondisi baru' },
]

const totalAvailableUnits = computed(() =>
  rows.value.reduce((s, r) => s + Number(r.total_available || 0), 0),
)
const totalQuarantineDamaged = computed(() =>
  rows.value.reduce((s, r) => s + Number(r.stock_quarantine || 0) + Number(r.stock_damaged || 0), 0),
)

function stockFillPercent(row: StockRow) {
  const cap = Math.max(10, Number(row.minimum_stock || 0) * 2.5, Number(row.total_available || 0))
  return Math.min(100, Math.round((Number(row.total_available || 0) / cap) * 100))
}

async function openOpeningStockModal() {
  editingOpeningId.value = null
  openingForm.recordedAt = new Date().toISOString().slice(0, 10)
  openingForm.notes = 'Saldo stok awal yang sudah ada sebelumnya'
  showOpeningModal.value = true

  try {
    const [, hist] = await Promise.all([
      master.refresh(),
      api<{ data: typeof openingHistory.value }>('/api/inventory/opening-stocks'),
    ])
    openingHistory.value = hist.data
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data master')
  }

  openingForm.officerName = activeOfficers.value[0]?.name || 'Admin Gudang'
  openingForm.items = [
    { variantId: master.variants[0]?.variant_id || '', condition: 'new', quantity: 1, notes: '' },
  ]
}

function loadOpeningForEdit(rec: typeof openingHistory.value[number]) {
  editingOpeningId.value = rec.id
  openingForm.recordedAt = rec.recorded_at.slice(0, 10)
  openingForm.officerName = rec.officer_name
  openingForm.notes = rec.notes || ''
  openingForm.items = rec.opening_stock_items.map((it) => ({
    variantId: it.variant_id,
    condition: it.condition,
    quantity: Number(it.quantity),
    notes: it.notes || '',
  }))
}

function addOpeningLine() {
  openingForm.items.push({ variantId: master.variants[0]?.variant_id || '', condition: 'new', quantity: 1, notes: '' })
}

async function submitOpeningStock() {
  const valid = openingForm.items.filter((i) => i.variantId && Number(i.quantity) > 0)
  if (!valid.length) {
    toast.error('Minimal 1 baris barang dengan jumlah > 0')
    return
  }
  savingOpening.value = true
  try {
    const endpoint = editingOpeningId.value ? `/api/inventory/opening-stock/${editingOpeningId.value}` : '/api/inventory/opening-stock'
    const method = editingOpeningId.value ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      headers: editingOpeningId.value ? {} : { 'X-Idempotency-Key': generateUuid() },
      body: JSON.stringify({
        recordedAt: openingForm.recordedAt,
        officerName: openingForm.officerName,
        notes: openingForm.notes || null,
        items: valid.map((i) => ({ ...i, quantity: Number(i.quantity), notes: i.notes || null })),
      }),
    })
    toast.success(editingOpeningId.value ? 'Stok awal berhasil diperbarui!' : 'Stok awal berhasil dimasukkan ke saldo inventaris!')
    showOpeningModal.value = false
    await Promise.all([load(), master.refresh(true)])
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan stok awal')
  } finally {
    savingOpening.value = false
  }
}

async function openHistory(row: StockRow) {
  historyRow.value = row
  showHistoryModal.value = true
  loadingHistory.value = true
  try {
    const res = await api<{ data: MovementRow[] }>(`/api/inventory/movements/${row.variant_id}`)
    movements.value = res.data
  } finally {
    loadingHistory.value = false
  }
}

const transferSourceMax = computed(() => {
  const r = transferRow.value
  if (!r) return 0
  if (transferForm.fromCondition === 'new') return Number(r.stock_new || 0)
  if (transferForm.fromCondition === 'used_good') return Number(r.stock_used_good || 0)
  if (transferForm.fromCondition === 'quarantine') return Number(r.stock_quarantine || 0)
  return Number(r.stock_damaged || 0)
})

function openTransferModal(row: StockRow) {
  transferRow.value = row
  if (row.stock_quarantine > 0) {
    transferForm.fromCondition = 'quarantine'
    transferForm.toCondition = 'used_good'
    transferForm.quantity = row.stock_quarantine
    transferForm.notes = 'Selesai pemeriksaan karantina -> siap pakai'
  } else if (row.stock_used_good > 0) {
    transferForm.fromCondition = 'used_good'
    transferForm.toCondition = 'quarantine'
    transferForm.quantity = 1
    transferForm.notes = 'Dipindahkan ke karantina untuk pemeriksaan / pembersihan'
  } else if (row.stock_new > 0) {
    transferForm.fromCondition = 'new'
    transferForm.toCondition = 'quarantine'
    transferForm.quantity = 1
    transferForm.notes = 'Pemeriksaan kualitas / karantina barang baru'
  } else {
    transferForm.fromCondition = 'damaged'
    transferForm.toCondition = 'used_good'
    transferForm.quantity = 1
    transferForm.notes = 'Perbaikan barang rusak -> bekas layak'
  }
  showTransferModal.value = true
}

function onTransferFromChange() {
  if (transferForm.fromCondition === transferForm.toCondition) {
    transferForm.toCondition = transferForm.fromCondition === 'quarantine' ? 'used_good' : 'quarantine'
  }
  if (transferForm.quantity > transferSourceMax.value && transferSourceMax.value > 0) {
    transferForm.quantity = transferSourceMax.value
  }
}

async function submitTransfer() {
  if (!transferRow.value) return
  if (transferForm.fromCondition === transferForm.toCondition) {
    toast.error('Kondisi asal dan tujuan tidak boleh sama')
    return
  }
  if (transferForm.quantity > transferSourceMax.value) {
    toast.error(`Stok kondisi asal hanya tersisa ${formatNumber(transferSourceMax.value)} ${transferRow.value.unit}`)
    return
  }
  savingTransfer.value = true
  try {
    await api('/api/inventory/condition-transfer', {
      method: 'POST',
      body: JSON.stringify({
        variantId: transferRow.value.variant_id,
        fromCondition: transferForm.fromCondition,
        toCondition: transferForm.toCondition,
        quantity: Number(transferForm.quantity),
        notes: transferForm.notes || null,
      }),
    })
    toast.success('Kondisi stok berhasil dipindahkan')
    showTransferModal.value = false
    await Promise.all([load(), master.refresh(true)])
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memindahkan kondisi stok')
  } finally {
    savingTransfer.value = false
  }
}

function movementLabel(type: string) {
  const map: Record<string, string> = {
    opening_stock: 'Stok Awal',
    receipt: 'Barang Masuk',
    issuance: 'Barang Keluar',
    return: 'Pengembalian APD',
    stocktake_adjustment: 'Penyesuaian Opname',
    condition_transfer: 'Pindah Kondisi',
  }
  return map[type] || type
}

function printInventory() {
  window.print()
}

function exportCsv() {
  downloadCsv(
    `stok-inventaris-${new Date().toISOString().slice(0, 10)}.csv`,
    ['Kode', 'Nama', 'Ukuran', 'Satuan', 'Baru', 'Bekas Layak', 'Karantina', 'Rusak', 'Tersedia', 'Minimum', 'Status'],
    filteredRows.value.map((row) => [
      row.code, row.name, row.size, row.unit,
      row.stock_new, row.stock_used_good, row.stock_quarantine, row.stock_damaged,
      row.total_available, row.minimum_stock, row.stock_status,
    ]),
  )
}

watch(search, (value) => {
  window.clearTimeout(timer)
  timer = window.setTimeout(() => { debouncedSearch.value = value; page.value = 1 }, 300)
})
watch(status, () => { page.value = 1 })
watch(debouncedSearch, load)

onMounted(async () => {
  await Promise.all([load(), master.refresh()])
  if (route.query.action === 'opening-stock') openOpeningStockModal()
})
</script>

<template>
  <div>
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
        <h1>LAPORAN SALDO STOK INVENTARIS APD</h1>
        <small>Total {{ total }} varian terdaftar</small>
      </div>
    </header>

    <section class="page-intro screen-only-intro">
      <div>
        <p class="eyebrow">Saldo terkini</p>
        <h2>Stok Inventaris</h2>
        <p>Kelola saldo stok awal, pantau stok baru, bekas layak, karantina, rusak, pindah kondisi, dan riwayat mutasi lengkap.</p>
      </div>
      <div class="intro-actions">
        <button class="secondary-button" @click="printInventory"><Printer :size="16" /> Cetak PDF</button>
        <button class="secondary-button" @click="exportCsv"><Download :size="16" /> Ekspor CSV</button>
        <button class="secondary-button highlight" @click="openOpeningStockModal"><ClipboardList :size="16" /> Input Stok Awal</button>
        <button class="primary-button" @click="showItemModal = true"><Plus :size="17" /> Tambah Barang</button>
      </div>
    </section>

    <section class="inv-stats-grid">
      <article class="inv-stat-card teal modern-hover-card">
        <div class="inv-stat-icon"><img :src="flaticonAssets.warehouse" alt="Item APD" /></div>
        <div>
          <span>Total Item APD</span>
          <strong>{{ total }}</strong>
          <small>Terdaftar di gudang</small>
        </div>
      </article>
      <article class="inv-stat-card blue modern-hover-card">
        <div class="inv-stat-icon"><img :src="flaticonAssets.inventory" alt="Unit Tersedia" /></div>
        <div>
          <span>Siap Pakai</span>
          <strong>{{ formatNumber(totalAvailableUnits) }}</strong>
          <small>Baru + Bekas Layak</small>
        </div>
      </article>
      <article class="inv-stat-card amber modern-hover-card">
        <div class="inv-stat-icon"><img :src="flaticonAssets.warning" alt="Menipis / Habis" /></div>
        <div>
          <span>Menipis / Habis</span>
          <strong>{{ rows.filter(r => r.stock_status !== 'safe').length }}</strong>
          <small>{{ rows.filter(r => r.stock_status === 'out').length }} kosong · {{ rows.filter(r => r.stock_status === 'low').length }} menipis</small>
        </div>
      </article>
      <article class="inv-stat-card violet modern-hover-card">
        <div class="inv-stat-icon"><img :src="flaticonAssets.quarantine" alt="Karantina & Rusak" /></div>
        <div>
          <span>Karantina &amp; Rusak</span>
          <strong>{{ formatNumber(totalQuarantineDamaged) }}</strong>
          <small>Perlu inspeksi / afval</small>
        </div>
      </article>
    </section>

    <section class="panel data-panel">
      <div class="table-toolbar">
        <label class="search-field"><Search :size="17" /><input v-model="search" placeholder="Cari kode atau nama barang APD..." /></label>
        <ModernSelect v-model="status" :options="statusFilterOptions" compact :searchable="false" />
      </div>

      <div class="table-wrap inventory-table">
        <table>
          <thead>
            <tr>
              <th>Barang</th><th>Ukuran</th><th>Baru</th><th>Bekas layak</th>
              <th>Karantina</th><th>Rusak</th><th>Total tersedia &amp; Level</th><th>Status</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, rowIdx) in pagedRows" :key="row.variant_id" class="inv-row-animated" :style="{ animationDelay: `${rowIdx * 35}ms` }">
              <td>
                <span class="item-cell">
                  <img v-if="row.photo_key" :src="attachmentUrl(row.photo_key)" class="item-thumb" alt="Foto barang" />
                  <span v-else class="item-flaticon-box">
                    <img :src="itemFlaticonIcon(row.name)" :alt="row.name" loading="lazy" />
                  </span>
                  <span><strong>{{ row.name }}</strong><small>{{ row.code }}</small></span>
                </span>
              </td>
              <td><span class="tag-pill">{{ row.size && row.size !== '-' ? row.size : 'Standar' }}</span></td>
              <td>{{ formatNumber(row.stock_new) }} <small>{{ row.unit }}</small></td>
              <td>{{ formatNumber(row.stock_used_good) }} <small>{{ row.unit }}</small></td>
              <td>
                <span :class="{ 'pulse-amber': row.stock_quarantine > 0 }">{{ formatNumber(row.stock_quarantine) }} <small>{{ row.unit }}</small></span>
              </td>
              <td>{{ formatNumber(row.stock_damaged) }} <small>{{ row.unit }}</small></td>
              <td>
                <div class="stock-level-cell">
                  <div class="stock-level-top">
                    <strong>{{ formatNumber(row.total_available) }} {{ row.unit }}</strong>
                    <small v-if="row.minimum_stock > 0">Min {{ formatNumber(row.minimum_stock) }}</small>
                  </div>
                  <div class="stock-meter-track">
                    <div class="stock-meter-fill" :class="row.stock_status" :style="{ width: `${stockFillPercent(row)}%` }" />
                  </div>
                </div>
              </td>
              <td><span class="status-pill" :class="row.stock_status">{{ row.stock_status === 'safe' ? 'Aman' : row.stock_status === 'low' ? 'Menipis' : 'Habis' }}</span></td>
              <td>
                <div class="row-actions">
                  <button
                    v-if="row.stock_new + row.stock_used_good + row.stock_quarantine + row.stock_damaged > 0"
                    class="secondary-button xs"
                    title="Pindahkan stok antar kondisi (Baru / Bekas Layak / Karantina / Rusak)"
                    @click="openTransferModal(row)"
                  >
                    <ArrowRightLeft :size="13" /> Pindah Kondisi
                  </button>
                  <button class="icon-button" title="Riwayat mutasi" @click="openHistory(row)"><History :size="16" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="9"><div class="empty-state"><PackageOpen :size="32" /><strong>Belum ada stok yang cocok</strong><span>Tambahkan master barang atau input stok awal.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="9"><div class="loading-row">Memuat saldo inventaris...</div></td></tr>
          </tbody>
        </table>
      </div>

      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <ItemFormModal :open="showItemModal" @close="showItemModal = false" @saved="load" />

    <!-- Modal Input / Edit Stok Awal -->
    <BaseModal
      :open="showOpeningModal"
      :title="editingOpeningId ? 'Edit Catatan Stok Awal' : 'Input Stok Awal (Stok Sebelumnya)'"
      eyebrow="Saldo Awal Gudang"
      subtitle="Masukkan atau revisi stok APD fisik yang sudah tersedia di gudang."
      size="lg"
      @close="showOpeningModal = false"
    >
      <form id="opening-stock-form" class="modal-form" @submit.prevent="submitOpeningStock">
        <div v-if="openingHistory.length" class="lookup-box">
          <div class="lookup-header">
            <strong>Riwayat Stok Awal Tercatat (klik untuk edit)</strong>
          </div>
          <div class="tag-group">
            <button
              v-for="rec in openingHistory"
              :key="rec.id"
              type="button"
              class="secondary-button xs"
              :class="{ highlight: editingOpeningId === rec.id }"
              @click="loadOpeningForEdit(rec)"
            >
              {{ rec.transaction_no }} ({{ formatDate(rec.recorded_at) }} · {{ rec.opening_stock_items.length }} item)
            </button>
            <button v-if="editingOpeningId" type="button" class="secondary-button xs" @click="openOpeningStockModal">
              + Buat Baru
            </button>
          </div>
        </div>
        <div class="form-grid-2">
          <label class="field"><span>Tanggal Pencatatan *</span><input v-model="openingForm.recordedAt" type="date" required /></label>
          <label class="field"><span>Petugas Pencatat *</span>
            <ModernSelect v-if="activeOfficers.length" v-model="openingForm.officerName" :options="officerOptions" required />
            <input v-else v-model="openingForm.officerName" required />
          </label>
        </div>
        <label class="field"><span>Catatan</span><input v-model="openingForm.notes" placeholder="Contoh: Saldo awal gudang per November 2026" /></label>

        <div class="lines-section">
          <div class="lines-header">
            <strong>Daftar Item Stok Awal</strong>
            <button type="button" class="secondary-button sm" @click="addOpeningLine"><Plus :size="14" /> Tambah Baris</button>
          </div>
          <div class="modal-lines-list">
            <div v-for="(line, idx) in openingForm.items" :key="idx" class="modal-line-card">
              <div class="line-top">
                <ModernSelect v-model="line.variantId" :options="variantOptions" required search-placeholder="Cari barang APD..." style="flex:1;" />
                <button v-if="openingForm.items.length > 1" type="button" class="icon-button danger" @click="openingForm.items.splice(idx, 1)">
                  <Trash2 :size="15" />
                </button>
              </div>
              <div class="form-grid-3">
                <label class="field">
                  <span>Kondisi Stok</span>
                  <ModernSelect v-model="line.condition" :options="conditionOptions" :searchable="false" />
                </label>
                <label class="field"><span>Jumlah Stok Awal *</span><input v-model.number="line.quantity" type="number" min="0.01" step="any" required /></label>
                <label class="field"><span>Catatan Baris</span><input v-model="line.notes" placeholder="Rak A1, dll." /></label>
              </div>
            </div>
          </div>
        </div>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showOpeningModal = false">Batal</button>
        <button type="submit" form="opening-stock-form" class="primary-button" :disabled="savingOpening">
          {{ savingOpening ? 'Menyimpan...' : 'Simpan Stok Awal' }}
        </button>
      </template>
    </BaseModal>

    <!-- Modal Riwayat Mutasi -->
    <BaseModal
      :open="showHistoryModal"
      :title="`Riwayat Mutasi — ${historyRow ? variantLabel(historyRow) : ''}`"
      eyebrow="Kartu Stok"
      size="lg"
      @close="showHistoryModal = false"
    >
      <div v-if="loadingHistory" class="loading-row">Memuat riwayat mutasi...</div>
      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>Tanggal</th><th>Jenis Mutasi</th><th>Kondisi</th><th>Perubahan</th><th>Saldo Akhir</th><th>Keterangan</th></tr></thead>
          <tbody>
            <tr v-for="m in movements" :key="m.id">
              <td>{{ formatDate(m.occurred_at) }}</td>
              <td><strong>{{ movementLabel(m.movement_type) }}</strong></td>
              <td>{{ conditionLabel(m.condition) }}</td>
              <td><span class="delta-pill" :class="m.quantity_delta >= 0 ? 'plus' : 'minus'">{{ m.quantity_delta >= 0 ? '+' : '' }}{{ formatNumber(m.quantity_delta) }}</span></td>
              <td><strong>{{ formatNumber(m.balance_after) }}</strong></td>
              <td>{{ m.notes || '-' }}</td>
            </tr>
            <tr v-if="!movements.length"><td colspan="6"><div class="empty-state compact">Belum ada riwayat mutasi untuk varian ini.</div></td></tr>
          </tbody>
        </table>
      </div>
    </BaseModal>

    <!-- Modal Tindak Lanjut Karantina / Pindah Kondisi -->
    <BaseModal
      :open="showTransferModal"
      :title="`Pindah Kondisi Stok — ${transferRow ? variantLabel(transferRow) : ''}`"
      eyebrow="Karantina & Perubahan Status Barang"
      subtitle="Pindahkan jumlah stok antar kondisi (misal: Bekas Layak → Karantina, atau Karantina → Siap Pakai / Rusak)."
      size="sm"
      @close="showTransferModal = false"
    >
      <form id="transfer-form" class="modal-form" @submit.prevent="submitTransfer">
        <div class="form-grid-2">
          <label class="field">
            <span>Dari Kondisi</span>
            <ModernSelect v-model="transferForm.fromCondition" :options="transferFromOptions" :searchable="false" @change="onTransferFromChange" />
          </label>
          <label class="field">
            <span>Pindahkan Ke</span>
            <ModernSelect v-model="transferForm.toCondition" :options="transferToOptions" :searchable="false" />
          </label>
        </div>
        <label class="field">
          <span>Jumlah Dipindahkan {{ transferRow ? `(Maks ${formatNumber(transferSourceMax)} ${transferRow.unit})` : '*' }}</span>
          <input v-model.number="transferForm.quantity" type="number" min="0.01" :max="transferSourceMax || undefined" step="any" required />
        </label>
        <label class="field"><span>Catatan Pemeriksaan / Alasan</span><input v-model="transferForm.notes" placeholder="Misal: Perlu dicuci / disortir terlebih dahulu" /></label>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showTransferModal = false">Batal</button>
        <button type="submit" form="transfer-form" class="primary-button" :disabled="savingTransfer || transferSourceMax <= 0 || transferForm.fromCondition === transferForm.toCondition">
          {{ savingTransfer ? 'Menyimpan...' : 'Simpan Perubahan Kondisi' }}
        </button>
      </template>
    </BaseModal>
  </div>
</template>
