<script setup lang="ts">
import { computed, onActivated, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  AlertTriangle, ArrowDownToLine, ArrowRightLeft, ArrowUpFromLine, Boxes,
  CheckCircle2, ClipboardCheck, ClipboardList, PackageCheck, PackageMinus, PackagePlus, RefreshCw, ShoppingBag, Wallet,
} from '@lucide/vue'
import ModernSelect from '@/components/ModernSelect.vue'
import StatCard from '@/components/StatCard.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, conditionLabel, formatCurrency, formatDate, formatNumber, getApiCacheVersion, invalidateApiCache, prefetchApi, variantLabel } from '@/lib/api'
import { flaticonAssets } from '@/lib/icons'
import { useMasterStore } from '@/stores/master'

type Flow = { unit: string; incoming: number; outgoing: number }
type MonthFlow = Flow & { month: string }
type Attention = { variant_id: string; code: string; name: string; size: string; unit: string; total_available: number; minimum_stock: number; stock_status: 'low' | 'out' }
type ActiveProc = { id: string; procurement_no: string; po_number: string | null; supplier_name: string; total_ordered: number; total_received: number; progress_percent: number; status: string }
type Dashboard = {
  itemTypes: number; stockByUnit: Array<{ unit: string; quantity: number }>;
  lowStockTypes: number; outStockTypes: number; purchaseCount: number;
  periodFlow: Flow[]; monthlyFlow: MonthFlow[]; attentionItems: Attention[];
  activeProcurements?: ActiveProc[]; activeProcurementCount?: number; pendingPaymentAmount?: number
}

const router = useRouter()
const master = useMasterStore()
const now = new Date()
const period = ref<'all' | 'month' | 'year'>('all')
const selectedUnit = ref('all')
const loading = ref(true)
const error = ref('')
const data = ref<Dashboard>({
  itemTypes: 0, stockByUnit: [], lowStockTypes: 0, outStockTypes: 0, purchaseCount: 0,
  periodFlow: [], monthlyFlow: [], attentionItems: [], activeProcurements: [], activeProcurementCount: 0, pendingPaymentAmount: 0,
})
const totalRecordedNominal = ref(0)
const recentMovements = ref<Array<{
  id: number; occurred_at: string; movement_type: string; condition: string;
  quantity_delta: number; balance_after: number; notes: string | null;
  item_variants?: { size: string; items?: { code?: string; name: string; unit: string } | null } | null
}>>([])
let lastCacheVer = -1

// Drill-down History Modal state
const historyOpen = ref(false)
const historyLoading = ref(false)
const historyTitle = ref('')
const historySubtitle = ref('')
const historyEmpty = ref('')
const historyActionLabel = ref('')
const historyActionTarget = ref<{ name: string; query?: Record<string, string> } | null>(null)
const historyColumns = ref<HistoryColumn[]>([])
const historyRows = ref<Array<Record<string, HistoryCell>>>([])

const periodLabelText = computed(() => {
  if (period.value === 'month') {
    return new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric' }).format(now)
  }
  if (period.value === 'year') return `Tahun ${now.getFullYear()}`
  return 'Semua waktu'
})

const unitOptions = computed(() => [
  { value: 'all', label: 'Semua Satuan' },
  ...data.value.stockByUnit.map((e) => ({ value: e.unit, label: `Satuan: ${e.unit}` })),
])

const totalStockAllUnits = computed(() =>
  data.value.stockByUnit.reduce((s, e) => s + Number(e.quantity || 0), 0),
)

const totalAttentionCount = computed(() =>
  Number(data.value.lowStockTypes || 0) + Number(data.value.outStockTypes || 0),
)

const availableItemTypes = computed(() =>
  Math.max(0, Number(data.value.itemTypes || 0) - Number(data.value.outStockTypes || 0)),
)

const activeFlow = computed(() => {
  if (selectedUnit.value === 'all') {
    const incoming = data.value.periodFlow.reduce((s, f) => s + Number(f.incoming || 0), 0)
    const outgoing = data.value.periodFlow.reduce((s, f) => s + Number(f.outgoing || 0), 0)
    return { unit: 'unit', incoming, outgoing }
  }
  return (
    data.value.periodFlow.find((item) => item.unit === selectedUnit.value) || {
      unit: selectedUnit.value || 'unit',
      incoming: 0,
      outgoing: 0,
    }
  )
})

