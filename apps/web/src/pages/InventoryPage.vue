<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowRightLeft, ClipboardList, Download, Edit3, Eye,
  History, PackageOpen, Plus, Printer, RotateCcw, Search, Trash2,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, attachmentUrl, conditionLabel, downloadCsv, formatDate, formatNumber, generateUuid, getApiCacheVersion, variantLabel } from '@/lib/api'
import { flaticonAssets, itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore, type ItemMaster } from '@/stores/master'

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
const router = useRouter()
const master = useMasterStore()
const toast = useToast()

const rows = ref<StockRow[]>([])
const stocktakes = ref<Array<{
  id: string; stocktake_no: string; reference_at: string; officer_name: string; status: string;
  stocktake_items: Array<{
    id: string; condition: string; system_quantity: number; physical_quantity: number; reason: string | null;
    item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null
  }>
}>>([])
const activeInvTab = ref<'stock' | 'so'>('stock')
const loadingSo = ref(false)
const search = ref('')
const debouncedSearch = ref('')
const status = ref('all')
const unitFilter = ref('all')
const returnTypeFilter = ref('all')
const itemFilter = ref('all')
const soSearch = ref('')
const soOfficerFilter = ref('all')
const soVarianceFilter = ref<'all' | 'surplus' | 'minus' | 'matched'>('all')
const page = ref(1)
const totalPages = ref(1)
const total = ref(0)
const loading = ref(true)
let timer: number | undefined

const showItemModal = ref(false)
const editingItem = ref<ItemMaster | null>(null)

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

// Preview Modal
const showPreviewModal = ref(false)
const previewRow = ref<StockRow | null>(null)
const showSoPreviewModal = ref(false)
const previewSoItem = ref<(typeof flatSoItems.value)[number] | null>(null)

function openPreview(row: StockRow) {
  previewRow.value = row
  showPreviewModal.value = true
}

function openSoPreview(item: (typeof flatSoItems.value)[number]) {
  previewSoItem.value = item
  showSoPreviewModal.value = true
}

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

const unitFilterOptions = computed(() => {
  const units = new Set<string>()
  for (const r of rows.value) if (r.unit) units.add(r.unit)
  return [
    { value: 'all', label: 'Semua Satuan' },
    ...[...units].sort((a, b) => a.localeCompare(b)).map((u) => ({ value: u, label: `Satuan: ${u}` })),
  ]
})

const returnTypeFilterOptions = [
  { value: 'all', label: 'Semua Tipe APD' },
  { value: 'return_required', label: 'Wajib Kembali' },
  { value: 'consumable', label: 'Habis Pakai' },
]

const itemNameFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) if (r.name) names.add(r.name)
  return [
    { value: 'all', label: 'Semua Nama Barang' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const soOfficerFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const st of stocktakes.value) if (st.officer_name) names.add(st.officer_name)
  return [
    { value: 'all', label: 'Semua Petugas SO' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const soVarianceFilterOptions = [
  { value: 'all', label: 'Semua Selisih' },
  { value: 'surplus', label: 'Surplus (+)' },
  { value: 'minus', label: 'Kurang / Hilang (-)' },
  { value: 'matched', label: 'Sesuai (0)' },
]

const hasStockFilters = computed(() =>
  Boolean(search.value.trim() || status.value !== 'all' || unitFilter.value !== 'all' || returnTypeFilter.value !== 'all' || itemFilter.value !== 'all'),
)

function resetStockFilters() {
  search.value = ''
  debouncedSearch.value = ''
  status.value = 'all'
  unitFilter.value = 'all'
  returnTypeFilter.value = 'all'
  itemFilter.value = 'all'
}

const filteredRows = computed(() => {
  return rows.value.filter((row) => {
    if (status.value === 'attention' && !(row.stock_status === 'low' || row.stock_status === 'out')) return false
    else if (status.value === 'quarantine_damaged' && !(Number(row.stock_quarantine || 0) > 0 || Number(row.stock_damaged || 0) > 0)) return false
    else if (status.value !== 'all' && status.value !== 'attention' && status.value !== 'quarantine_damaged' && row.stock_status !== status.value) return false
    if (unitFilter.value !== 'all' && row.unit !== unitFilter.value) return false
    if (itemFilter.value !== 'all' && row.name !== itemFilter.value) return false
    if (returnTypeFilter.value !== 'all') {
      const itemMaster = master.items.find((i) => i.id === row.item_id)
      const isReturnReq = itemMaster ? itemMaster.return_required : true
      if (returnTypeFilter.value === 'return_required' && !isReturnReq) return false
      if (returnTypeFilter.value === 'consumable' && isReturnReq) return false
    }
    return true
  })
})

const flatSoItems = computed(() =>
  stocktakes.value.flatMap((st) =>
    (st.stocktake_items ?? []).map((it) => {
      const diff = Number(it.physical_quantity) - Number(it.system_quantity)
      return {
        key: `${st.id}-${it.id}`,
        stocktakeId: st.id,
        stocktakeNo: st.stocktake_no,
        referenceAt: st.reference_at,
        officerName: st.officer_name,
        status: st.status,
        itemName: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }),
        unit: it.item_variants?.items?.unit || 'unit',
        condition: it.condition,
        systemQty: Number(it.system_quantity),
        physicalQty: Number(it.physical_quantity),
        diff,
        reason: it.reason || '-',
      }
    }),
  ),
)

const filteredSoItems = computed(() => {
  const q = soSearch.value.trim().toLowerCase()
  return flatSoItems.value.filter((it) => {
    if (soOfficerFilter.value !== 'all' && it.officerName !== soOfficerFilter.value) return false
    if (soVarianceFilter.value === 'surplus' && it.diff <= 0) return false
    if (soVarianceFilter.value === 'minus' && it.diff >= 0) return false
    if (soVarianceFilter.value === 'matched' && it.diff !== 0) return false
    if (!q) return true
    return it.stocktakeNo.toLowerCase().includes(q) || it.officerName.toLowerCase().includes(q) || it.itemName.toLowerCase().includes(q) || it.reason.toLowerCase().includes(q)
  })
})

const soSurplusTotal = computed(() => flatSoItems.value.filter((x) => x.diff > 0).reduce((s, x) => s + x.diff, 0))
const soMinusTotal = computed(() => flatSoItems.value.filter((x) => x.diff < 0).reduce((s, x) => s + Math.abs(x.diff), 0))

async function loadStocktakes() {
  loadingSo.value = true
  try {
    const res = await api<{ data: typeof stocktakes.value }>('/api/transactions/stocktakes')
    stocktakes.value = res.data
  } catch {
    // non-fatal
  } finally {
    loadingSo.value = false
  }
}

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

function openStatHistory(kind: 'all' | 'safe' | 'attention' | 'quarantine_damaged') {
  statModalOpen.value = true
  if (kind === 'all') {
    statModalTitle.value = 'Daftar Seluruh Item APD'
    statModalSubtitle.value = `Total ${rows.value.length} varian terdaftar dalam sistem`
    statModalEmpty.value = 'Belum ada item APD terdaftar.'
    statModalColumns.value = [
      { key: 'item', label: 'Barang APD' },
      { key: 'category', label: 'Kategori' },
      { key: 'available', label: 'Tersedia (Baru+Layak)' },
      { key: 'nonAvail', label: 'Karantina / Rusak' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = rows.value.map((r) => ({
      item: { text: variantLabel(r), sub: r.code, strong: true },
      category: r.category_name,
      available: { text: `${formatNumber(r.total_available)} ${r.unit}`, sub: `Baru ${formatNumber(r.stock_new)} · Layak ${formatNumber(r.stock_used_good)}`, strong: true },
      nonAvail: `${formatNumber(r.stock_quarantine)} / ${formatNumber(r.stock_damaged)} ${r.unit}`,
      status: { text: r.stock_status === 'safe' ? 'Aman' : r.stock_status === 'low' ? 'Menipis' : 'Habis', pill: r.stock_status },
    }))
  } else if (kind === 'safe') {
    const list = rows.value.filter((r) => Number(r.total_available) > 0)
    statModalTitle.value = 'Rincian Stok Siap Pakai (Tersedia)'
    statModalSubtitle.value = `Hanya menghitung Baru + Bekas Layak (${formatNumber(totalAvailableUnits.value)} unit) — tidak termasuk Karantina & Rusak`
    statModalEmpty.value = 'Belum ada stok tersedia.'
    statModalColumns.value = [
      { key: 'item', label: 'Barang APD' },
      { key: 'newQty', label: 'Baru' },
      { key: 'usedQty', label: 'Bekas Layak' },
      { key: 'total', label: 'Total Tersedia' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = list.map((r) => ({
      item: { text: variantLabel(r), sub: r.code, strong: true },
      newQty: `${formatNumber(r.stock_new)} ${r.unit}`,
      usedQty: `${formatNumber(r.stock_used_good)} ${r.unit}`,
      total: { text: `${formatNumber(r.total_available)} ${r.unit}`, strong: true },
      status: { text: r.stock_status === 'safe' ? 'Aman' : 'Menipis', pill: r.stock_status },
    }))
  } else if (kind === 'attention') {
    const list = rows.value.filter((r) => r.stock_status === 'low' || r.stock_status === 'out')
    statModalTitle.value = 'Daftar Item Menipis & Habis'
    statModalSubtitle.value = 'Item dengan saldo tersedia <= batas minimum stok'
    statModalEmpty.value = 'Semua stok berada dalam batas aman.'
    statModalColumns.value = [
      { key: 'item', label: 'Barang APD' },
      { key: 'available', label: 'Tersedia' },
      { key: 'min', label: 'Batas Minimum' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = list.map((r) => ({
      item: { text: variantLabel(r), sub: r.code, strong: true },
      available: { text: `${formatNumber(r.total_available)} ${r.unit}`, strong: true },
      min: `${formatNumber(r.minimum_stock)} ${r.unit}`,
      status: { text: r.stock_status === 'out' ? 'Habis' : 'Menipis', pill: r.stock_status },
    }))
  } else {
    const list = rows.value.filter((r) => Number(r.stock_quarantine) > 0 || Number(r.stock_damaged) > 0)
    statModalTitle.value = 'Riwayat & Daftar Stok Karantina & Rusak'
    statModalSubtitle.value = 'Stok ini dipisahkan dan tidak dihitung dalam saldo tersedia'
    statModalEmpty.value = 'Tidak ada barang di karantina atau rusak.'
    statModalColumns.value = [
      { key: 'item', label: 'Barang APD' },
      { key: 'quarantine', label: 'Karantina' },
      { key: 'damaged', label: 'Rusak (Afval)' },
      { key: 'total', label: 'Total Non-Tersedia' },
    ]
    statModalRows.value = list.map((r) => ({
      item: { text: variantLabel(r), sub: r.code, strong: true },
      quarantine: { text: `${formatNumber(r.stock_quarantine)} ${r.unit}`, pill: Number(r.stock_quarantine) > 0 ? 'amber' : 'neutral' },
      damaged: { text: `${formatNumber(r.stock_damaged)} ${r.unit}`, pill: Number(r.stock_damaged) > 0 ? 'out' : 'neutral' },
      total: { text: `${formatNumber(Number(r.stock_quarantine) + Number(r.stock_damaged))} ${r.unit}`, strong: true },
    }))
  }
}

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
  { value: 'safe', label: 'Aman (Siap Pakai)', badge: 'Tersedia' },
  { value: 'attention', label: 'Menipis & Habis', badge: 'Perhatian' },
  { value: 'low', label: 'Menipis Saja', badge: 'Low' },
  { value: 'out', label: 'Habis Saja', badge: 'Kosong' },
  { value: 'quarantine_damaged', label: 'Ada Karantina / Rusak', badge: 'Non-Tersedia' },
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

function openAddItem() {
  editingItem.value = null
  showItemModal.value = true
}

function openEditItem(row: StockRow) {
  const found = master.items.find((i) => i.id === row.item_id) || null
  editingItem.value = found
  showItemModal.value = true
}

async function deleteInventoryItem(row: StockRow) {
  if (!window.confirm(`Hapus master barang "${row.name}" (${row.code}) secara permanen?`)) return
  try {
    await api(`/api/master/items/${row.item_id}`, { method: 'DELETE' })
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Barang "${row.name}" berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus barang (mungkin masih memiliki transaksi terkait)')
  }
}

async function deleteSoFromInventory(item: (typeof flatSoItems.value)[number]) {
  if (!window.confirm(`Hapus sesi stok opname "${item.stocktakeNo}"? Penyesuaian stok dari sesi ini akan dibalikkan.`)) return
  try {
    await api(`/api/transactions/stocktakes/${item.stocktakeId}`, { method: 'DELETE' })
    showSoPreviewModal.value = false
    await Promise.all([load(), loadStocktakes(), master.refresh(true)])
    toast.success(`Stok opname ${item.stocktakeNo} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus stok opname')
  }
}

async function deleteOpeningStock(id: string, txNo: string) {
  if (!window.confirm(`Hapus catatan stok awal "${txNo}"? Stok barang terkait akan dikurangi kembali sesuai jumlah stok awal.`)) return
  try {
    await api(`/api/inventory/opening-stock/${id}`, { method: 'DELETE' })
    if (editingOpeningId.value === id) editingOpeningId.value = null
    const [, hist] = await Promise.all([
      load(),
      api<{ data: typeof openingHistory.value }>('/api/inventory/opening-stocks'),
      master.refresh(true),
    ])
    openingHistory.value = hist.data
    toast.success(`Stok awal ${txNo} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus stok awal')
  }
}

watch(search, (value) => {
  window.clearTimeout(timer)
  timer = window.setTimeout(() => { debouncedSearch.value = value; page.value = 1 }, 300)
})
watch([status, unitFilter, returnTypeFilter, itemFilter], () => { page.value = 1 })
watch(debouncedSearch, load)

let lastCacheVer = -1
function applyInventoryRouteQuery() {
  const qs = String(route.query.status || '')
  if (['safe', 'low', 'out', 'attention', 'quarantine_damaged'].includes(qs)) {
    status.value = qs
  }
  const qSearch = String(route.query.search || '').trim()
  if (qSearch) {
    search.value = qSearch
    debouncedSearch.value = qSearch
  }
  if (route.query.action === 'opening-stock') {
    void openOpeningStockModal()
  }
}

onMounted(() => {
  applyInventoryRouteQuery()
  lastCacheVer = getApiCacheVersion()
  void Promise.all([load(), master.refresh(), loadStocktakes()])
})

onActivated(() => {
  applyInventoryRouteQuery()
  if (getApiCacheVersion() !== lastCacheVer) {
    lastCacheVer = getApiCacheVersion()
    void Promise.all([load(), master.refresh(), loadStocktakes()])
  }
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
        <button class="primary-button" @click="openAddItem"><Plus :size="17" /> Tambah Barang</button>
      </div>
    </section>

    <section class="inv-stats-grid">
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('all')">
        <div class="inv-stat-icon"><img :src="flaticonAssets.warehouse" alt="Item APD" /></div>
        <div>
          <span>Total Item APD</span>
          <strong>{{ total }}</strong>
          <small>Klik lihat daftar item</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('safe')">
        <div class="inv-stat-icon"><img :src="flaticonAssets.inventory" alt="Unit Tersedia" /></div>
        <div>
          <span>Siap Pakai (Tersedia)</span>
          <strong>{{ formatNumber(totalAvailableUnits) }}</strong>
          <small>Klik rincian Baru + Bekas Layak</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('attention')">
        <div class="inv-stat-icon"><img :src="flaticonAssets.warning" alt="Menipis / Habis" /></div>
        <div>
          <span>Menipis / Habis</span>
          <strong>{{ rows.filter(r => r.stock_status !== 'safe').length }}</strong>
          <small>{{ rows.filter(r => r.stock_status === 'out').length }} kosong · {{ rows.filter(r => r.stock_status === 'low').length }} menipis</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('quarantine_damaged')">
        <div class="inv-stat-icon"><img :src="flaticonAssets.quarantine" alt="Karantina & Rusak" /></div>
        <div>
          <span>Karantina &amp; Rusak</span>
          <strong>{{ formatNumber(totalQuarantineDamaged) }}</strong>
          <small>Tidak masuk stok tersedia</small>
        </div>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: activeInvTab === 'stock' }" @click="activeInvTab = 'stock'">Saldo Stok APD ({{ filteredRows.length }})</button>
        <button :class="{ active: activeInvTab === 'so' }" @click="activeInvTab = 'so'">
          Laporan Selisih SO (+/-) ({{ flatSoItems.length }})
        </button>
      </div>

      <template v-if="activeInvTab === 'stock'">
        <div class="table-toolbar filter-toolbar-rich">
          <label class="search-field"><Search :size="17" /><input v-model="search" placeholder="Cari kode atau nama barang APD..." /></label>
          <ModernSelect v-model="status" :options="statusFilterOptions" compact searchable search-placeholder="Cari status stok..." />
          <ModernSelect v-model="itemFilter" :options="itemNameFilterOptions" compact searchable search-placeholder="Cari nama barang..." />
          <ModernSelect v-model="unitFilter" :options="unitFilterOptions" compact searchable search-placeholder="Cari satuan..." />
          <ModernSelect v-model="returnTypeFilter" :options="returnTypeFilterOptions" compact searchable search-placeholder="Cari tipe APD..." />
          <button v-if="hasStockFilters" type="button" class="secondary-button xs" @click="resetStockFilters">
            <RotateCcw :size="13" /> Reset
          </button>
        </div>

        <div class="table-wrap inventory-table">
          <table>
            <thead>
              <tr>
                <th>Barang</th><th>Ukuran</th><th>Baru</th><th>Bekas layak</th>
                <th>Karantina</th><th>Rusak</th><th>Tersedia (Baru+Layak)</th><th>Status</th><th>Aksi</th>
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
                  <button class="icon-button" title="Preview detail barang & stok" @click="openPreview(row)"><Eye :size="15" /></button>
                  <button class="icon-button" title="Riwayat mutasi" @click="openHistory(row)"><History :size="16" /></button>
                  <button class="icon-button" title="Edit barang" @click="openEditItem(row)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus barang" @click="deleteInventoryItem(row)"><Trash2 :size="15" /></button>
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
      </template>

      <template v-else>
        <div class="table-toolbar filter-toolbar-rich" style="justify-content: space-between;">
          <div class="tag-group">
            <span class="tag-pill">Sesi SO: <b>{{ stocktakes.length }}</b></span>
            <span class="delta-pill plus">Total Surplus: +{{ formatNumber(soSurplusTotal) }}</span>
            <span class="delta-pill minus">Total Kurang / Hilang: -{{ formatNumber(soMinusTotal) }}</span>
          </div>
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
            <label class="search-field" style="width:240px;"><Search :size="15" /><input v-model="soSearch" placeholder="Cari No. SO, barang, petugas..." /></label>
            <ModernSelect v-model="soOfficerFilter" :options="soOfficerFilterOptions" compact searchable search-placeholder="Cari petugas..." />
            <ModernSelect v-model="soVarianceFilter" :options="soVarianceFilterOptions" compact searchable search-placeholder="Cari selisih..." />
            <RouterLink :to="{ name: 'stocktakes' }" class="secondary-button xs">Buka Halaman Stok Opname →</RouterLink>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>No. &amp; Tanggal SO</th>
                <th>Petugas</th>
                <th>Nama Barang</th>
                <th>Kondisi</th>
                <th>Sistem</th>
                <th>Fisik</th>
                <th>Selisih (+/-)</th>
                <th>Alasan / Catatan</th>
                <th>Aksi</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in filteredSoItems" :key="item.key">
                <td><strong>{{ item.stocktakeNo }}</strong><small class="table-sub">{{ formatDate(item.referenceAt) }}</small></td>
                <td>{{ item.officerName }}</td>
                <td><strong>{{ item.itemName }}</strong></td>
                <td>{{ conditionLabel(item.condition) }}</td>
                <td>{{ formatNumber(item.systemQty) }} {{ item.unit }}</td>
                <td>{{ formatNumber(item.physicalQty) }} {{ item.unit }}</td>
                <td>
                  <span class="delta-pill" :class="item.diff > 0 ? 'plus' : item.diff < 0 ? 'minus' : 'zero'">
                    {{ item.diff > 0 ? '+' : '' }}{{ formatNumber(item.diff) }}
                  </span>
                </td>
                <td>{{ item.reason }}</td>
                <td>
                  <div class="row-actions">
                    <button class="icon-button" title="Preview detail selisih SO" @click="openSoPreview(item)"><Eye :size="15" /></button>
                    <button class="icon-button" title="Edit di halaman Stok Opname" @click="router.push({ name: 'stocktakes' })"><Edit3 :size="15" /></button>
                    <button class="icon-button danger" title="Hapus sesi stok opname" @click="deleteSoFromInventory(item)"><Trash2 :size="15" /></button>
                  </div>
                </td>
              </tr>
              <tr v-if="!loadingSo && !filteredSoItems.length">
                <td colspan="9"><div class="empty-state compact">Belum ada laporan selisih (+/-) yang cocok.</div></td>
              </tr>
              <tr v-if="loadingSo"><td colspan="9"><div class="loading-row">Memuat laporan selisih Stok Opname...</div></td></tr>
            </tbody>
          </table>
        </div>
      </template>
    </section>

    <ItemFormModal :open="showItemModal" :item="editingItem" @close="showItemModal = false" @saved="load" />

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
            <strong>Riwayat Stok Awal Tercatat (klik untuk edit / hapus)</strong>
          </div>
          <div class="tag-group">
            <span v-for="rec in openingHistory" :key="rec.id" style="display:inline-flex;align-items:center;gap:4px;">
              <button
                type="button"
                class="secondary-button xs"
                :class="{ highlight: editingOpeningId === rec.id }"
                @click="loadOpeningForEdit(rec)"
              >
                {{ rec.transaction_no }} ({{ formatDate(rec.recorded_at) }} · {{ rec.opening_stock_items.length }} item)
              </button>
              <button
                type="button"
                class="icon-button danger"
                style="width:28px;height:28px;"
                :title="`Hapus stok awal ${rec.transaction_no}`"
                @click="deleteOpeningStock(rec.id, rec.transaction_no)"
              >
                <Trash2 :size="13" />
              </button>
            </span>
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

    <!-- Modal Preview Detail Barang & Stok -->
    <BaseModal
      :open="showPreviewModal"
      :title="previewRow ? variantLabel(previewRow) : 'Detail Stok Barang'"
      eyebrow="Preview Stok Inventaris"
      :subtitle="previewRow ? `Kode ${previewRow.code} · Satuan ${previewRow.unit}` : ''"
      size="md"
      @close="showPreviewModal = false"
    >
      <div v-if="previewRow" class="detail-stack">
        <div style="display:flex;align-items:center;gap:14px;padding:12px 14px;border-radius:12px;background:#f7fbfb;border:1px solid #dcebe9;">
          <img v-if="previewRow.photo_key" :src="attachmentUrl(previewRow.photo_key)" class="item-thumb" style="width:56px;height:56px;border-radius:12px;" alt="Foto barang" />
          <span v-else class="item-flaticon-box" style="width:56px;height:56px;border-radius:12px;">
            <img :src="itemFlaticonIcon(previewRow.name)" :alt="previewRow.name" />
          </span>
          <div style="flex:1;min-width:0;">
            <strong style="font-size:15px;display:block;color:var(--text);">{{ previewRow.name }}</strong>
            <small class="table-sub">Kode: {{ previewRow.code }} · Ukuran: {{ previewRow.size && previewRow.size !== '-' ? previewRow.size : 'Standar' }}</small>
          </div>
          <span class="status-pill" :class="previewRow.stock_status">
            {{ previewRow.stock_status === 'safe' ? 'Aman' : previewRow.stock_status === 'low' ? 'Menipis' : 'Habis' }}
          </span>
        </div>

        <div class="summary-banner">
          <div><small>Stok Tersedia (Baru + Layak)</small><strong class="text-primary">{{ formatNumber(previewRow.total_available) }} {{ previewRow.unit }}</strong></div>
          <div><small>Batas Minimum</small><strong>{{ formatNumber(previewRow.minimum_stock) }} {{ previewRow.unit }}</strong></div>
          <div><small>Karantina + Rusak</small><strong>{{ formatNumber(Number(previewRow.stock_quarantine) + Number(previewRow.stock_damaged)) }} {{ previewRow.unit }}</strong></div>
        </div>

        <div class="table-wrap" style="margin-top:0;">
          <table>
            <thead><tr><th>Kondisi Stok</th><th>Jumlah</th><th>Keterangan</th></tr></thead>
            <tbody>
              <tr><td><strong>Baru</strong></td><td><strong>{{ formatNumber(previewRow.stock_new) }} {{ previewRow.unit }}</strong></td><td>Siap pakai (segel/baru)</td></tr>
              <tr><td><strong>Bekas Layak</strong></td><td><strong>{{ formatNumber(previewRow.stock_used_good) }} {{ previewRow.unit }}</strong></td><td>Siap pakai (layak pakai ulang)</td></tr>
              <tr><td><strong>Karantina</strong></td><td><strong>{{ formatNumber(previewRow.stock_quarantine) }} {{ previewRow.unit }}</strong></td><td>Menunggu inspeksi / pembersihan</td></tr>
              <tr><td><strong>Rusak</strong></td><td><strong>{{ formatNumber(previewRow.stock_damaged) }} {{ previewRow.unit }}</strong></td><td>Tidak layak pakai / afval</td></tr>
            </tbody>
          </table>
        </div>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showPreviewModal = false">Tutup</button>
        <button v-if="previewRow" type="button" class="secondary-button" @click="showPreviewModal = false; openHistory(previewRow)">
          <History :size="15" /> Riwayat Mutasi
        </button>
        <button v-if="previewRow" type="button" class="primary-button" @click="showPreviewModal = false; openEditItem(previewRow)">
          <Edit3 :size="15" /> Edit Barang
        </button>
      </template>
    </BaseModal>

    <!-- Modal Preview Baris Selisih SO -->
    <BaseModal
      :open="showSoPreviewModal"
      :title="`Detail Selisih · ${previewSoItem?.stocktakeNo || ''}`"
      eyebrow="Preview Laporan Selisih SO"
      size="sm"
      @close="showSoPreviewModal = false"
    >
      <div v-if="previewSoItem" class="table-wrap" style="margin-top:0;">
        <table>
          <tbody>
            <tr><th style="width:40%;">No. SO</th><td><strong>{{ previewSoItem.stocktakeNo }}</strong></td></tr>
            <tr><th>Tanggal SO</th><td>{{ formatDate(previewSoItem.referenceAt) }}</td></tr>
            <tr><th>Petugas</th><td>{{ previewSoItem.officerName }}</td></tr>
            <tr><th>Barang</th><td><strong>{{ previewSoItem.itemName }}</strong></td></tr>
            <tr><th>Kondisi</th><td>{{ conditionLabel(previewSoItem.condition) }}</td></tr>
            <tr><th>Stok Sistem</th><td>{{ formatNumber(previewSoItem.systemQty) }} {{ previewSoItem.unit }}</td></tr>
            <tr><th>Stok Fisik</th><td>{{ formatNumber(previewSoItem.physicalQty) }} {{ previewSoItem.unit }}</td></tr>
            <tr><th>Selisih (+/-)</th><td><span class="delta-pill" :class="previewSoItem.diff > 0 ? 'plus' : previewSoItem.diff < 0 ? 'minus' : 'zero'">{{ previewSoItem.diff > 0 ? '+' : '' }}{{ formatNumber(previewSoItem.diff) }} {{ previewSoItem.unit }}</span></td></tr>
            <tr><th>Alasan / Catatan</th><td>{{ previewSoItem.reason }}</td></tr>
          </tbody>
        </table>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showSoPreviewModal = false">Tutup</button>
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
          <thead><tr><th>Tanggal</th><th>Jenis Mutasi</th><th>Kondisi</th><th>Perubahan</th><th>Stok Akhir</th><th>Keterangan</th></tr></thead>
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
