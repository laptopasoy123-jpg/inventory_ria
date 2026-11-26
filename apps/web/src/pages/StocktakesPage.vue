<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { AlertTriangle, CalendarRange, CheckCircle2, ClipboardCheck, Download, Edit3, Eye, FileDown, Plus, RotateCcw, Search, Trash2 } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, attachmentUrl, conditionLabel, downloadCsv, formatDate, formatNumber, getApiCacheVersion, imageUrlToDataUrl, variantLabel } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface StocktakeItemRow {
  id: string; variant_id: string; condition: 'new' | 'used_good' | 'quarantine' | 'damaged';
  system_quantity: number; physical_quantity: number; adjustment_quantity: number | null; reason: string | null;
  item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null
}

interface StocktakeRow {
  id: string; stocktake_no: string; reference_at: string; officer_name: string;
  status: 'draft' | 'pending_review' | 'completed'; finalized_at: string | null;
  stocktake_items: StocktakeItemRow[]
}

const router = useRouter()
const master = useMasterStore()
const toast = useToast()

const rows = ref<StocktakeRow[]>([])
const lostLogs = ref<Array<{
  id: string; returnId: string; transaction_no: string; returned_at: string; employee_name: string;
  item_name: string; unit: string; qty: number; reason: string
}>>([])
const loading = ref(true)
const activeTab = ref<'all' | 'lost_logs'>('all')

// Comprehensive Filters
const search = ref('')
const dateFrom = ref('')
const dateTo = ref('')
const officerFilter = ref('all')
const varianceFilter = ref<'all' | 'surplus' | 'minus' | 'matched'>('all')
const soStatusFilter = ref<'all' | 'completed' | 'pending_review'>('all')

const page = ref(1)
const lostPage = ref(1)

const showCreateModal = ref(false)
const editingId = ref<string | null>(null)
const editingCompleted = ref(false)
const modalSearch = ref('')
const modalConditionTab = ref<'all' | 'new' | 'used_good' | 'quarantine' | 'damaged'>('all')
const modalOnlyNonZero = ref(false)
const detailConditionTab = ref<'all' | 'new' | 'used_good' | 'quarantine' | 'damaged'>('all')
const saving = ref(false)

interface DraftLine {
  variantId: string
  name: string
  code: string
  size: string
  unit: string
  condition: 'new' | 'used_good' | 'quarantine' | 'damaged'
  systemQuantity: number
  physicalQuantity: number
  reason: string
}

const form = reactive({
  referenceAt: new Date().toISOString().slice(0, 10),
  officerName: 'Petugas Opname',
  lines: [] as DraftLine[],
})

const showDetailModal = ref(false)
const activeStocktake = ref<StocktakeRow | null>(null)
const finalizing = ref(false)

const showLostPreviewModal = ref(false)
const activeLostLog = ref<(typeof lostLogs.value)[number] | null>(null)

function openLostPreview(log: (typeof lostLogs.value)[number]) {
  activeLostLog.value = log
  showLostPreviewModal.value = true
}

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

const officerFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) if (r.officer_name) names.add(r.officer_name)
  for (const o of master.officers) if (o.name) names.add(o.name)
  return [
    { value: 'all', label: 'Semua Petugas' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const varianceFilterOptions = [
  { value: 'all', label: 'Semua Hasil Selisih' },
  { value: 'surplus', label: 'Ada Surplus (+)', badge: '+' },
  { value: 'minus', label: 'Ada Kurang / Hilang (-)', badge: '-' },
  { value: 'matched', label: 'Sesuai (Tanpa Selisih)', badge: '0' },
]

const soStatusFilterOptions = [
  { value: 'all', label: 'Semua Status SO' },
  { value: 'completed', label: 'Selesai (Difinalisasi)', badge: 'Selesai' },
  { value: 'pending_review', label: 'Menunggu Finalisasi', badge: 'Draft' },
]

const hasActiveFilters = computed(() =>
  Boolean(search.value.trim() || dateFrom.value || dateTo.value || officerFilter.value !== 'all' || varianceFilter.value !== 'all' || soStatusFilter.value !== 'all'),
)

function resetFilters() {
  search.value = ''
  dateFrom.value = ''
  dateTo.value = ''
  officerFilter.value = 'all'
  varianceFilter.value = 'all'
  soStatusFilter.value = 'all'
}

function inDateRange(dateStr?: string | null) {
  if (!dateStr) return true
  const d = dateStr.slice(0, 10)
  if (dateFrom.value && d < dateFrom.value) return false
  if (dateTo.value && d > dateTo.value) return false
  return true
}

function openStatHistory(kind: 'sessions' | 'surplus' | 'minus') {
  statModalOpen.value = true
  if (kind === 'sessions') {
    statModalTitle.value = 'Riwayat Semua Sesi Stok Opname'
    statModalSubtitle.value = `Total ${rows.value.length} sesi rekonsiliasi stok opname`
    statModalEmpty.value = 'Belum ada sesi stok opname.'
    statModalColumns.value = [
      { key: 'doc', label: 'No. & Tanggal SO' },
      { key: 'officer', label: 'Petugas' },
      { key: 'count', label: 'Jumlah Varian' },
      { key: 'variance', label: 'Ringkasan Selisih' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = rows.value.map((st) => {
      const v = varianceSummary(st)
      return {
        doc: { text: st.stocktake_no, sub: formatDate(st.reference_at), strong: true },
        officer: st.officer_name,
        count: `${st.stocktake_items?.length || 0} varian`,
        variance: `+${formatNumber(v.plus)} / -${formatNumber(v.minus)}`,
        status: { text: st.status === 'completed' ? 'Selesai' : 'Menunggu Finalisasi', pill: st.status === 'completed' ? 'safe' : 'amber' },
      }
    })
  } else if (kind === 'surplus') {
    statModalTitle.value = 'Riwayat Selisih Surplus (+) Stok Opname'
    statModalSubtitle.value = `Total +${formatNumber(totalGlobalPlus.value)} unit surplus dari seluruh sesi SO`
    statModalEmpty.value = 'Belum ada item surplus (+) dari stok opname.'
    statModalColumns.value = [
      { key: 'doc', label: 'No. & Tanggal SO' },
      { key: 'item', label: 'Barang & Kondisi' },
      { key: 'system', label: 'Stok Sistem' },
      { key: 'physical', label: 'Stok Fisik' },
      { key: 'diff', label: 'Surplus (+)' },
      { key: 'reason', label: 'Alasan' },
    ]
    const out: Array<Record<string, HistoryCell>> = []
    for (const st of rows.value) {
      for (const it of st.stocktake_items ?? []) {
        const diff = Number(it.physical_quantity) - Number(it.system_quantity)
        if (diff <= 0) continue
        const unit = it.item_variants?.items?.unit || 'unit'
        out.push({
          doc: { text: st.stocktake_no, sub: `${formatDate(st.reference_at)} · ${st.officer_name}`, strong: true },
          item: { text: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }), sub: conditionLabel(it.condition), strong: true },
          system: `${formatNumber(it.system_quantity)} ${unit}`,
          physical: `${formatNumber(it.physical_quantity)} ${unit}`,
          diff: { text: `+${formatNumber(diff)} ${unit}`, pill: 'plus' },
          reason: it.reason || '-',
        })
      }
    }
    statModalRows.value = out
  } else {
    statModalTitle.value = 'Riwayat Selisih Kurang / Hilang (-) Stok Opname'
    statModalSubtitle.value = `Total -${formatNumber(totalGlobalMinus.value)} unit kurang/hilang dari seluruh sesi SO`
    statModalEmpty.value = 'Tidak ada item kurang / hilang (-).'
    statModalColumns.value = [
      { key: 'doc', label: 'No. & Tanggal' },
      { key: 'item', label: 'Barang & Sumber' },
      { key: 'system', label: 'Sistem' },
      { key: 'physical', label: 'Fisik' },
      { key: 'diff', label: 'Kurang / Hilang' },
      { key: 'reason', label: 'Alasan' },
    ]
    const out: Array<Record<string, HistoryCell>> = []
    for (const st of rows.value) {
      for (const it of st.stocktake_items ?? []) {
        const diff = Number(it.physical_quantity) - Number(it.system_quantity)
        if (diff >= 0) continue
        const unit = it.item_variants?.items?.unit || 'unit'
        out.push({
          doc: { text: st.stocktake_no, sub: `${formatDate(st.reference_at)} · ${st.officer_name}`, strong: true },
          item: { text: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }), sub: conditionLabel(it.condition), strong: true },
          system: `${formatNumber(it.system_quantity)} ${unit}`,
          physical: `${formatNumber(it.physical_quantity)} ${unit}`,
          diff: { text: `${formatNumber(diff)} ${unit}`, pill: 'minus' },
          reason: it.reason || '-',
        })
      }
    }
    for (const log of lostLogs.value) {
      out.push({
        doc: { text: log.transaction_no, sub: `${formatDate(log.returned_at)} · Pengembalian`, strong: true },
        item: { text: log.item_name, sub: `Karyawan: ${log.employee_name}`, strong: true },
        system: '—',
        physical: 'Hilang',
        diff: { text: `-${formatNumber(log.qty)} ${log.unit}`, pill: 'minus' },
        reason: log.reason || 'Hilang saat pengembalian APD',
      })
    }
    statModalRows.value = out
  }
}

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  return rows.value.filter((r) => {
    if (!inDateRange(r.reference_at)) return false
    if (officerFilter.value !== 'all' && r.officer_name !== officerFilter.value) return false
    if (soStatusFilter.value !== 'all' && r.status !== soStatusFilter.value) return false
    const v = varianceSummary(r)
    if (varianceFilter.value === 'surplus' && v.plus <= 0) return false
    if (varianceFilter.value === 'minus' && v.minus <= 0) return false
    if (varianceFilter.value === 'matched' && (v.plus > 0 || v.minus > 0)) return false
    if (!q) return true
    return (
      r.stocktake_no.toLowerCase().includes(q) ||
      r.officer_name.toLowerCase().includes(q) ||
      r.reference_at.slice(0, 10).includes(q) ||
      (r.stocktake_items ?? []).some(
        (it) =>
          (it.item_variants?.items?.name || '').toLowerCase().includes(q) ||
          (it.item_variants?.items?.code || '').toLowerCase().includes(q) ||
          (it.reason || '').toLowerCase().includes(q),
      )
    )
  })
})

const filteredLostLogs = computed(() => {
  const q = search.value.trim().toLowerCase()
  return lostLogs.value.filter((log) => {
    if (!inDateRange(log.returned_at)) return false
    if (!q) return true
    return (
      log.transaction_no.toLowerCase().includes(q) ||
      log.employee_name.toLowerCase().includes(q) ||
      log.item_name.toLowerCase().includes(q) ||
      log.reason.toLowerCase().includes(q)
    )
  })
})

const pagedRows = computed(() => {
  const maxPage = Math.max(1, Math.ceil(filteredRows.value.length / 10))
  const cur = Math.min(Math.max(1, page.value), maxPage)
  return filteredRows.value.slice((cur - 1) * 10, cur * 10)
})
const pagedLostLogs = computed(() => {
  const maxPage = Math.max(1, Math.ceil(filteredLostLogs.value.length / 10))
  const cur = Math.min(Math.max(1, lostPage.value), maxPage)
  return filteredLostLogs.value.slice((cur - 1) * 10, cur * 10)
})
watch([activeTab, search, dateFrom, dateTo, officerFilter, varianceFilter, soStatusFilter], () => {
  page.value = 1
  lostPage.value = 1
})

