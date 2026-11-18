<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ChevronLeft, ChevronRight, Download, Filter, History, PackageOpen, Plus, Search, SlidersHorizontal } from '@lucide/vue'
import { api, formatNumber } from '@/lib/api'

type StockRow = {
  variant_id: string; code: string; name: string; category_name: string; size: string; unit: string;
  stock_new: number; stock_used_good: number; stock_quarantine: number; stock_damaged: number;
  total_available: number; minimum_stock: number; stock_status: 'safe' | 'low' | 'out'
}

const rows = ref<StockRow[]>([])
const search = ref('')
const debouncedSearch = ref('')
const status = ref('all')
const page = ref(1)
const totalPages = ref(1)
const total = ref(0)
const loading = ref(true)
let timer: number | undefined

const filteredRows = computed(() => status.value === 'all' ? rows.value : rows.value.filter((row) => row.stock_status === status.value))

async function load() {
  loading.value = true
  try {
    const result = await api<{ data: StockRow[]; pagination: { total: number; totalPages: number } }>(`/api/inventory?page=${page.value}&limit=20&search=${encodeURIComponent(debouncedSearch.value)}`)
    rows.value = result.data; total.value = result.pagination.total; totalPages.value = result.pagination.totalPages
  } finally { loading.value = false }
}

function exportCsv() {
  const header = ['Kode','Nama','Kategori','Ukuran','Satuan','Baru','Bekas Layak','Karantina','Rusak','Tersedia','Minimum','Status']
  const lines = filteredRows.value.map((row) => [row.code,row.name,row.category_name,row.size,row.unit,row.stock_new,row.stock_used_good,row.stock_quarantine,row.stock_damaged,row.total_available,row.minimum_stock,row.stock_status])
  const csv = [header, ...lines].map((line) => line.map((value) => `"${String(value).replaceAll('"','""')}"`).join(',')).join('\n')
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a'); link.href = url; link.download = `stok-inventaris-${new Date().toISOString().slice(0,10)}.csv`; link.click(); URL.revokeObjectURL(url)
}

watch(search, (value) => { window.clearTimeout(timer); timer = window.setTimeout(() => { debouncedSearch.value = value; page.value = 1 }, 350) })
watch([debouncedSearch, page], load)
onMounted(load)
</script>

<template>
  <div>
    <section class="page-intro">
      <div><p class="eyebrow">Saldo terkini</p><h2>Stok Inventaris</h2><p>Saldo per barang, ukuran, dan kondisi dengan riwayat mutasi lengkap.</p></div>
      <div class="intro-actions"><button class="secondary-button" @click="exportCsv"><Download :size="17" /> Ekspor CSV</button><button class="primary-button"><Plus :size="18" /> Tambah barang</button></div>
    </section>

    <section class="mini-stats">
      <div><span class="mini-icon teal"><PackageOpen :size="19" /></span><p>Total varian<strong>{{ total }}</strong></p></div>
      <div><span class="mini-icon amber"><Filter :size="19" /></span><p>Menipis<strong>{{ rows.filter(r => r.stock_status === 'low').length }}</strong></p></div>
      <div><span class="mini-icon red"><SlidersHorizontal :size="19" /></span><p>Habis<strong>{{ rows.filter(r => r.stock_status === 'out').length }}</strong></p></div>
    </section>

    <section class="panel data-panel">
      <div class="table-toolbar">
        <label class="search-field"><Search :size="18" /><input v-model="search" placeholder="Cari kode, nama, atau kategori..." /></label>
        <select v-model="status" class="compact-select"><option value="all">Semua status</option><option value="safe">Aman</option><option value="low">Menipis</option><option value="out">Habis</option></select>
      </div>
      <div class="table-wrap inventory-table"><table><thead><tr><th>Barang</th><th>Kategori / Ukuran</th><th>Baru</th><th>Bekas layak</th><th>Karantina</th><th>Rusak</th><th>Total tersedia</th><th>Status</th><th /></tr></thead><tbody>
        <tr v-for="row in filteredRows" :key="row.variant_id"><td><span class="item-cell"><i>{{ row.name.slice(0, 2).toUpperCase() }}</i><span><strong>{{ row.name }}</strong><small>{{ row.code }}</small></span></span></td><td><strong class="table-main">{{ row.category_name }}</strong><small class="table-sub">Ukuran {{ row.size }}</small></td><td>{{ formatNumber(row.stock_new) }} <small>{{ row.unit }}</small></td><td>{{ formatNumber(row.stock_used_good) }} <small>{{ row.unit }}</small></td><td>{{ formatNumber(row.stock_quarantine) }} <small>{{ row.unit }}</small></td><td>{{ formatNumber(row.stock_damaged) }} <small>{{ row.unit }}</small></td><td><strong>{{ formatNumber(row.total_available) }}</strong> {{ row.unit }}</td><td><span class="status-pill" :class="row.stock_status">{{ row.stock_status === 'safe' ? 'Aman' : row.stock_status === 'low' ? 'Menipis' : 'Habis' }}</span></td><td><button class="icon-button" title="Riwayat mutasi"><History :size="17" /></button></td></tr>
        <tr v-if="!loading && !filteredRows.length"><td colspan="9"><div class="empty-state"><PackageOpen :size="32" /><strong>Belum ada stok yang cocok</strong><span>Ubah pencarian atau tambahkan master barang baru.</span></div></td></tr>
        <tr v-if="loading"><td colspan="9"><div class="loading-row">Memuat saldo inventaris...</div></td></tr>
      </tbody></table></div>
      <footer class="table-footer"><span>Menampilkan {{ filteredRows.length }} dari {{ total }} varian</span><div><button class="icon-button" :disabled="page <= 1" @click="page--"><ChevronLeft :size="18" /></button><span>Halaman {{ page }} / {{ Math.max(1, totalPages) }}</span><button class="icon-button" :disabled="page >= totalPages" @click="page++"><ChevronRight :size="18" /></button></div></footer>
    </section>
  </div>
</template>
