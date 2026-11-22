<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { AlertTriangle, CheckCircle2, ClipboardCheck, Download, Edit3, Eye, Plus, Search } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, conditionLabel, downloadCsv, formatDate, formatNumber, getApiCacheVersion, variantLabel } from '@/lib/api'
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

const master = useMasterStore()
const toast = useToast()

const rows = ref<StocktakeRow[]>([])
const lostLogs = ref<Array<{
  id: string; transaction_no: string; returned_at: string; employee_name: string;
  item_name: string; unit: string; qty: number; reason: string
}>>([])
const loading = ref(true)
const statusFilter = ref<'all' | 'pending_review' | 'completed' | 'surplus' | 'minus' | 'lost_logs'>('all')
const page = ref(1)
const lostPage = ref(1)

const showCreateModal = ref(false)
const editingId = ref<string | null>(null)
const modalSearch = ref('')
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

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

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
        status: { text: st.status === 'completed' ? 'Selesai' : 'Menunggu Review', pill: st.status === 'completed' ? 'safe' : 'amber' },
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
  if (statusFilter.value === 'all' || statusFilter.value === 'lost_logs') return rows.value
  if (statusFilter.value === 'surplus') return rows.value.filter((r) => varianceSummary(r).plus > 0)
  if (statusFilter.value === 'minus') return rows.value.filter((r) => varianceSummary(r).minus > 0)
  return rows.value.filter((r) => r.status === statusFilter.value)
})
const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * 10, page.value * 10))
const pagedLostLogs = computed(() => lostLogs.value.slice((lostPage.value - 1) * 10, lostPage.value * 10))
watch(statusFilter, () => { page.value = 1; lostPage.value = 1 })

