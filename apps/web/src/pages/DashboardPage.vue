<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { AlertTriangle, ArrowDownToLine, ArrowUpFromLine, Boxes, CalendarDays, PackageX, RefreshCw, ShoppingCart } from '@lucide/vue'
import StatCard from '@/components/StatCard.vue'
import { api, formatNumber } from '@/lib/api'

type Flow = { unit: string; incoming: number; outgoing: number }
type MonthFlow = Flow & { month: string }
type Attention = { variant_id: string; code: string; name: string; size: string; unit: string; total_available: number; minimum_stock: number; stock_status: 'low' | 'out' }
type Dashboard = {
  itemTypes: number; stockByUnit: Array<{ unit: string; quantity: number }>;
  lowStockTypes: number; outStockTypes: number; purchaseCount: number;
  periodFlow: Flow[]; monthlyFlow: MonthFlow[]; attentionItems: Attention[]
}

const now = new Date()
const month = ref(now.getMonth() + 1)
const year = ref(now.getFullYear())
const selectedUnit = ref('')
const loading = ref(true)
const error = ref('')
const data = ref<Dashboard>({ itemTypes: 0, stockByUnit: [], lowStockTypes: 0, outStockTypes: 0, purchaseCount: 0, periodFlow: [], monthlyFlow: [], attentionItems: [] })
const months = ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember']

const activeFlow = computed(() => data.value.periodFlow.find((item) => item.unit === selectedUnit.value) || { unit: selectedUnit.value || '—', incoming: 0, outgoing: 0 })
const chartRows = computed(() => data.value.monthlyFlow.filter((item) => item.unit === selectedUnit.value))
const chartMax = computed(() => Math.max(1, ...chartRows.value.flatMap((row) => [Number(row.incoming), Number(row.outgoing)])))

async function load() {
  loading.value = true; error.value = ''
  try {
    const response = await api<{ data: Dashboard }>(`/api/dashboard?month=${month.value}&year=${year.value}`)
    data.value = response.data
    if (!selectedUnit.value || !data.value.stockByUnit.some((x) => x.unit === selectedUnit.value)) selectedUnit.value = data.value.stockByUnit[0]?.unit || ''
  } catch (e) { error.value = e instanceof Error ? e.message : 'Dashboard tidak dapat dimuat' }
  finally { loading.value = false }
}

onMounted(load)
watch([month, year], load)
</script>

<template>
  <div class="dashboard-page">
    <section class="page-intro">
      <div><p class="eyebrow">Ringkasan operasional</p><h2>Selamat datang kembali</h2><p>Pantau stok dan pergerakan APD tanpa mencampur satuan barang.</p></div>
      <div class="filter-group">
        <label><CalendarDays :size="17" /><select v-model="month"><option v-for="(name, index) in months" :key="name" :value="index + 1">{{ name }}</option></select></label>
        <label><select v-model="year"><option v-for="value in [year - 1, year, year + 1]" :key="value" :value="value">{{ value }}</option></select></label>
        <button class="secondary-button square" aria-label="Muat ulang" @click="load"><RefreshCw :size="17" :class="{ spinning: loading }" /></button>
      </div>
    </section>

    <div v-if="error" class="inline-alert"><AlertTriangle :size="18" />{{ error }}<button @click="load">Coba lagi</button></div>

    <section class="stats-grid">
      <StatCard label="Jenis barang" :value="data.itemTypes" hint="Item aktif terdaftar" :icon="Boxes" tone="teal" />
      <StatCard label="Barang masuk" :value="`${formatNumber(activeFlow.incoming)} ${activeFlow.unit}`" :hint="`Periode ${months[month - 1]}`" :icon="ArrowDownToLine" tone="blue" />
      <StatCard label="Barang keluar" :value="`${formatNumber(activeFlow.outgoing)} ${activeFlow.unit}`" :hint="`Periode ${months[month - 1]}`" :icon="ArrowUpFromLine" tone="violet" />
      <StatCard label="Stok menipis" :value="data.lowStockTypes" hint="Perlu perhatian" :icon="AlertTriangle" tone="amber" />
      <StatCard label="Stok habis" :value="data.outStockTypes" hint="Perlu pengadaan" :icon="PackageX" tone="red" />
    </section>

    <section class="dashboard-grid">
      <article class="panel chart-panel">
        <div class="panel-header"><div><h3>Pergerakan stok {{ year }}</h3><p>Barang masuk dan keluar per bulan</p></div><select v-model="selectedUnit" class="compact-select"><option v-for="entry in data.stockByUnit" :key="entry.unit" :value="entry.unit">Satuan: {{ entry.unit }}</option></select></div>
        <div class="chart-legend"><span><i class="incoming" />Masuk</span><span><i class="outgoing" />Keluar</span></div>
        <div v-if="chartRows.length" class="bar-chart">
          <div v-for="row in chartRows" :key="row.month" class="bar-group">
            <div class="bars"><span class="bar incoming" :style="{ height: `${Math.max(2, Number(row.incoming) / chartMax * 100)}%` }" :title="`Masuk ${row.incoming} ${row.unit}`" /><span class="bar outgoing" :style="{ height: `${Math.max(2, Number(row.outgoing) / chartMax * 100)}%` }" :title="`Keluar ${row.outgoing} ${row.unit}`" /></div>
            <small>{{ row.month }}</small>
          </div>
        </div>
        <div v-else class="empty-state compact">Belum ada data pergerakan untuk satuan ini.</div>
      </article>

      <article class="panel stock-summary-panel">
        <div class="panel-header"><div><h3>Stok tersedia</h3><p>Rincian per satuan</p></div><Boxes :size="20" /></div>
        <div class="unit-list">
          <button v-for="entry in data.stockByUnit" :key="entry.unit" :class="{ active: selectedUnit === entry.unit }" @click="selectedUnit = entry.unit">
            <span>{{ entry.unit }}</span><strong>{{ formatNumber(entry.quantity) }}</strong><small>baru + bekas layak</small>
          </button>
          <div v-if="!data.stockByUnit.length" class="empty-state compact">Belum ada saldo stok.</div>
        </div>
        <div class="purchase-strip"><span><ShoppingCart :size="18" /></span><div><small>Transaksi pembelian bulan ini</small><strong>{{ data.purchaseCount }} transaksi</strong></div></div>
      </article>
    </section>

    <section class="panel attention-panel">
      <div class="panel-header"><div><h3>Stok yang perlu perhatian</h3><p>Item menipis dan habis berdasarkan batas minimum</p></div><RouterLink :to="{ name: 'inventory' }">Lihat seluruh stok →</RouterLink></div>
      <div class="table-wrap"><table><thead><tr><th>Barang</th><th>Ukuran</th><th>Stok tersedia</th><th>Minimum</th><th>Status</th></tr></thead><tbody>
        <tr v-for="item in data.attentionItems" :key="item.variant_id"><td><span class="item-cell"><i>{{ item.name.slice(0, 2).toUpperCase() }}</i><span><strong>{{ item.name }}</strong><small>{{ item.code }}</small></span></span></td><td>{{ item.size }}</td><td><strong>{{ formatNumber(item.total_available) }}</strong> {{ item.unit }}</td><td>{{ formatNumber(item.minimum_stock) }} {{ item.unit }}</td><td><span class="status-pill" :class="item.stock_status">{{ item.stock_status === 'out' ? 'Habis' : 'Menipis' }}</span></td></tr>
        <tr v-if="!data.attentionItems.length"><td colspan="5"><div class="empty-state compact">Semua stok berada dalam batas aman.</div></td></tr>
      </tbody></table></div>
    </section>
  </div>
</template>