const conditionGroupsMeta: Array<{
  key: 'new' | 'used_good' | 'quarantine' | 'damaged'
  title: string
  desc: string
  tone: string
}> = [
  { key: 'new', title: 'Stok Baru', desc: 'Barang baru / segel siap pakai', tone: 'new' },
  { key: 'used_good', title: 'Stok Bekas Layak', desc: 'Barang bekas layak pakai ulang', tone: 'used_good' },
  { key: 'quarantine', title: 'Stok Karantina', desc: 'Sedang perawatan / pemeriksaan', tone: 'quarantine' },
  { key: 'damaged', title: 'Stok Rusak', desc: 'Tidak layak pakai / afval', tone: 'damaged' },
]

function conditionTone(cond: string) {
  if (cond === 'new') return 'cond-new'
  if (cond === 'used_good') return 'cond-used'
  if (cond === 'quarantine') return 'cond-quarantine'
  return 'cond-damaged'
}

const filteredDraftLines = computed(() => {
  const q = modalSearch.value.trim().toLowerCase()
  return form.lines.filter((l) => {
    if (modalConditionTab.value !== 'all' && l.condition !== modalConditionTab.value) return false
    if (modalOnlyNonZero.value && Number(l.systemQuantity) === 0 && Number(l.physicalQuantity) === 0) return false
    if (!q) return true
    return l.name.toLowerCase().includes(q) || l.code.toLowerCase().includes(q) || l.size.toLowerCase().includes(q)
  })
})

const groupedDraftSections = computed(() => {
  return conditionGroupsMeta
    .map((meta) => {
      const items = filteredDraftLines.value.filter((l) => l.condition === meta.key)
      let totalSys = 0
      let totalPhys = 0
      let plus = 0
      let minus = 0
      for (const it of items) {
        totalSys += Number(it.systemQuantity || 0)
        totalPhys += Number(it.physicalQuantity || 0)
        const d = Number(it.physicalQuantity || 0) - Number(it.systemQuantity || 0)
        if (d > 0) plus += d
        else if (d < 0) minus += Math.abs(d)
      }
      return { ...meta, items, totalSys, totalPhys, plus, minus }
    })
    .filter((sec) => sec.items.length > 0)
})

const conditionTabCounts = computed(() => {
  const counts = { all: form.lines.length, new: 0, used_good: 0, quarantine: 0, damaged: 0 }
  for (const l of form.lines) counts[l.condition] += 1
  return counts
})

const filteredDetailSections = computed(() => {
  const items = activeStocktake.value?.stocktake_items ?? []
  return conditionGroupsMeta
    .filter((meta) => detailConditionTab.value === 'all' || detailConditionTab.value === meta.key)
    .map((meta) => ({
      ...meta,
      items: items.filter((it) => it.condition === meta.key),
    }))
    .filter((sec) => sec.items.length > 0)
})

const draftSummary = computed(() => {
  let plusCount = 0
  let minusCount = 0
  let plusUnits = 0
  let minusUnits = 0
  for (const l of form.lines) {
    const diff = Number(l.physicalQuantity) - Number(l.systemQuantity)
    if (diff > 0) { plusCount++; plusUnits += diff }
    else if (diff < 0) { minusCount++; minusUnits += Math.abs(diff) }
  }
  return { plusCount, minusCount, plusUnits, minusUnits }
})

function varianceSummary(st: StocktakeRow) {
  let plus = 0
  let minus = 0
  for (const it of st.stocktake_items) {
    const diff = Number(it.physical_quantity) - Number(it.system_quantity)
    if (diff > 0) plus += diff
    if (diff < 0) minus += Math.abs(diff)
  }
  return { plus, minus }
}

const totalGlobalPlus = computed(() => rows.value.reduce((s, r) => s + varianceSummary(r).plus, 0))
const totalGlobalMinus = computed(() => rows.value.reduce((s, r) => s + varianceSummary(r).minus, 0))

async function load() {
  loading.value = true
  try {
    const [stRes, retRes] = await Promise.all([
      api<{ data: StocktakeRow[] }>('/api/transactions/stocktakes'),
      api<{
        data: Array<{
          id: string; transaction_no: string; returned_at: string;
          employees?: { name: string } | null;
          return_items: Array<{
            id: string; quantity: number; result: string; reason: string | null;
            issuance_items?: { item_variants?: { size: string; items?: { name: string; unit: string } | null } | null } | null
          }>
        }>
      }>('/api/transactions/returns?result=lost'),
    ])
    rows.value = stRes.data
    const flatLost: typeof lostLogs.value = []
    for (const r of retRes.data) {
      for (const it of r.return_items) {
        if (it.result !== 'lost') continue
        flatLost.push({
          id: `${r.id}-${it.id}`,
          returnId: r.id,
          transaction_no: r.transaction_no,
          returned_at: r.returned_at,
          employee_name: r.employees?.name || '-',
          item_name: variantLabel({ name: it.issuance_items?.item_variants?.items?.name || 'Barang', size: it.issuance_items?.item_variants?.size }),
          unit: it.issuance_items?.item_variants?.items?.unit || 'unit',
          qty: Number(it.quantity),
          reason: it.reason || 'Hilang saat pengembalian',
        })
      }
    }
    lostLogs.value = flatLost
  } finally {
    loading.value = false
  }
}

const activeOfficers = computed(() => master.officers.filter((o) => o.active))

const officerOptions = computed(() =>
  activeOfficers.value.map((off) => ({ value: off.name, label: off.name, sublabel: off.role_label })),
)