const filteredDraftLines = computed(() => {
  if (!modalSearch.value.trim()) return form.lines
  const q = modalSearch.value.toLowerCase()
  return form.lines.filter((l) => l.name.toLowerCase().includes(q) || l.code.toLowerCase().includes(q) || l.size.toLowerCase().includes(q))
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
  modalSearch.value = ''
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
  modalSearch.value = ''
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
      lines.push({
        variantId: v.variant_id,
        name: v.name,
        code: v.code,
        size: v.size,
        unit: v.unit,
        condition: c.cond,
        systemQuantity: prev ? Number(prev.system_quantity) : c.qty,
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
      finalizeNow
        ? 'Stok opname difinalisasi & selisih (+/-) disesuaikan!'
        : editingId.value
          ? 'Draft stok opname berhasil diperbarui'
          : 'Stok opname disimpan menunggu pemeriksaan',
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
    toast.success('Stok opname difinalisasi & saldo gudang diperbarui!')
    showDetailModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal finalisasi')
  } finally {
    finalizing.value = false
  }
}

function openDetail(st: StocktakeRow) {
  activeStocktake.value = st
  showDetailModal.value = true
}

function exportVarianceCsv(st: StocktakeRow) {
  downloadCsv(
    `laporan-opname-${st.stocktake_no}.csv`,
    ['No Opname', 'Tanggal SO', 'Kode', 'Barang', 'Ukuran', 'Kondisi', 'Stok Sistem', 'Stok Fisik', 'Selisih (+/-)', 'Status Selisih', 'Alasan'],
    st.stocktake_items.map((it) => {
      const diff = Number(it.physical_quantity) - Number(it.system_quantity)
      return [
        st.stocktake_no,
        st.reference_at.slice(0, 10),
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
        <p class="eyebrow">Rekonsiliasi & Laporan +/-</p>
        <h2>Stok Opname</h2>
        <p>Bandingkan saldo sistem dengan stok fisik gudang. Draft opname tetap bisa diedit sebelum difinalisasi.</p>
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
        <button :class="{ active: statusFilter === 'all' }" @click="statusFilter = 'all'">Semua Opname</button>
        <button :class="{ active: statusFilter === 'pending_review' }" @click="statusFilter = 'pending_review'">Menunggu Pemeriksaan</button>
        <button :class="{ active: statusFilter === 'completed' }" @click="statusFilter = 'completed'">Selesai (Difinalisasi)</button>
        <button :class="{ active: statusFilter === 'lost_logs' }" @click="statusFilter = 'lost_logs'">
          Catatan Hilang Pengembalian ({{ lostLogs.length }})
        </button>
      </div>

      <div v-if="statusFilter === 'lost_logs'" class="table-wrap">
        <table>
          <thead><tr><th>No. Pengembalian</th><th>Tanggal</th><th>Karyawan</th><th>Barang Hilang</th><th>Jumlah</th><th>Catatan / Alasan</th></tr></thead>
          <tbody>
            <tr v-for="log in pagedLostLogs" :key="log.id">
              <td><strong>{{ log.transaction_no }}</strong></td>
              <td>{{ formatDate(log.returned_at) }}</td>
              <td><strong>{{ log.employee_name }}</strong></td>
              <td>{{ log.item_name }}</td>
              <td><span class="delta-pill minus">-{{ formatNumber(log.qty) }} {{ log.unit }}</span></td>
              <td>{{ log.reason }}</td>
            </tr>
            <tr v-if="!loading && !lostLogs.length">
              <td colspan="6"><div class="empty-state compact"><AlertTriangle :size="24" /><strong>Belum ada catatan kehilangan dari pengembalian APD.</strong></div></td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-if="statusFilter === 'lost_logs'" v-model:page="lostPage" :total-items="lostLogs.length" />

      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>No. & Tanggal SO</th><th>Petugas</th><th>Jumlah Varian</th><th>Laporan Selisih (+/-)</th><th>Status</th><th>Aksi</th></tr></thead>
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
                  <button v-if="row.status !== 'completed'" class="secondary-button xs" title="Edit sebelum finalisasi" @click="openEditModal(row)">
                    <Edit3 :size="13" /> Edit
                  </button>
                  <button class="secondary-button xs" @click="openDetail(row)"><Eye :size="13" /> Laporan +/-</button>
                  <button class="icon-button" title="Ekspor CSV Opname" @click="exportVarianceCsv(row)"><Download :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="6"><div class="empty-state"><ClipboardCheck :size="32" /><strong>Belum ada stok opname</strong><span>Klik "Buat Stok Opname" untuk menghitung stok fisik dan melaporkan selisih + / -.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat riwayat stok opname...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-if="statusFilter !== 'lost_logs'" v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <!-- Create / Edit Stocktake Modal -->
    <BaseModal
      :open="showCreateModal"
      :title="editingId ? 'Edit Draft Stok Opname' : 'Input Stok Opname Fisik'"
      eyebrow="Audit & Penyesuaian Stok"
      subtitle="Masukkan tanggal SO dan jumlah fisik sebenarnya di gudang. Selisih (+) atau (-) dihitung otomatis."
      size="xl"
      @close="showCreateModal = false"
    >
      <div class="modal-form">
        <div class="form-grid-3">
          <label class="field"><span>Tanggal SO *</span><input v-model="form.referenceAt" type="date" required /></label>
          <label class="field"><span>Petugas Opname *</span>
            <ModernSelect v-if="activeOfficers.length" v-model="form.officerName" :options="officerOptions" required />
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

        <div class="table-wrap">
          <table>
            <thead><tr><th>Barang & Ukuran</th><th>Kondisi</th><th>Sistem</th><th>Fisik Gudang</th><th>Selisih (+/-)</th><th>Keterangan / Alasan</th></tr></thead>
            <tbody>
              <tr v-for="(line, idx) in filteredDraftLines" :key="idx">
                <td><strong>{{ variantLabel(line) }}</strong><small class="table-sub">{{ line.code }}</small></td>
                <td>{{ conditionLabel(line.condition) }}</td>
                <td><strong>{{ formatNumber(line.systemQuantity) }}</strong> {{ line.unit }}</td>
                <td style="width: 120px;">
                  <input v-model.number="line.physicalQuantity" type="number" min="0" step="any" class="table-input" />
                </td>
                <td>
                  <span
                    class="delta-pill"
                    :class="line.physicalQuantity - line.systemQuantity > 0 ? 'plus' : line.physicalQuantity - line.systemQuantity < 0 ? 'minus' : 'zero'"
                  >
                    {{ line.physicalQuantity - line.systemQuantity > 0 ? '+' : '' }}{{ formatNumber(line.physicalQuantity - line.systemQuantity) }}
                  </span>
                </td>
                <td style="min-width: 190px;">
                  <input v-model="line.reason" class="table-input" placeholder="Mis. hilang / salah hitung" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <template #footer>
        <button type="button" class="secondary-button" @click="showCreateModal = false">Batal</button>
        <button type="button" class="secondary-button" :disabled="saving" @click="submitStocktake(false)">
          {{ editingId ? 'Simpan Perubahan Draft' : 'Simpan Draft' }}
        </button>
        <button type="button" class="primary-button" :disabled="saving" @click="submitStocktake(true)">
          <CheckCircle2 :size="16" /> {{ saving ? 'Memproses...' : 'Simpan & Finalisasi Sekarang' }}
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
          <div><small>Tanggal SO & Petugas</small><strong>{{ formatDate(activeStocktake.reference_at) }} · {{ activeStocktake.officer_name }}</strong></div>
          <div><small>Surplus (+)</small><strong class="text-primary">+{{ formatNumber(varianceSummary(activeStocktake).plus) }}</strong></div>
          <div><small>Kurang / Hilang (-)</small><strong class="text-red">-{{ formatNumber(varianceSummary(activeStocktake).minus) }}</strong></div>
        </div>

        <div class="table-wrap">
          <table>
            <thead><tr><th>Barang</th><th>Kondisi</th><th>Sistem</th><th>Fisik</th><th>Selisih (+/-)</th><th>Alasan</th></tr></thead>
            <tbody>
              <tr v-for="it in activeStocktake.stocktake_items" :key="it.id">
                <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name, size: it.item_variants?.size }) }}</strong></td>
                <td>{{ conditionLabel(it.condition) }}</td>
                <td>{{ formatNumber(it.system_quantity) }}</td>
                <td>{{ formatNumber(it.physical_quantity) }}</td>
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
      </div>
      <template #footer>
        <button v-if="activeStocktake && activeStocktake.status !== 'completed'" type="button" class="secondary-button" @click="openEditModal(activeStocktake)">
          <Edit3 :size="15" /> Edit SO
        </button>
        <button v-if="activeStocktake" type="button" class="secondary-button" @click="exportVarianceCsv(activeStocktake)">
          <Download :size="15" /> Ekspor CSV (+/-)
        </button>
        <button v-if="activeStocktake?.status === 'pending_review'" type="button" class="primary-button" :disabled="finalizing" @click="finalizeExisting(activeStocktake.id)">
          <CheckCircle2 :size="15" /> Finalisasi & Sesuaikan Saldo
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