const chartRows = computed(() => {
  if (selectedUnit.value === 'all') {
    const order: string[] = []
    const map = new Map<string, { month: string; unit: string; incoming: number; outgoing: number }>()
    for (const row of data.value.monthlyFlow) {
      let entry = map.get(row.month)
      if (!entry) {
        entry = { month: row.month, unit: 'unit', incoming: 0, outgoing: 0 }
        map.set(row.month, entry)
        order.push(row.month)
      }
      entry.incoming += Number(row.incoming || 0)
      entry.outgoing += Number(row.outgoing || 0)
    }
    return order.map((m) => map.get(m)!)
  }
  return data.value.monthlyFlow.filter((item) => item.unit === selectedUnit.value)
})

const chartMax = computed(() => Math.max(1, ...chartRows.value.flatMap((row) => [Number(row.incoming), Number(row.outgoing)])))

function movementLabel(t: string) {
  const map: Record<string, string> = {
    opening_stock: 'Stok Awal', receipt: 'Barang Masuk', issuance: 'Barang Keluar',
    return: 'Pengembalian APD', stocktake_adjustment: 'Stok Opname', condition_transfer: 'Pindah Kondisi',
  }
  return map[t] || t
}

function movementIcon(t: string) {
  if (t === 'receipt' || t === 'opening_stock') return PackagePlus
  if (t === 'issuance') return PackageMinus
  if (t === 'return') return PackageCheck
  if (t === 'stocktake_adjustment') return ClipboardCheck
  if (t === 'condition_transfer') return ArrowRightLeft
  return Boxes
}

function matchesActivePeriod(dateStr?: string | null) {
  if (period.value === 'all' || !dateStr) return true
  const d = new Date(dateStr)
  if (Number.isNaN(d.getTime())) return true
  if (period.value === 'year') return d.getFullYear() === now.getFullYear()
  return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth()
}