async function openCreateModal() {
  editingId.value = null
  editingCompleted.value = false
  modalSearch.value = ''
  modalConditionTab.value = 'all'
  modalOnlyNonZero.value = false
  form.referenceAt = new Date().toISOString().slice(0, 10)
  showCreateModal.value = true

  try {
    await master.refresh(true)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data stok')
  }

  form.officerName = activeOfficers.value[0]?.name || 'Petugas Opname'
  const lines: DraftLine[] = []
  for (const v of master.variants) {
    const conds: Array<{ cond: 'new' | 'used_good' | 'quarantine' | 'damaged'; qty: number }> = [
      { cond: 'new', qty: Number(v.stock_new) },
      { cond: 'used_good', qty: Number(v.stock_used_good) },
    ]
    if (Number(v.stock_quarantine) > 0) conds.push({ cond: 'quarantine', qty: Number(v.stock_quarantine) })
    if (Number(v.stock_damaged) > 0) conds.push({ cond: 'damaged', qty: Number(v.stock_damaged) })

    for (const c of conds) {
      lines.push({
        variantId: v.variant_id,
        name: v.name,
        code: v.code,
        size: v.size,
        unit: v.unit,
        condition: c.cond,
        systemQuantity: c.qty,
        physicalQuantity: c.qty,
        reason: '',
      })
    }
  }
  form.lines = lines
}

async function openEditModal(st: StocktakeRow) {
  editingId.value = st.id
  editingCompleted.value = st.status === 'completed'
  modalSearch.value = ''
  modalConditionTab.value = 'all'
  modalOnlyNonZero.value = false
  form.referenceAt = st.reference_at.slice(0, 10)
  form.officerName = st.officer_name
  showDetailModal.value = false
  showCreateModal.value = true

  try {
    await master.refresh(true)
  } catch {}

  const existingMap = new Map(st.stocktake_items.map((it) => [`${it.variant_id}:${it.condition}`, it]))
  const lines: DraftLine[] = []
  for (const v of master.variants) {
    const conds: Array<{ cond: 'new' | 'used_good' | 'quarantine' | 'damaged'; qty: number }> = [
      { cond: 'new', qty: Number(v.stock_new) },
      { cond: 'used_good', qty: Number(v.stock_used_good) },
    ]
    if (Number(v.stock_quarantine) > 0 || existingMap.has(`${v.variant_id}:quarantine`)) {
      conds.push({ cond: 'quarantine', qty: Number(v.stock_quarantine) })
    }
    if (Number(v.stock_damaged) > 0 || existingMap.has(`${v.variant_id}:damaged`)) {
      conds.push({ cond: 'damaged', qty: Number(v.stock_damaged) })
    }
    for (const c of conds) {
      const prev = existingMap.get(`${v.variant_id}:${c.cond}`)
      const preSoSystem = prev
        ? editingCompleted.value
          ? Math.max(0, c.qty - Number(prev.adjustment_quantity ?? 0))
          : Number(prev.system_quantity)
        : c.qty
      lines.push({
        variantId: v.variant_id,
        name: v.name,
        code: v.code,
        size: v.size,
        unit: v.unit,
        condition: c.cond,
        systemQuantity: preSoSystem,
        physicalQuantity: prev ? Number(prev.physical_quantity) : c.qty,
        reason: prev?.reason || '',
      })
    }
  }
  form.lines = lines
}

async function submitStocktake(finalizeNow: boolean) {
  if (!form.lines.length) {
    toast.error('Tidak ada varian barang untuk diopname')
    return
  }
  saving.value = true
  try {
    const endpoint = editingId.value ? `/api/transactions/stocktakes/${editingId.value}` : '/api/transactions/stocktakes'
    const method = editingId.value ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      body: JSON.stringify({
        referenceAt: form.referenceAt,
        officerName: form.officerName,
        finalizeNow,
        items: form.lines.map((l) => ({
          variantId: l.variantId,
          condition: l.condition,
          physicalQuantity: Number(l.physicalQuantity),
          reason: l.reason || null,
        })),
      }),
    })
    await Promise.all([load(), master.refresh(true)])
    toast.success(
      editingCompleted.value
        ? 'Stok opname berhasil direvisi & stok inventaris disesuaikan!'
        : finalizeNow
          ? 'Stok opname difinalisasi & stok gudang disesuaikan sesuai fisik aktual!'
          : editingId.value
            ? 'Draft stok opname berhasil diperbarui'
            : 'Stok opname disimpan sebagai draft',
    )
    showCreateModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan stok opname')
  } finally {
    saving.value = false
  }
}

async function finalizeExisting(id: string) {
  finalizing.value = true
  try {
    await api('/api/transactions/stocktakes/finalize', {
      method: 'POST',
      body: JSON.stringify({ stocktakeId: id }),
    })
    await Promise.all([load(), master.refresh(true)])
    toast.success('Stok opname difinalisasi & stok gudang diperbarui!')
    showDetailModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal finalisasi')
  } finally {
    finalizing.value = false
  }
}

async function deleteStocktake(st: StocktakeRow) {
  const warn = st.status === 'completed'
    ? `Hapus stok opname "${st.stocktake_no}"? Penyesuaian stok yang pernah diterapkan dari SO ini akan dikembalikan ke stok sebelumnya.`
    : `Hapus draft stok opname "${st.stocktake_no}" secara permanen?`
  if (!window.confirm(warn)) return
  try {
    await api(`/api/transactions/stocktakes/${st.id}`, { method: 'DELETE' })
    showDetailModal.value = false
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Stok opname ${st.stocktake_no} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus stok opname')
  }
}

