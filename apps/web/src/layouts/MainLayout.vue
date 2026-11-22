<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowUpRight, Bell, Boxes, CalendarDays, ClipboardCheck, Clock, FileBarChart, LayoutDashboard, Menu,
  PackageCheck, PackageMinus, PackagePlus, ReceiptText, Search, Settings2, ShieldCheck, ShoppingBag, UsersRound, X,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import { api, attachmentUrl, conditionLabel, formatDate, formatNumber, variantLabel } from '@/lib/api'
import { useMasterStore } from '@/stores/master'

const route = useRoute()
const router = useRouter()
const master = useMasterStore()
const sidebarOpen = ref(false)
const quickQuery = ref('')
const showActivityModal = ref(false)
const loadingActivity = ref(false)
const recentMovements = ref<Array<{
  id: number; occurred_at: string; movement_type: string; condition: string;
  quantity_delta: number; balance_after: number; notes: string | null;
  item_variants?: { size: string; items?: { name: string; unit: string } | null } | null
}>>([])

const now = ref(new Date())
let clockTimer: number | undefined

const formattedDate = computed(() =>
  new Intl.DateTimeFormat('id-ID', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(now.value),
)

const formattedTime = computed(() =>
  new Intl.DateTimeFormat('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(now.value).replace(/\./g, ':'),
)

const navGroups = [
  {
    section: 'Ringkasan',
    items: [
      { name: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    ],
  },
  {
    section: 'Stok & Audit',
    items: [
      { name: 'inventory', label: 'Stok Inventaris', icon: Boxes },
      { name: 'stocktakes', label: 'Stok Opname (+/-)', icon: ClipboardCheck },
    ],
  },
  {
    section: 'Pengadaan & Arus APD',
    items: [
      { name: 'procurements', label: 'Pengadaan Barang', icon: ShoppingBag },
      { name: 'receipts', label: 'Barang Masuk', icon: PackagePlus },
      { name: 'issuances', label: 'Barang Keluar', icon: PackageMinus },
      { name: 'returns', label: 'Pengembalian APD', icon: PackageCheck },
      { name: 'employees', label: 'Karyawan & APD', icon: UsersRound },
    ],
  },
  {
    section: 'Keuangan & Laporan',
    items: [
      { name: 'payments', label: 'History Pembayaran', icon: ReceiptText },
      { name: 'reports', label: 'Laporan', icon: FileBarChart },
    ],
  },
  {
    section: 'Konfigurasi',
    items: [
      { name: 'master', label: 'Master & Pengaturan', icon: Settings2 },
    ],
  },
]

const allNav = navGroups.flatMap((g) => g.items)
const pageTitle = computed(() => allNav.find((item) => item.name === route.name)?.label || 'Inventaris APD')
const alertCount = computed(() => master.variants.filter((v) => v.stock_status !== 'safe').length)
const lowVariants = computed(() => master.variants.filter((v) => v.stock_status !== 'safe'))

function movementLabel(t: string) {
  const map: Record<string, string> = {
    opening_stock: 'Stok Awal', receipt: 'Barang Masuk', issuance: 'Barang Keluar',
    return: 'Pengembalian APD', stocktake_adjustment: 'Stok Opname', condition_transfer: 'Pindah Kondisi',
  }
  return map[t] || t
}

async function openActivityModal() {
  showActivityModal.value = true
  loadingActivity.value = true
  try {
    const [movRes] = await Promise.all([
      api<{ data: typeof recentMovements.value }>('/api/inventory/movements?limit=15'),
      master.refresh(true),
    ])
    recentMovements.value = movRes.data
  } finally {
    loadingActivity.value = false
  }
}

function onQuickSearch() {
  if (!quickQuery.value.trim()) return
  router.push({ name: 'inventory' })
}

onMounted(() => {
  clockTimer = window.setInterval(() => {
    now.value = new Date()
  }, 1000)
  master.refresh().catch(() => {})
})

onUnmounted(() => {
  if (clockTimer) window.clearInterval(clockTimer)
})
</script>

<template>
  <div class="app-shell">
    <div v-if="sidebarOpen" class="sidebar-backdrop" @click="sidebarOpen = false" />
    <aside class="sidebar" :class="{ open: sidebarOpen }">
      <div class="brand-panel">
        <div class="brand-top">
          <div class="brand-mark">
            <ShieldCheck :size="21" stroke-width="2.2" />
          </div>
          <div class="brand-titles">
            <strong>INVENTRA</strong>
            <span>APD Asset Control</span>
          </div>
          <button class="icon-button sidebar-close" aria-label="Tutup menu" @click="sidebarOpen = false"><X :size="18" /></button>
        </div>

        <button type="button" class="workspace-pill" @click="router.push({ name: 'master', query: { section: 'company' } }); sidebarOpen = false">
          <span class="workspace-icon" :class="{ 'has-logo': Boolean(master.company.logoKey) }">
            <img v-if="master.company.logoKey" :src="attachmentUrl(master.company.logoKey)" alt="Logo PT" />
            <template v-else>{{ master.companyInitials }}</template>
          </span>
          <span class="workspace-meta">
            <strong>{{ master.company.name }}</strong>
            <small>{{ master.company.tagline }}</small>
          </span>
          <Settings2 :size="15" class="workspace-gear" />
        </button>
      </div>

      <div class="nav-plots">
        <div v-for="group in navGroups" :key="group.section" class="nav-plot">
          <p class="nav-section">{{ group.section }}</p>
          <nav class="nav-list">
            <RouterLink v-for="item in group.items" :key="item.name" :to="{ name: item.name }" @click="sidebarOpen = false">
              <component :is="item.icon" :size="17" />
              <span>{{ item.label }}</span>
            </RouterLink>
          </nav>
        </div>
      </div>

      <div class="sidebar-foot">
        <a href="https://daysheet.id" target="_blank" rel="noopener noreferrer" class="daysheet-card" title="Kunjungi situs resmi DaySheet.id">
          <span class="daysheet-brand-pill">
            <img src="/daysheet-logo.png" alt="DaySheet.id" class="daysheet-logo-wordmark" />
          </span>
          <span class="daysheet-sub">
            <small>Powered by</small>
            <span>daysheet.id</span>
          </span>
          <ArrowUpRight :size="15" class="daysheet-arrow" />
        </a>
        <div class="user-card">
          <span class="avatar">IN</span>
          <span><strong>Inventaris APD</strong><small>Operasional Gudang</small></span>
        </div>
      </div>
    </aside>

    <main class="main-area">
      <header class="topbar">
        <div class="topbar-left">
          <button class="icon-button menu-button" aria-label="Buka menu" @click="sidebarOpen = true"><Menu :size="20" /></button>
          <div class="page-heading">
            <span>Operasional</span>
            <h1>{{ pageTitle }}</h1>
          </div>
        </div>

        <div class="topbar-center">
          <div class="live-clock-pill" title="Waktu lokal sistem">
            <span class="clock-date"><CalendarDays :size="14" /> {{ formattedDate }}</span>
            <span class="clock-sep" />
            <span class="clock-time"><Clock :size="14" /> {{ formattedTime }} WIB</span>
          </div>
        </div>

        <div class="top-actions">
          <form class="global-search" @submit.prevent="onQuickSearch">
            <Search :size="16" />
            <input v-model="quickQuery" placeholder="Lompat ke stok inventaris..." />
          </form>
          <button
            class="icon-button notification"
            :title="`Pergerakan terbaru & ${alertCount} stok perlu perhatian`"
            aria-label="Notifikasi Pergerakan"
            @click="openActivityModal"
          >
            <Bell :size="18" />
            <i v-if="alertCount > 0" />
          </button>
          <span class="top-avatar">IN</span>
        </div>
      </header>
      <div class="page-content">
        <RouterView v-slot="{ Component }">
          <Transition name="page-fade" mode="out-in">
            <component :is="Component" />
          </Transition>
        </RouterView>
      </div>
      <footer class="app-footer">
        <div class="footer-left">
          <span>INVENTRA · <strong>{{ master.company.name }}</strong> — Sistem Kontrol Inventaris APD</span>
        </div>
        <a href="https://daysheet.id" target="_blank" rel="noopener noreferrer" class="footer-copyright" title="Kunjungi situs resmi DaySheet.id">
          <span>© {{ now.getFullYear() }}</span>
          <span class="footer-logo-chip"><img src="/daysheet-logo.png" alt="DaySheet.id" /></span>
          <span>All rights reserved</span>
        </a>
      </footer>
    </main>

    <BaseModal
      :open="showActivityModal"
      title="Pergerakan & Aktivitas Terbaru"
      eyebrow="Monitor Real-Time"
      subtitle="Ringkasan mutasi stok terbaru di sistem serta peringatan stok menipis/habis."
      size="lg"
      @close="showActivityModal = false"
    >
      <div class="detail-stack">
        <div v-if="lowVariants.length" class="detail-section">
          <h4>Peringatan Stok Menipis / Habis ({{ lowVariants.length }})</h4>
          <div class="tag-group">
            <span v-for="v in lowVariants" :key="v.variant_id" class="status-pill" :class="v.stock_status">
              {{ variantLabel(v) }} · Sisa {{ formatNumber(v.total_available) }} {{ v.unit }}
            </span>
          </div>
        </div>

        <div class="detail-section">
          <h4>15 Pergerakan Stok Terakhir di Website</h4>
          <div v-if="loadingActivity" class="loading-row">Memuat pergerakan terbaru...</div>
          <div v-else class="table-wrap">
            <table>
              <thead><tr><th>Tanggal</th><th>Aktivitas</th><th>Barang</th><th>Kondisi</th><th>Perubahan</th><th>Stok Akhir</th></tr></thead>
              <tbody>
                <tr v-for="m in recentMovements" :key="m.id">
                  <td>{{ formatDate(m.occurred_at) }}</td>
                  <td><strong>{{ movementLabel(m.movement_type) }}</strong><small class="table-sub">{{ m.notes || '-' }}</small></td>
                  <td>{{ variantLabel({ name: m.item_variants?.items?.name, size: m.item_variants?.size }) }}</td>
                  <td>{{ conditionLabel(m.condition) }}</td>
                  <td><span class="delta-pill" :class="m.quantity_delta >= 0 ? 'plus' : 'minus'">{{ m.quantity_delta >= 0 ? '+' : '' }}{{ formatNumber(m.quantity_delta) }}</span></td>
                  <td><strong>{{ formatNumber(m.balance_after) }}</strong></td>
                </tr>
                <tr v-if="!recentMovements.length"><td colspan="6"><div class="empty-state compact">Belum ada aktivitas mutasi.</div></td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </BaseModal>
  </div>
</template>
