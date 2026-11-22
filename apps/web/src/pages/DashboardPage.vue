<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  AlertTriangle, ArrowDownToLine, ArrowUpFromLine, Boxes, CalendarDays,
  ClipboardList, PackageMinus, PackagePlus, PackageX, RefreshCw, ShoppingBag, Wallet,
} from '@lucide/vue'
import ModernSelect from '@/components/ModernSelect.vue'
import StatCard from '@/components/StatCard.vue'
import { api, formatCurrency, formatNumber } from '@/lib/api'
import { flaticonAssets } from '@/lib/icons'

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
const now = new Date()
const month = ref(now.getMonth() + 1)
const year = ref(now.getFullYear())
const selectedUnit = ref('')
const loading = ref(true)
const error = ref('')
const data = ref<Dashboard>({
  itemTypes: 0, stockByUnit: [], lowStockTypes: 0, outStockTypes: 0, purchaseCount: 0,
  periodFlow: [], monthlyFlow: [], attentionItems: [], activeProcurements: [], activeProcurementCount: 0, pendingPaymentAmount: 0,
})
const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember']

const monthOptions = months.map((name, index) => ({ value: index + 1, label: name }))
const yearOptions = computed(() => [year.value - 1, year.value, year.value + 1].map((v) => ({ value: v, label: String(v) })))
const unitOptions = computed(() => data.value.stockByUnit.map((e) => ({ value: e.unit, label: `Satuan: ${e.unit}` })))

const activeFlow = computed(() => data.value.periodFlow.find((item) => item.unit === selectedUnit.value) || { unit: selectedUnit.value || '—', incoming: 0, outgoing: 0 })
const chartRows = computed(() => data.value.monthlyFlow.filter((item) => item.unit === selectedUnit.value))
const chartMax = computed(() => Math.max(1, ...chartRows.value.flatMap((row) => [Number(row.incoming), Number(row.outgoing)])))