async function deleteLostReturn(log: (typeof lostLogs.value)[number]) {
  if (!window.confirm(`Hapus transaksi pengembalian "${log.transaction_no}" (termasuk catatan kehilangan ini)?`)) return
  try {
    await api(`/api/transactions/returns/${log.returnId}`, { method: 'DELETE' })
    showLostPreviewModal.value = false
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Catatan pengembalian ${log.transaction_no} berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus catatan')
  }
}

function openDetail(st: StocktakeRow) {
  activeStocktake.value = st
  detailConditionTab.value = 'all'
  showDetailModal.value = true
}

function exportVarianceCsv(st: StocktakeRow) {
  downloadCsv(
    `laporan-opname-${st.stocktake_no}.csv`,
    ['No Opname', 'Tanggal SO', 'Petugas', 'Kode', 'Barang', 'Ukuran', 'Kondisi', 'Stok Sistem', 'Stok Fisik', 'Selisih (+/-)', 'Status Selisih', 'Alasan'],
    st.stocktake_items.map((it) => {
      const diff = Number(it.physical_quantity) - Number(it.system_quantity)
      return [
        st.stocktake_no,
        st.reference_at.slice(0, 10),
        st.officer_name,
        it.item_variants?.items?.code || '',
        it.item_variants?.items?.name || '',
        it.item_variants?.size || '',
        conditionLabel(it.condition),
        it.system_quantity,
        it.physical_quantity,
        diff > 0 ? `+${diff}` : String(diff),
        diff > 0 ? 'Surplus (+)' : diff < 0 ? 'Kurang / Hilang (-)' : 'Sesuai (0)',
        it.reason || '',
      ]
    }),
  )
}