async function openDashboardHistory(
  kind: 'available' | 'items' | 'incoming' | 'outgoing' | 'attention' | 'low' | 'out' | 'payments' | 'proc_detail' | 'item_movements',
  payload?: ActiveProc | Attention,
) {
  historyOpen.value = true
  historyLoading.value = true
  historyRows.value = []
  historyActionLabel.value = ''
  historyActionTarget.value = null

  try {
    if (kind === 'available' || kind === 'items' || kind === 'attention' || kind === 'low' || kind === 'out') {
      const res = await api<{
        data: Array<{
          variant_id: string; code: string; name: string; size: string; unit: string;
          stock_new: number; stock_used_good: number; stock_quarantine: number; stock_damaged: number;
          total_available: number; minimum_stock: number; stock_status: 'safe' | 'low' | 'out'
        }>
      }>('/api/inventory?page=1&limit=200')

      const list = res.data.filter((item) => {
        if (kind === 'available') return Number(item.total_available) > 0 && item.stock_status !== 'out'
        if (kind === 'attention') return item.stock_status === 'out' || item.stock_status === 'low'
        if (kind === 'low') return item.stock_status === 'low'
        if (kind === 'out') return item.stock_status === 'out'
        return true
      })

      historyTitle.value =
        kind === 'available'
          ? 'Daftar Barang Stok Siap Pakai (Tidak Habis)'
          : kind === 'attention'
            ? 'Barang Perlu Segera Dipesan (Habis & Menipis)'
            : kind === 'low'
              ? 'Daftar Stok Menipis'
              : kind === 'out'
                ? 'Daftar Stok Habis'
                : 'Daftar Seluruh Jenis Barang APD'
      historySubtitle.value =
        kind === 'available'
          ? 'Hanya menampilkan barang dengan stok tersedia (> 0) — tidak termasuk barang habis, karantina, atau rusak'
          : kind === 'items'
            ? 'Rincian stok siap pakai (Baru + Bekas Layak), karantina, dan rusak'
            : 'Daftar barang yang sudah habis atau mendekati batas minimum'
      historyEmpty.value =
        kind === 'available'
          ? 'Belum ada barang yang memiliki stok siap pakai.'
          : kind === 'items'
            ? 'Belum ada barang APD terdaftar.'
            : 'Semua stok saat ini aman!'
      historyActionLabel.value = 'Buka Stok Inventaris'
      historyActionTarget.value = { name: 'inventory', query: kind === 'items' ? undefined : kind === 'available' ? { status: 'safe' } : { status: kind } }
      historyColumns.value = [
        { key: 'item', label: 'Barang APD' },
        { key: 'available', label: 'Siap Pakai (Baru+Layak)' },
        { key: 'nonAvail', label: 'Karantina / Rusak' },
        { key: 'min', label: 'Min. Stok' },
        { key: 'status', label: 'Status' },
      ]
      historyRows.value = list.map((it) => ({
        item: { text: variantLabel(it), sub: it.code, strong: true },
        available: { text: `${formatNumber(it.total_available)} ${it.unit}`, sub: `Baru ${formatNumber(it.stock_new)} · Layak ${formatNumber(it.stock_used_good)}`, strong: true },
        nonAvail: `${formatNumber(it.stock_quarantine)} / ${formatNumber(it.stock_damaged)} ${it.unit}`,
        min: `${formatNumber(it.minimum_stock)} ${it.unit}`,
        status: {
          text: it.stock_status === 'safe' ? 'Aman' : it.stock_status === 'low' ? 'Menipis' : 'Habis',
          pill: it.stock_status,
        },
      }))
    } else if (kind === 'incoming') {
      const [purRes, openRes] = await Promise.all([
        api<{
          data: Array<{
            transaction_no: string; received_date: string; reason: string;
            suppliers?: { name: string } | null;
            purchase_items: Array<{ quantity: number; condition: string; item_variants?: { size: string; items?: { name: string; unit: string } | null } | null }>
          }>
        }>('/api/transactions/purchases'),
        api<{
          data: Array<{
            transaction_no: string; recorded_at: string; officer_name: string; notes: string | null;
            opening_stock_items: Array<{ quantity: number; condition: string; variant_id: string }>
          }>
        }>('/api/inventory/opening-stocks'),
      ])

      const rows: Array<Record<string, HistoryCell>> = []
      for (const p of purRes.data) {
        if (!matchesActivePeriod(p.received_date)) continue
        for (const it of p.purchase_items ?? []) {
          const unit = it.item_variants?.items?.unit || 'unit'
          if (selectedUnit.value !== 'all' && unit !== selectedUnit.value) continue
          rows.push({
            date: formatDate(p.received_date),
            doc: { text: p.transaction_no, sub: p.suppliers?.name || 'Penerimaan Barang', strong: true },
            item: { text: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }), sub: conditionLabel(it.condition) },
            qty: { text: `+${formatNumber(it.quantity)} ${unit}`, pill: 'plus' },
            note: p.reason || '-',
          })
        }
      }
      const varMap = new Map(master.variants.map((v) => [v.variant_id, v]))
      for (const op of openRes.data) {
        if (!matchesActivePeriod(op.recorded_at)) continue
        for (const it of op.opening_stock_items ?? []) {
          const v = varMap.get(it.variant_id)
          const unit = v?.unit || 'unit'
          if (selectedUnit.value !== 'all' && unit !== selectedUnit.value) continue
          rows.push({
            date: formatDate(op.recorded_at),
            doc: { text: op.transaction_no, sub: `Stok Awal · ${op.officer_name}`, strong: true },
            item: { text: v ? variantLabel(v) : 'Barang APD', sub: conditionLabel(it.condition) },
            qty: { text: `+${formatNumber(it.quantity)} ${unit}`, pill: 'plus' },
            note: op.notes || 'Saldo awal',
          })
        }
      }

      historyTitle.value = 'Riwayat Barang Masuk'
      historySubtitle.value = `Periode: ${periodLabelText.value} · ${selectedUnit.value === 'all' ? 'Semua satuan' : `Satuan ${selectedUnit.value}`}`
      historyEmpty.value = 'Belum ada transaksi barang masuk pada periode ini.'
      historyActionLabel.value = 'Buka Barang Masuk'
      historyActionTarget.value = { name: 'receipts' }
      historyColumns.value = [
        { key: 'date', label: 'Tanggal' },
        { key: 'doc', label: 'No. Dokumen & Sumber' },
        { key: 'item', label: 'Barang & Kondisi' },
        { key: 'qty', label: 'Masuk' },
        { key: 'note', label: 'Keterangan' },
      ]
      historyRows.value = rows
    } else if (kind === 'outgoing') {
      const res = await api<{
        data: Array<{
          transaction_no: string; issued_at: string; officer_name: string;
          employees?: { name: string; nik: string } | null;
          issuance_items: Array<{ quantity: number; condition: string; purpose: string; item_variants?: { size: string; items?: { name: string; unit: string } | null } | null }>
        }>
      }>('/api/transactions/issuances')

      const rows: Array<Record<string, HistoryCell>> = []
      for (const iss of res.data) {
        if (!matchesActivePeriod(iss.issued_at)) continue
        for (const it of iss.issuance_items ?? []) {
          const unit = it.item_variants?.items?.unit || 'unit'
          if (selectedUnit.value !== 'all' && unit !== selectedUnit.value) continue
          rows.push({
            date: formatDate(iss.issued_at),
            doc: { text: iss.transaction_no, sub: `Petugas: ${iss.officer_name}`, strong: true },
            employee: { text: iss.employees?.name || 'Karyawan', sub: iss.employees?.nik || '' },
            item: { text: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }), sub: conditionLabel(it.condition) },
            qty: { text: `-${formatNumber(it.quantity)} ${unit}`, pill: 'minus' },
            purpose: it.purpose || '-',
          })
        }
      }

      historyTitle.value = 'Riwayat Barang Keluar'
      historySubtitle.value = `Periode: ${periodLabelText.value} · ${selectedUnit.value === 'all' ? 'Semua satuan' : `Satuan ${selectedUnit.value}`}`
      historyEmpty.value = 'Belum ada transaksi barang keluar pada periode ini.'
      historyActionLabel.value = 'Buka Barang Keluar'
      historyActionTarget.value = { name: 'issuances' }
      historyColumns.value = [
        { key: 'date', label: 'Tanggal' },
        { key: 'doc', label: 'No. Transaksi' },
        { key: 'employee', label: 'Karyawan' },
        { key: 'item', label: 'Barang & Kondisi' },
        { key: 'qty', label: 'Keluar' },
        { key: 'purpose', label: 'Keperluan' },
      ]
      historyRows.value = rows
    } else if (kind === 'payments') {
      const res = await api<{
        data: Array<{
          procurement_no: string; po_number: string | null; procurement_date: string; status: string;
          funding_source?: string; payment_method?: string; total_amount: number; supplier_name?: string; reason?: string;
          suppliers?: { name: string } | null
        }>
      }>('/api/procurements')
      const recorded = res.data.filter((p) => p.status !== 'cancelled' && Number(p.total_amount || 0) > 0)

      historyTitle.value = 'History Pembayaran (Total Belanja Tercatat)'
      historySubtitle.value = `${recorded.length} pengadaan bernominal · Total ${formatCurrency(recorded.reduce((s, p) => s + Number(p.total_amount || 0), 0))}`
      historyEmpty.value = 'Belum ada nominal pengadaan yang tercatat.'
      historyActionLabel.value = 'Buka History Pembayaran'
      historyActionTarget.value = { name: 'payments' }
      historyColumns.value = [
        { key: 'doc', label: 'Kode Pengadaan / PO' },
        { key: 'supplier', label: 'Supplier / Toko' },
        { key: 'method', label: 'Sumber & Metode' },
        { key: 'total', label: 'Nominal' },
        { key: 'note', label: 'Keterangan' },
      ]
      historyRows.value = recorded.map((p) => ({
        doc: { text: p.procurement_no, sub: `${formatDate(p.procurement_date)}${p.po_number ? ` · PO: ${p.po_number}` : ''}`, strong: true },
        supplier: p.suppliers?.name || p.supplier_name || '-',
        method: { text: p.funding_source === 'advanced' ? 'Talangan' : 'Kas Perusahaan', sub: p.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer Bank' },
        total: { text: formatCurrency(p.total_amount), strong: true },
        note: p.reason || '-',
      }))
    } else if (kind === 'proc_detail' && payload && 'procurement_no' in payload) {
      const res = await api<{
        data: {
          procurement_no: string; po_number: string | null; supplier_name?: string;
          procurement_items: Array<{ ordered_quantity: number; received_quantity: number; unit_price: number; item_variants?: { size: string; items?: { name: string; unit: string } | null } | null }>
        }
      }>(`/api/procurements/${payload.id}`)

      historyTitle.value = `Detail Progress ${payload.procurement_no}`
      historySubtitle.value = `${payload.supplier_name}${payload.po_number ? ` · PO: ${payload.po_number}` : ''} · Progress ${payload.progress_percent}%`
      historyEmpty.value = 'Belum ada rincian barang pengadaan.'
      historyActionLabel.value = 'Buka Pengadaan Barang'
      historyActionTarget.value = { name: 'procurements' }
      historyColumns.value = [
        { key: 'item', label: 'Barang Dipesan' },
        { key: 'ordered', label: 'Dipesan' },
        { key: 'received', label: 'Sudah Masuk' },
        { key: 'remaining', label: 'Sisa Belum Datang' },
        { key: 'price', label: 'Harga Satuan' },
      ]
      historyRows.value = (res.data.procurement_items ?? []).map((it) => {
        const unit = it.item_variants?.items?.unit || 'unit'
        const rem = Math.max(0, Number(it.ordered_quantity) - Number(it.received_quantity))
        return {
          item: { text: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }), strong: true },
          ordered: `${formatNumber(it.ordered_quantity)} ${unit}`,
          received: { text: `${formatNumber(it.received_quantity)} ${unit}`, pill: 'safe' },
          remaining: { text: `${formatNumber(rem)} ${unit}`, pill: rem > 0 ? 'amber' : 'safe' },
          price: formatCurrency(it.unit_price),
        }
      })
    } else if (kind === 'item_movements' && payload && 'variant_id' in payload) {
      const res = await api<{
        data: Array<{ occurred_at: string; movement_type: string; condition: string; quantity_delta: number; balance_after: number; notes: string | null }>
      }>(`/api/inventory/movements/${payload.variant_id}`)
      historyTitle.value = `Riwayat Mutasi — ${variantLabel(payload)}`
      historySubtitle.value = `Kode ${payload.code} · Sisa ${formatNumber(payload.total_available)} ${payload.unit} (Min. ${formatNumber(payload.minimum_stock)} ${payload.unit})`
      historyEmpty.value = 'Belum ada riwayat mutasi untuk item ini.'
      historyActionLabel.value = 'Buka Stok Inventaris'
      historyActionTarget.value = { name: 'inventory', query: { status: payload.stock_status } }
      historyColumns.value = [
        { key: 'date', label: 'Tanggal' },
        { key: 'type', label: 'Aktivitas' },
        { key: 'cond', label: 'Kondisi' },
        { key: 'delta', label: 'Perubahan' },
        { key: 'after', label: 'Stok Akhir' },
        { key: 'note', label: 'Catatan' },
      ]
      historyRows.value = res.data.map((m) => ({
        date: formatDate(m.occurred_at),
        type: { text: movementLabel(m.movement_type), strong: true },
        cond: conditionLabel(m.condition),
        delta: { text: `${Number(m.quantity_delta) > 0 ? '+' : ''}${formatNumber(m.quantity_delta)} ${payload.unit}`, pill: Number(m.quantity_delta) >= 0 ? 'plus' : 'minus' },
        after: `${formatNumber(m.balance_after)} ${payload.unit}`,
        note: m.notes || '-',
      }))
    }
  } catch (e) {
    historyEmpty.value = e instanceof Error ? e.message : 'Gagal memuat riwayat data'
  } finally {
    historyLoading.value = false
  }
}