async function load() {
  loading.value = true; error.value = ''
  try {
    const response = await api<{ data: Dashboard }>(`/api/dashboard?month=${month.value}&year=${year.value}`)
    data.value = response.data
    if (!selectedUnit.value || !data.value.stockByUnit.some((x) => x.unit === selectedUnit.value)) {
      selectedUnit.value = data.value.stockByUnit[0]?.unit || ''
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Dashboard tidak dapat dimuat'
  } finally {
    loading.value = false
  }
}

onMounted(load)
watch([month, year], load)
</script>

<template>
  <div class="dashboard-page">
    <section class="page-intro">
      <div>
        <p class="eyebrow">Ringkasan operasional</p>
        <h2>Selamat datang kembali</h2>
        <p>Pantau stok APD, pengadaan berjalan, penerimaan barang, dan tanggungan karyawan secara real-time.</p>
      </div>
      <div class="filter-group">
        <span class="filter-icon-pill"><CalendarDays :size="16" /></span>
        <ModernSelect v-model="month" :options="monthOptions" compact :searchable="false" />
        <ModernSelect v-model="year" :options="yearOptions" compact :searchable="false" />
        <button class="secondary-button square" aria-label="Muat ulang" @click="load"><RefreshCw :size="17" :class="{ spinning: loading }" /></button>
      </div>
    </section>

    <section class="quick-actions-bar">
      <button class="quick-chip" @click="router.push({ name: 'inventory', query: { action: 'opening-stock' } })">
        <ClipboardList :size="16" /> Input Stok Awal
      </button>
      <button class="quick-chip" @click="router.push({ name: 'procurements', query: { action: 'new' } })">
        <ShoppingBag :size="16" /> Buat Pengadaan Barang
      </button>
      <button class="quick-chip" @click="router.push({ name: 'receipts', query: { action: 'new' } })">
        <PackagePlus :size="16" /> Catat Barang Masuk
      </button>
      <button class="quick-chip" @click="router.push({ name: 'issuances', query: { action: 'new' } })">
        <PackageMinus :size="16" /> Catat Barang Keluar
      </button>
    </section>

    <div v-if="error" class="inline-alert"><AlertTriangle :size="18" />{{ error }}<button @click="load">Coba lagi</button></div>

    <section class="stats-grid">
      <StatCard label="Jenis barang" :value="data.itemTypes" hint="Master APD aktif" :icon="Boxes" :flaticon-icon="flaticonAssets.warehouse" tone="teal" />
      <StatCard label="Barang masuk" :value="`${formatNumber(activeFlow.incoming)} ${activeFlow.unit}`" :hint="`Periode ${months[month - 1]}`" :icon="ArrowDownToLine" :flaticon-icon="flaticonAssets.box" tone="blue" />
      <StatCard label="Barang keluar" :value="`${formatNumber(activeFlow.outgoing)} ${activeFlow.unit}`" :hint="`Periode ${months[month - 1]}`" :icon="ArrowUpFromLine" :flaticon-icon="flaticonAssets.shield" tone="violet" />
      <StatCard label="Stok menipis" :value="data.lowStockTypes" hint="Segera buat pengadaan" :icon="AlertTriangle" :flaticon-icon="flaticonAssets.warning" tone="amber" />
      <StatCard label="Stok habis" :value="data.outStockTypes" hint="Varian kosong" :icon="PackageX" :flaticon-icon="flaticonAssets.quarantine" tone="red" />
    </section>

    <section class="dashboard-grid">
      <article class="panel chart-panel">
        <div class="panel-header">
          <div><h3>Pergerakan stok {{ year }}</h3><p>Barang masuk (termasuk stok awal) vs barang keluar per bulan</p></div>
          <ModernSelect v-if="unitOptions.length" v-model="selectedUnit" :options="unitOptions" compact :searchable="false" />
        </div>
        <div class="chart-legend"><span><i class="incoming" />Masuk</span><span><i class="outgoing" />Keluar</span></div>
        <div v-if="chartRows.length" class="bar-chart">
          <div v-for="row in chartRows" :key="row.month" class="bar-group">
            <div class="bars">
              <span class="bar incoming" :style="{ height: `${Math.max(2, Number(row.incoming) / chartMax * 100)}%` }" :title="`Masuk ${row.incoming} ${row.unit}`" />
              <span class="bar outgoing" :style="{ height: `${Math.max(2, Number(row.outgoing) / chartMax * 100)}%` }" :title="`Keluar ${row.outgoing} ${row.unit}`" />
            </div>
            <small>{{ row.month }}</small>
          </div>
        </div>
        <div v-else class="empty-state compact">Belum ada data pergerakan. Mulai dengan Input Stok Awal atau Barang Masuk.</div>
      </article>

      <article class="panel stock-summary-panel">
        <div class="panel-header"><div><h3>Stok tersedia</h3><p>Rincian per satuan</p></div><Boxes :size="20" /></div>
        <div class="unit-list">
          <button v-for="entry in data.stockByUnit" :key="entry.unit" :class="{ active: selectedUnit === entry.unit }" @click="selectedUnit = entry.unit">
            <span>{{ entry.unit }}</span><strong>{{ formatNumber(entry.quantity) }}</strong><small>baru + bekas layak</small>
          </button>
          <div v-if="!data.stockByUnit.length" class="empty-state compact">Belum ada saldo stok.</div>
        </div>
        <div class="purchase-strip">
          <span><Wallet :size="18" /></span>
          <div>
            <small>Tagihan pengadaan belum lunas</small>
            <strong>{{ formatCurrency(data.pendingPaymentAmount || 0) }}</strong>
          </div>
        </div>
      </article>
    </section>

    <section class="dashboard-bottom-grid">
      <article class="panel attention-panel">
        <div class="panel-header">
          <div><h3>Progress Pengadaan Berjalan</h3><p>Pengadaan yang sedang menunggu kedatangan barang</p></div>
          <RouterLink :to="{ name: 'procurements' }">Kelola pengadaan →</RouterLink>
        </div>
        <div class="proc-mini-list">
          <div v-for="proc in data.activeProcurements" :key="proc.id" class="proc-mini-row">
            <div>
              <strong>{{ proc.procurement_no }} <span v-if="proc.po_number" class="tag-pill">PO: {{ proc.po_number }}</span></strong>
              <small>{{ proc.supplier_name }} · {{ formatNumber(proc.total_received) }} / {{ formatNumber(proc.total_ordered) }} unit</small>
            </div>
            <div class="proc-mini-bar">
              <div class="progress-track"><div class="progress-fill" :style="{ width: `${proc.progress_percent}%` }" /></div>
              <span>{{ proc.progress_percent }}%</span>
            </div>
          </div>
          <div v-if="!data.activeProcurements?.length" class="empty-state compact">Tidak ada pengadaan yang sedang menunggu barang.</div>
        </div>
      </article>

      <article class="panel attention-panel">
        <div class="panel-header">
          <div><h3>Stok yang perlu perhatian</h3><p>Item menipis dan habis berdasarkan batas minimum</p></div>
          <RouterLink :to="{ name: 'inventory' }">Lihat seluruh stok →</RouterLink>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Barang</th><th>Ukuran</th><th>Tersedia</th><th>Min</th><th>Status</th></tr></thead>
            <tbody>
              <tr v-for="item in data.attentionItems" :key="item.variant_id">
                <td><span class="item-cell"><i>{{ item.name.slice(0, 2).toUpperCase() }}</i><span><strong>{{ item.name }}</strong><small>{{ item.code }}</small></span></span></td>
                <td>{{ item.size && item.size !== '-' ? item.size : 'Standar' }}</td>
                <td><strong>{{ formatNumber(item.total_available) }}</strong> {{ item.unit }}</td>
                <td>{{ formatNumber(item.minimum_stock) }} {{ item.unit }}</td>
                <td><span class="status-pill" :class="item.stock_status">{{ item.stock_status === 'out' ? 'Habis' : 'Menipis' }}</span></td>
              </tr>
              <tr v-if="!data.attentionItems.length"><td colspan="5"><div class="empty-state compact">Semua stok berada dalam batas aman.</div></td></tr>
            </tbody>
          </table>
        </div>
      </article>
    </section>
  </div>
</template>