async function exportVariancePdf(st: StocktakeRow) {
  try {
    const v = varianceSummary(st)
    const [{ generateInventoryPdf }, companyLogoDataUrl] = await Promise.all([
      import('@/lib/pdf-report'),
      master.company.logoKey ? imageUrlToDataUrl(attachmentUrl(master.company.logoKey)) : Promise.resolve(null),
    ])
    generateInventoryPdf({
      filename: `Laporan-Stok-Opname-${st.stocktake_no}.pdf`,
      reportTitle: `LAPORAN STOK OPNAME · ${st.stocktake_no}`,
      periodLabel: `Tanggal SO: ${formatDate(st.reference_at)} · Petugas: ${st.officer_name}`,
      companyName: master.company.name,
      companyTagline: `INVENTRA · ${master.company.tagline}`,
      companyLogoDataUrl,
      summaryStats: [
        { label: 'No. Dokumen SO', value: st.stocktake_no },
        { label: 'Total Varian Diperiksa', value: `${st.stocktake_items.length} baris` },
        { label: 'Total Surplus (+)', value: `+${formatNumber(v.plus)} unit` },
        { label: 'Total Kurang / Hilang (-)', value: `-${formatNumber(v.minus)} unit` },
      ],
      sections: [
        {
          title: `Rincian Hasil Pemeriksaan Fisik — ${st.stocktake_no}`,
          subtitle: `Petugas: ${st.officer_name} · Status: ${st.status === 'completed' ? 'Selesai (Difinalisasi)' : 'Menunggu Finalisasi'}`,
          headers: ['Kode', 'Nama Barang', 'Kondisi', 'Stok Sistem', 'Stok Fisik', 'Selisih (+/-)', 'Status', 'Alasan'],
          rows: st.stocktake_items.map((it) => {
            const diff = Number(it.physical_quantity) - Number(it.system_quantity)
            const unit = it.item_variants?.items?.unit || 'unit'
            return [
              it.item_variants?.items?.code || '-',
              variantLabel({ name: it.item_variants?.items?.name || '-', size: it.item_variants?.size }),
              conditionLabel(it.condition),
              `${formatNumber(it.system_quantity)} ${unit}`,
              `${formatNumber(it.physical_quantity)} ${unit}`,
              `${diff > 0 ? '+' : ''}${formatNumber(diff)} ${unit}`,
              diff > 0 ? 'Surplus' : diff < 0 ? 'Kurang' : 'Sesuai',
              it.reason || '-',
            ]
          }),
        },
      ],
    })
    toast.success(`PDF Stok Opname ${st.stocktake_no} berhasil diunduh!`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal membuat PDF stok opname')
  }
}

let lastCacheVer = -1
onMounted(() => { lastCacheVer = getApiCacheVersion(); void Promise.all([load(), master.refresh()]) })
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
        <p class="eyebrow">Rekonsiliasi &amp; Laporan +/-</p>
        <h2>Stok Opname</h2>
        <p>Bandingkan stok sistem dengan stok fisik aktual di gudang. Stok inventaris otomatis disesuaikan tepat sesuai angka fisik aktual.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openCreateModal"><Plus :size="17" /> Buat Stok Opname</button>
      </div>
    </section>

    <section class="mini-stats">
      <button type="button" class="mini-stat-btn" @click="openStatHistory('sessions')">
        <span class="mini-icon unified"><ClipboardCheck :size="19" /></span>
        <p>Sesi Opname<strong>{{ rows.length }}</strong></p>
      </button>
      <button type="button" class="mini-stat-btn" @click="openStatHistory('surplus')">
        <span class="mini-icon unified"><Plus :size="19" /></span>
        <p>Total Surplus (+)<strong>+{{ formatNumber(totalGlobalPlus) }}</strong></p>
      </button>
      <button type="button" class="mini-stat-btn" @click="openStatHistory('minus')">
        <span class="mini-icon unified"><AlertTriangle :size="19" /></span>
        <p>Total Kurang / Hilang (-)<strong>-{{ formatNumber(totalGlobalMinus) }}</strong></p>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: activeTab === 'all' }" @click="activeTab = 'all'">Semua Stok Opname ({{ filteredRows.length }})</button>
        <button :class="{ active: activeTab === 'lost_logs' }" @click="activeTab = 'lost_logs'">
          Catatan Hilang Pengembalian ({{ filteredLostLogs.length }})
        </button>
      </div>

      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field">
          <Search :size="16" />
          <input v-model="search" placeholder="Cari No. SO (SO-...), petugas, nama barang, atau alasan..." />
        </label>

        <div class="date-range-inline">
          <CalendarRange :size="15" />
          <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" aria-label="Dari tanggal" />
          <span class="date-sep">s/d</span>
          <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" aria-label="Sampai tanggal" />
        </div>

        <template v-if="activeTab === 'all'">
          <ModernSelect v-model="officerFilter" :options="officerFilterOptions" compact searchable search-placeholder="Cari petugas..." />
          <ModernSelect v-model="varianceFilter" :options="varianceFilterOptions" compact searchable search-placeholder="Cari hasil selisih..." />
          <ModernSelect v-model="soStatusFilter" :options="soStatusFilterOptions" compact searchable search-placeholder="Cari status SO..." />
        </template>

        <button v-if="hasActiveFilters" type="button" class="secondary-button xs" @click="resetFilters">
          <RotateCcw :size="13" /> Reset
        </button>
      </div>

      <div v-if="activeTab === 'lost_logs'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengembalian</th><th>Tanggal</th><th>Karyawan</th><th>Barang Hilang</th><th>Jumlah</th><th>Catatan / Alasan</th><th>Aksi</th></tr></thead>
          <tbody>
            <tr v-for="log in pagedLostLogs" :key="log.id">
              <td><strong>{{ log.transaction_no }}</strong></td>
              <td>{{ formatDate(log.returned_at) }}</td>
              <td><strong>{{ log.employee_name }}</strong></td>
              <td>{{ log.item_name }}</td>
              <td><span class="delta-pill minus">-{{ formatNumber(log.qty) }} {{ log.unit }}</span></td>
              <td>{{ log.reason }}</td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Preview detail kehilangan" @click="openLostPreview(log)"><Eye :size="15" /></button>
                  <button class="icon-button" title="Edit di Pengembalian APD" @click="router.push({ name: 'returns' })"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus catatan pengembalian" @click="deleteLostReturn(log)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredLostLogs.length">
              <td colspan="7"><div class="empty-state compact"><AlertTriangle :size="24" /><strong>Belum ada catatan kehilangan yang cocok.</strong></div></td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-if="activeTab === 'lost_logs'" v-model:page="lostPage" :total-items="filteredLostLogs.length" />

      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>No. &amp; Tanggal SO</th><th>Petugas</th><th>Jumlah Varian</th><th>Laporan Selisih (+/-)</th><th>Status</th><th>Aksi</th></tr></thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td><strong>{{ row.stocktake_no }}</strong><small class="table-sub">Tanggal SO: {{ formatDate(row.reference_at) }}</small></td>
              <td>{{ row.officer_name }}</td>
              <td>{{ row.stocktake_items.length }} baris</td>
              <td>
                <div class="tag-group">
                  <span class="delta-pill plus">+{{ formatNumber(varianceSummary(row).plus) }} surplus</span>
                  <span class="delta-pill minus">-{{ formatNumber(varianceSummary(row).minus) }} hilang/kurang</span>
                </div>
              </td>
              <td>
                <span class="status-pill" :class="row.status === 'completed' ? 'safe' : 'amber'">
                  {{ row.status === 'completed' ? 'Selesai' : 'Menunggu Finalisasi' }}
                </span>
              </td>
              <td>
                <div class="row-actions">
                  <button class="secondary-button xs" @click="openDetail(row)"><Eye :size="13" /> Laporan +/-</button>
                  <button class="secondary-button xs highlight" title="Download PDF Opname" @click="exportVariancePdf(row)">
                    <FileDown :size="13" /> PDF
                  </button>
                  <button class="icon-button" title="Unduh CSV Opname" @click="exportVarianceCsv(row)"><Download :size="15" /></button>
                  <button class="icon-button" title="Edit stok opname" @click="openEditModal(row)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus stok opname" @click="deleteStocktake(row)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="6"><div class="empty-state"><ClipboardCheck :size="32" /><strong>Belum ada stok opname yang cocok</strong><span>Ubah filter atau klik "Buat Stok Opname" untuk menghitung stok fisik aktual.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat riwayat stok opname...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-if="activeTab !== 'lost_logs'" v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <!-- Create / Edit Stocktake Modal -->
    <BaseModal
      :open="showCreateModal"
      :title="editingId ? (editingCompleted ? 'Edit Stok Opname (Revisi Penyesuaian)' : 'Edit Draft Stok Opname') : 'Input Stok Opname Fisik'"
      eyebrow="Audit & Penyesuaian Stok"
      subtitle="Masukkan tanggal SO dan jumlah fisik aktual di gudang. Stok inventaris akan disesuaikan tepat sesuai angka fisik aktual."
      size="xl"
      @close="showCreateModal = false"
    >
      <div class="modal-form">
        <div class="form-grid-3">
          <label class="field"><span>Tanggal SO *</span><input v-model="form.referenceAt" type="date" required /></label>
          <label class="field"><span>Petugas Opname *</span>
            <ModernSelect v-if="activeOfficers.length" v-model="form.officerName" :options="officerOptions" searchable required />
            <input v-else v-model="form.officerName" required />
          </label>
          <label class="field"><span>Cari Barang di Daftar Opname</span>
            <label class="search-field full"><Search :size="15" /><input v-model="modalSearch" placeholder="Ketik nama atau kode barang..." /></label>
          </label>
        </div>

        <div class="summary-banner">
          <div><small>Total Baris</small><strong>{{ form.lines.length }} item</strong></div>
          <div><small>Selisih Surplus (+)</small><strong class="text-primary">+{{ formatNumber(draftSummary.plusUnits) }} ({{ draftSummary.plusCount }} item)</strong></div>
          <div><small>Selisih Kurang / Hilang (-)</small><strong class="text-red">-{{ formatNumber(draftSummary.minusUnits) }} ({{ draftSummary.minusCount }} item)</strong></div>
        </div>

        <div class="so-cond-toolbar">
          <div class="so-cond-pills">
            <button type="button" class="so-cond-pill" :class="{ active: modalConditionTab === 'all' }" @click="modalConditionTab = 'all'">
              Semua Kondisi <span>{{ conditionTabCounts.all }}</span>
            </button>
            <button type="button" class="so-cond-pill cond-new" :class="{ active: modalConditionTab === 'new' }" @click="modalConditionTab = 'new'">
              <i /> Baru <span>{{ conditionTabCounts.new }}</span>
            </button>
            <button type="button" class="so-cond-pill cond-used" :class="{ active: modalConditionTab === 'used_good' }" @click="modalConditionTab = 'used_good'">
              <i /> Bekas Layak <span>{{ conditionTabCounts.used_good }}</span>
            </button>
            <button v-if="conditionTabCounts.quarantine > 0" type="button" class="so-cond-pill cond-quarantine" :class="{ active: modalConditionTab === 'quarantine' }" @click="modalConditionTab = 'quarantine'">
              <i /> Karantina <span>{{ conditionTabCounts.quarantine }}</span>
            </button>
            <button v-if="conditionTabCounts.damaged > 0" type="button" class="so-cond-pill cond-damaged" :class="{ active: modalConditionTab === 'damaged' }" @click="modalConditionTab = 'damaged'">
              <i /> Rusak <span>{{ conditionTabCounts.damaged }}</span>
            </button>
          </div>
          <label class="so-nonzero-toggle">
            <input v-model="modalOnlyNonZero" type="checkbox" />
            <span>Hanya yang ada stok / diisi</span>
          </label>
        </div>

        <div v-if="!groupedDraftSections.length" class="empty-state compact">
          <strong>Tidak ada item yang cocok dengan filter pencarian.</strong>
        </div>

        <div v-else class="so-groups-stack">
          <section v-for="sec in groupedDraftSections" :key="sec.key" class="so-group-card" :class="`tone-${sec.tone}`">
            <header class="so-group-head">
              <div class="so-group-title">
                <span class="cond-badge" :class="conditionTone(sec.key)">{{ sec.title }}</span>
                <small>{{ sec.desc }}</small>
              </div>
              <div class="so-group-metrics">
                <span class="tag-pill">{{ sec.items.length }} barang</span>
                <span class="tag-pill">Sistem: <b>{{ formatNumber(sec.totalSys) }}</b></span>
                <span class="tag-pill">Fisik: <b>{{ formatNumber(sec.totalPhys) }}</b></span>
                <span v-if="sec.plus > 0" class="delta-pill plus">+{{ formatNumber(sec.plus) }}</span>
                <span v-if="sec.minus > 0" class="delta-pill minus">-{{ formatNumber(sec.minus) }}</span>
              </div>
            </header>
            <div class="table-wrap" style="margin-top:0;">
              <table>
                <thead>
                  <tr>
                    <th>Barang &amp; Ukuran</th>
                    <th>Kondisi</th>
                    <th>Stok Sistem</th>
                    <th style="width:130px;">Fisik Aktual</th>
                    <th>Selisih (+/-)</th>
                    <th style="min-width:190px;">Keterangan / Alasan</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="line in sec.items"
                    :key="`${line.variantId}-${line.condition}`"
                    :class="line.physicalQuantity - line.systemQuantity > 0 ? 'so-row-plus' : line.physicalQuantity - line.systemQuantity < 0 ? 'so-row-minus' : ''"
                  >
                    <td><strong>{{ variantLabel(line) }}</strong><small class="table-sub">{{ line.code }}</small></td>
                    <td><span class="cond-badge sm" :class="conditionTone(line.condition)">{{ conditionLabel(line.condition) }}</span></td>
                    <td><strong>{{ formatNumber(line.systemQuantity) }}</strong> <small>{{ line.unit }}</small></td>
                    <td>
                      <input v-model.number="line.physicalQuantity" type="number" min="0" step="any" class="table-input so-qty-input" />
                    </td>
                    <td>
                      <span
                        class="delta-pill"
                        :class="line.physicalQuantity - line.systemQuantity > 0 ? 'plus' : line.physicalQuantity - line.systemQuantity < 0 ? 'minus' : 'zero'"
                      >
                        {{ line.physicalQuantity - line.systemQuantity > 0 ? '+' : '' }}{{ formatNumber(line.physicalQuantity - line.systemQuantity) }}
                      </span>
                    </td>
                    <td>
                      <input v-model="line.reason" class="table-input" placeholder="Mis. hilang / salah hitung" />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <template #footer>
        <button type="button" class="secondary-button" @click="showCreateModal = false">Batal</button>
        <button v-if="!editingCompleted" type="button" class="secondary-button" :disabled="saving" @click="submitStocktake(false)">
          {{ editingId ? 'Simpan Perubahan Draft' : 'Simpan Draft' }}
        </button>
        <button type="button" class="primary-button" :disabled="saving" @click="submitStocktake(true)">
          <CheckCircle2 :size="16" /> {{ saving ? 'Memproses...' : (editingCompleted ? 'Simpan Revisi & Sesuaikan Stok' : 'Simpan & Finalisasi Sekarang') }}
        </button>
      </template>
    </BaseModal>

    <!-- Detail & +/- Variance Modal -->
    <BaseModal
      :open="showDetailModal"
      :title="`Laporan Selisih Opname (+/-) · ${activeStocktake?.stocktake_no || ''}`"
      eyebrow="Hasil Rekonsiliasi Stok"
      size="lg"
      @close="showDetailModal = false"
    >
      <div v-if="activeStocktake" class="detail-stack">
        <div class="summary-banner">
          <div><small>Tanggal SO &amp; Petugas</small><strong>{{ formatDate(activeStocktake.reference_at) }} · {{ activeStocktake.officer_name }}</strong></div>
          <div><small>Surplus (+)</small><strong class="text-primary">+{{ formatNumber(varianceSummary(activeStocktake).plus) }}</strong></div>
          <div><small>Kurang / Hilang (-)</small><strong class="text-red">-{{ formatNumber(varianceSummary(activeStocktake).minus) }}</strong></div>
        </div>

        <div class="so-cond-pills">
          <button type="button" class="so-cond-pill" :class="{ active: detailConditionTab === 'all' }" @click="detailConditionTab = 'all'">Semua Kondisi</button>
          <button type="button" class="so-cond-pill cond-new" :class="{ active: detailConditionTab === 'new' }" @click="detailConditionTab = 'new'"><i /> Baru</button>
          <button type="button" class="so-cond-pill cond-used" :class="{ active: detailConditionTab === 'used_good' }" @click="detailConditionTab = 'used_good'"><i /> Bekas Layak</button>
          <button type="button" class="so-cond-pill cond-quarantine" :class="{ active: detailConditionTab === 'quarantine' }" @click="detailConditionTab = 'quarantine'"><i /> Karantina</button>
          <button type="button" class="so-cond-pill cond-damaged" :class="{ active: detailConditionTab === 'damaged' }" @click="detailConditionTab = 'damaged'"><i /> Rusak</button>
        </div>

        <div class="so-groups-stack">
          <section v-for="sec in filteredDetailSections" :key="sec.key" class="so-group-card" :class="`tone-${sec.tone}`">
            <header class="so-group-head">
              <div class="so-group-title">
                <span class="cond-badge" :class="conditionTone(sec.key)">{{ sec.title }}</span>
                <small>{{ sec.items.length }} barang</small>
              </div>
            </header>
            <div class="table-wrap" style="margin-top:0;">
              <table>
                <thead><tr><th>Barang</th><th>Kondisi</th><th>Sistem</th><th>Fisik</th><th>Selisih (+/-)</th><th>Alasan</th></tr></thead>
                <tbody>
                  <tr
                    v-for="it in sec.items"
                    :key="it.id"
                    :class="it.physical_quantity - it.system_quantity > 0 ? 'so-row-plus' : it.physical_quantity - it.system_quantity < 0 ? 'so-row-minus' : ''"
                  >
                    <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name, size: it.item_variants?.size }) }}</strong></td>
                    <td><span class="cond-badge sm" :class="conditionTone(it.condition)">{{ conditionLabel(it.condition) }}</span></td>
                    <td>{{ formatNumber(it.system_quantity) }}</td>
                    <td><strong>{{ formatNumber(it.physical_quantity) }}</strong></td>
                    <td>
                      <span
                        class="delta-pill"
                        :class="it.physical_quantity - it.system_quantity > 0 ? 'plus' : it.physical_quantity - it.system_quantity < 0 ? 'minus' : 'zero'"
                      >
                        {{ it.physical_quantity - it.system_quantity > 0 ? '+' : '' }}{{ formatNumber(it.physical_quantity - it.system_quantity) }}
                      </span>
                    </td>
                    <td>{{ it.reason || '-' }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
      <template #footer>
        <button v-if="activeStocktake" type="button" class="secondary-button danger-soft" @click="deleteStocktake(activeStocktake)">
          <Trash2 :size="15" /> Hapus SO
        </button>
        <button v-if="activeStocktake" type="button" class="secondary-button" @click="openEditModal(activeStocktake)">
          <Edit3 :size="15" /> Edit SO
        </button>
        <button v-if="activeStocktake" type="button" class="secondary-button" @click="exportVarianceCsv(activeStocktake)">
          <Download :size="15" /> Ekspor CSV
        </button>
        <button v-if="activeStocktake" type="button" class="secondary-button highlight" @click="exportVariancePdf(activeStocktake)">
          <FileDown :size="15" /> Download PDF
        </button>
        <button v-if="activeStocktake?.status === 'pending_review'" type="button" class="primary-button" :disabled="finalizing" @click="finalizeExisting(activeStocktake.id)">
          <CheckCircle2 :size="15" /> Finalisasi &amp; Sesuaikan Stok
        </button>
      </template>
    </BaseModal>

    <BaseModal
      :open="showLostPreviewModal"
      :title="`Detail Kehilangan · ${activeLostLog?.transaction_no || ''}`"
      eyebrow="Preview Catatan Hilang Pengembalian"
      size="sm"
      @close="showLostPreviewModal = false"
    >
      <div v-if="activeLostLog" class="table-wrap" style="margin-top:0;">
        <table>
          <tbody>
            <tr><th style="width:40%;">No. Pengembalian</th><td><strong>{{ activeLostLog.transaction_no }}</strong></td></tr>
            <tr><th>Tanggal</th><td>{{ formatDate(activeLostLog.returned_at) }}</td></tr>
            <tr><th>Karyawan</th><td><strong>{{ activeLostLog.employee_name }}</strong></td></tr>
            <tr><th>Barang Hilang</th><td><strong>{{ activeLostLog.item_name }}</strong></td></tr>
            <tr><th>Jumlah Hilang</th><td><span class="delta-pill minus">-{{ formatNumber(activeLostLog.qty) }} {{ activeLostLog.unit }}</span></td></tr>
            <tr><th>Alasan / Kronologi</th><td>{{ activeLostLog.reason }}</td></tr>
          </tbody>
        </table>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showLostPreviewModal = false">Tutup</button>
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