function goHistoryTarget() {
  if (!historyActionTarget.value) return
  historyOpen.value = false
  void router.push(historyActionTarget.value)
}

async function load(force = false) {
  if (force) invalidateApiCache()
  if (!data.value.itemTypes && !force) loading.value = true
  error.value = ''
  try {
    const m = now.getMonth() + 1
    const y = now.getFullYear()
    const [response, procRes, movRes] = await Promise.all([
      api<{ data: Dashboard }>(`/api/dashboard?period=${period.value}&month=${m}&year=${y}`),
      api<{ data: Array<{ status: string; total_amount: number }> }>('/api/procurements').catch(() => ({ data: [] })),
      api<{ data: typeof recentMovements.value }>('/api/inventory/movements?limit=6').catch(() => ({ data: [] })),
    ])
    data.value = response.data
    totalRecordedNominal.value = procRes.data
      .filter((p) => p.status !== 'cancelled')
      .reduce((s, p) => s + Number(p.total_amount || 0), 0)
    recentMovements.value = movRes.data
    lastCacheVer = getApiCacheVersion()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Dashboard tidak dapat dimuat'
  } finally {
    loading.value = false
  }
}

function prefetchRoute(name: 'inventory' | 'procurements' | 'receipts' | 'issuances') {
  master.refresh().catch(() => {})
  if (name === 'inventory') {
    void import('@/pages/InventoryPage.vue')
    prefetchApi('/api/inventory?page=1&limit=200&search=')
    prefetchApi('/api/inventory/opening-stocks')
  } else if (name === 'procurements') {
    void import('@/pages/ProcurementsPage.vue')
    prefetchApi('/api/procurements')
  } else if (name === 'receipts') {
    void import('@/pages/ReceiptsPage.vue')
    prefetchApi('/api/transactions/purchases')
    prefetchApi('/api/procurements')
  } else if (name === 'issuances') {
    void import('@/pages/IssuancesPage.vue')
    prefetchApi('/api/transactions/issuances')
  }
}

onMounted(() => {
  void load()
  master.refresh().catch(() => {})
})
onActivated(() => {
  if (getApiCacheVersion() !== lastCacheVer) void load()
})
watch(period, () => void load())
</script>

<template>
  <div class="dashboard-page">
    <section class="page-intro">
      <div>
        <p class="eyebrow">Ringkasan Gudang APD</p>
        <h2>Halo, ini kondisi gudang hari ini</h2>
        <p>Semua angka bisa langsung diklik untuk melihat rincian &amp; riwayat datanya.</p>
      </div>
      <div class="filter-group">
        <div class="period-pills" role="group" aria-label="Filter periode dashboard">
          <button type="button" :class="{ active: period === 'all' }" @click="period = 'all'">Semua</button>
          <button type="button" :class="{ active: period === 'month' }" @click="period = 'month'">Bulan Ini</button>
          <button type="button" :class="{ active: period === 'year' }" @click="period = 'year'">Tahun Ini</button>
        </div>
        <button class="secondary-button square" aria-label="Muat ulang" @click="load(true)"><RefreshCw :size="17" :class="{ spinning: loading }" /></button>
      </div>
    </section>

    <!-- Plain-Language One-Line Warehouse Health Summary -->
    <section class="dash-digest-banner" :class="{ warn: totalAttentionCount > 0 }">
      <div class="dash-digest-left">
        <AlertTriangle v-if="totalAttentionCount > 0" :size="18" />
        <CheckCircle2 v-else :size="18" />
        <p v-if="totalAttentionCount > 0">
          Ada <strong>{{ data.outStockTypes }} barang habis</strong> dan <strong>{{ data.lowStockTypes }} menipis</strong> yang perlu segera dipesan.
          Saat ini tersedia <strong>{{ formatNumber(totalStockAllUnits) }} unit</strong> ({{ availableItemTypes }} jenis tidak habis dari {{ data.itemTypes }} total item).
        </p>
        <p v-else>
          Semua stok aman! Tersedia <strong>{{ formatNumber(totalStockAllUnits) }} unit</strong> siap pakai dari <strong>{{ availableItemTypes }} jenis barang</strong>.
        </p>
      </div>
      <button v-if="totalAttentionCount > 0" type="button" class="secondary-button xs" @click="openDashboardHistory('attention')">
        Lihat {{ totalAttentionCount }} Barang →
      </button>
    </section>

    <section class="quick-actions-bar">
      <button class="quick-chip" @mouseenter="prefetchRoute('inventory')" @click="router.push({ name: 'inventory', query: { action: 'opening-stock' } })">
        <ClipboardList :size="16" /> Input Stok Awal
      </button>
      <button class="quick-chip" @mouseenter="prefetchRoute('procurements')" @click="router.push({ name: 'procurements', query: { action: 'new' } })">
        <ShoppingBag :size="16" /> Buat Pengadaan
      </button>
      <button class="quick-chip" @mouseenter="prefetchRoute('receipts')" @click="router.push({ name: 'receipts', query: { action: 'new' } })">
        <PackagePlus :size="16" /> Catat Barang Masuk
      </button>
      <button class="quick-chip" @mouseenter="prefetchRoute('issuances')" @click="router.push({ name: 'issuances', query: { action: 'new' } })">
        <PackageMinus :size="16" /> Catat Barang Keluar
      </button>
    </section>

    <div v-if="error" class="inline-alert"><AlertTriangle :size="18" />{{ error }}<button @click="load(true)">Coba lagi</button></div>

    <!-- 4 Big, Spacious, Easy-to-Read KPI Cards -->
    <section class="stats-grid stats-grid-4">
      <StatCard
        label="Stok Siap Pakai"
        :value="`${formatNumber(totalStockAllUnits)} unit`"
        :hint="`${availableItemTypes} jenis tidak habis · Klik lihat daftar`"
        value-tone="teal"
        :icon="Boxes"
        :flaticon-icon="flaticonAssets.warehouse"
        clickable
        @click="openDashboardHistory('available')"
      />
      <StatCard
        label="Total Barang Masuk"
        :value="`+${formatNumber(activeFlow.incoming)} ${activeFlow.unit}`"
        :hint="`Periode: ${periodLabelText} · Klik riwayat`"
        value-tone="teal"
        :icon="ArrowDownToLine"
        :flaticon-icon="flaticonAssets.box"
        clickable
        @click="openDashboardHistory('incoming')"
      />
      <StatCard
        label="Total Barang Keluar"
        :value="`-${formatNumber(activeFlow.outgoing)} ${activeFlow.unit}`"
        :hint="`Periode: ${periodLabelText} · Klik riwayat`"
        :icon="ArrowUpFromLine"
        :flaticon-icon="flaticonAssets.shield"
        clickable
        @click="openDashboardHistory('outgoing')"
      />
      <StatCard
        label="Perlu Segera Dipesan"
        :value="`${totalAttentionCount} barang`"
        :hint="`${data.outStockTypes} habis · ${data.lowStockTypes} menipis · Klik lihat`"
        :value-tone="data.outStockTypes > 0 ? 'red' : data.lowStockTypes > 0 ? 'amber' : 'teal'"
        :icon="AlertTriangle"
        :flaticon-icon="flaticonAssets.warning"
        clickable
        @click="openDashboardHistory('attention')"
      />
    </section>

    <section class="dashboard-grid">
      <article class="panel chart-panel">
        <div class="panel-header">
          <div>
            <h3>Grafik Masuk vs Keluar ({{ now.getFullYear() }})</h3>
            <p>Perbandingan barang masuk dan keluar tiap bulan ({{ selectedUnit === 'all' ? 'semua satuan' : `satuan ${selectedUnit}` }})</p>
          </div>
          <ModernSelect v-model="selectedUnit" :options="unitOptions" compact :searchable="false" />
        </div>
        <div class="chart-legend"><span><i class="incoming" />Masuk (Hijau Tua)</span><span><i class="outgoing" />Keluar (Hijau Muda)</span></div>
        <div v-if="chartRows.length" class="bar-chart">
          <div v-for="row in chartRows" :key="row.month" class="bar-group">
            <div class="bars">
              <span class="bar incoming" :style="{ height: `${Math.max(2, Number(row.incoming) / chartMax * 100)}%` }" :title="`Masuk ${row.incoming} ${row.unit}`">
                <em v-if="Number(row.incoming) > 0" class="bar-val">{{ formatNumber(row.incoming) }}</em>
              </span>
              <span class="bar outgoing" :style="{ height: `${Math.max(2, Number(row.outgoing) / chartMax * 100)}%` }" :title="`Keluar ${row.outgoing} ${row.unit}`">
                <em v-if="Number(row.outgoing) > 0" class="bar-val">{{ formatNumber(row.outgoing) }}</em>
              </span>
            </div>
            <small>{{ row.month }}</small>
          </div>
        </div>
        <div v-else class="empty-state compact">Belum ada data pergerakan. Mulai dengan Input Stok Awal atau Barang Masuk.</div>
      </article>

      <article class="panel stock-summary-panel">
        <div class="panel-header">
          <div><h3>Rincian Stok per Satuan</h3><p>Klik satuan untuk filter grafik di sebelah</p></div>
          <Boxes :size="20" />
        </div>
        <div class="unit-list">
          <button :class="{ active: selectedUnit === 'all' }" @click="selectedUnit = 'all'">
            <span>Semua Satuan</span><strong>{{ formatNumber(totalStockAllUnits) }}</strong><small>Total gabungan siap pakai</small>
          </button>
          <button v-for="entry in data.stockByUnit" :key="entry.unit" :class="{ active: selectedUnit === entry.unit }" @click="selectedUnit = entry.unit">
            <span>{{ entry.unit }}</span><strong>{{ formatNumber(entry.quantity) }}</strong><small>Siap pakai (Baru + Layak)</small>
          </button>
          <div v-if="!data.stockByUnit.length" class="empty-state compact">Belum ada saldo stok.</div>
        </div>
        <button type="button" class="purchase-strip clickable-strip" @click="openDashboardHistory('payments')">
          <span><Wallet :size="18" /></span>
          <div>
            <small>Total Belanja Tercatat (History Pembayaran)</small>
            <strong>{{ formatCurrency(totalRecordedNominal) }}</strong>
          </div>
        </button>
      </article>
    </section>

    <section class="dashboard-bottom-grid">
      <article class="panel attention-panel">
        <div class="panel-header">
          <div><h3>Barang Habis &amp; Menipis</h3><p>Klik barang untuk lihat riwayat keluar/masuknya</p></div>
          <RouterLink :to="{ name: 'inventory', query: { status: 'attention' } }">Semua stok →</RouterLink>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Nama Barang</th><th>Sisa Stok</th><th>Minimal</th><th>Status</th></tr></thead>
            <tbody>
              <tr v-for="item in data.attentionItems" :key="item.variant_id" class="clickable-tr" @click="openDashboardHistory('item_movements', item)">
                <td>
                  <span class="item-cell">
                    <i>{{ item.name.slice(0, 2).toUpperCase() }}</i>
                    <span>
                      <strong>{{ variantLabel(item) }}</strong>
                      <small>{{ item.code }}</small>
                    </span>
                  </span>
                </td>
                <td><strong :class="item.stock_status === 'out' ? 'text-red' : 'text-amber'">{{ formatNumber(item.total_available) }} {{ item.unit }}</strong></td>
                <td>{{ formatNumber(item.minimum_stock) }} {{ item.unit }}</td>
                <td><span class="status-pill" :class="item.stock_status">{{ item.stock_status === 'out' ? 'Habis' : 'Menipis' }}</span></td>
              </tr>
              <tr v-if="!data.attentionItems.length"><td colspan="4"><div class="empty-state compact">Semua stok berada dalam batas aman.</div></td></tr>
            </tbody>
          </table>
        </div>
      </article>

      <article class="panel attention-panel">
        <div class="panel-header">
          <div><h3>Pengadaan Sedang Berjalan</h3><p>Barang yang sudah dipesan dan ditunggu kedatangannya</p></div>
          <RouterLink :to="{ name: 'procurements' }">Kelola PO →</RouterLink>
        </div>
        <div class="proc-mini-list">
          <button
            v-for="proc in data.activeProcurements"
            :key="proc.id"
            type="button"
            class="proc-mini-row clickable-row"
            @click="openDashboardHistory('proc_detail', proc)"
          >
            <div>
              <strong>{{ proc.procurement_no }} <span v-if="proc.po_number" class="tag-pill">PO: {{ proc.po_number }}</span></strong>
              <small>{{ proc.supplier_name }} · Masuk {{ formatNumber(proc.total_received) }} dari {{ formatNumber(proc.total_ordered) }} unit</small>
            </div>
            <div class="proc-mini-bar">
              <div class="progress-track"><div class="progress-fill" :style="{ width: `${proc.progress_percent}%` }" /></div>
              <span>{{ proc.progress_percent }}%</span>
            </div>
          </button>
          <div v-if="!data.activeProcurements?.length" class="empty-state compact">Tidak ada pengadaan yang sedang menunggu kedatangan barang.</div>
        </div>
      </article>
    </section>

    <section class="panel" style="margin-top:16px;padding:18px 20px;">
      <div class="panel-header">
        <div>
          <h3>Pergerakan &amp; Aktivitas Terbaru</h3>
          <p>6 aktivitas keluar/masuk stok terakhir di gudang</p>
        </div>
        <RouterLink :to="{ name: 'reports' }">Lihat semua di Laporan →</RouterLink>
      </div>
      <ul v-if="recentMovements.length" class="activity-feed-list compact" style="margin-top:12px;">
        <li v-for="m in recentMovements" :key="m.id" class="activity-feed-item">
          <span class="activity-feed-icon">
            <component :is="movementIcon(m.movement_type)" :size="16" />
          </span>
          <div class="activity-feed-body">
            <div class="activity-feed-top">
              <strong>{{ variantLabel({ name: m.item_variants?.items?.name || 'Barang APD', size: m.item_variants?.size }) }}</strong>
              <span class="tag-pill">{{ movementLabel(m.movement_type) }}</span>
              <span class="tag-pill">{{ conditionLabel(m.condition) }}</span>
            </div>
            <p class="activity-feed-meta">
              <span>{{ formatDate(m.occurred_at) }}</span>
              <span v-if="m.notes" class="activity-feed-dot">·</span>
              <span v-if="m.notes">{{ m.notes }}</span>
            </p>
          </div>
          <div class="activity-feed-numbers">
            <span class="delta-pill" :class="Number(m.quantity_delta) >= 0 ? 'plus' : 'minus'">
              {{ Number(m.quantity_delta) >= 0 ? '+' : '' }}{{ formatNumber(m.quantity_delta) }} {{ m.item_variants?.items?.unit || '' }}
            </span>
            <small>Stok Akhir: <strong>{{ formatNumber(m.balance_after) }} {{ m.item_variants?.items?.unit || '' }}</strong></small>
          </div>
        </li>
      </ul>
      <div v-else class="empty-state compact">Belum ada aktivitas mutasi stok tercatat.</div>
    </section>

    <StatHistoryModal
      :open="historyOpen"
      :title="historyTitle"
      :subtitle="historySubtitle"
      :loading="historyLoading"
      :columns="historyColumns"
      :rows="historyRows"
      :empty-text="historyEmpty"
      :action-label="historyActionLabel"
      @close="historyOpen = false"
      @action="goHistoryTarget"
    />
  </div>
</template>
