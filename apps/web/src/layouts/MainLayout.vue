<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  AlertTriangle, ArrowRightLeft, ArrowUpRight, Bell, Boxes, ClipboardCheck,
  FileBarChart, LayoutDashboard, Menu, PackageCheck, PackageMinus, PackagePlus, ReceiptText,
  RefreshCw, Search, Settings2, ShieldCheck, ShoppingBag, UsersRound, X,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import LiveClock from '@/components/LiveClock.vue'
import { api, attachmentUrl, conditionLabel, formatDate, formatNumber, invalidateApiCache, prefetchApi, variantLabel } from '@/lib/api'
import { useMasterStore } from '@/stores/master'

const route = useRoute()
const router = useRouter()
const master = useMasterStore()
const sidebarOpen = ref(false)
const quickQuery = ref('')
const currentYear = new Date().getFullYear()

// Activity & Notification Center state
const showActivityModal = ref(false)
const loadingActivity = ref(false)
const activityError = ref('')
const activityTab = ref<'feed' | 'alerts'>('feed')
const activityTypeFilter = ref<'all' | 'receipt' | 'issuance' | 'return' | 'stocktake_adjustment' | 'other'>('all')
const activitySearch = ref('')
const recentMovements = ref<Array<{
  id: number; occurred_at: string; movement_type: string; condition: string;
  quantity_delta: number; balance_after: number; notes: string | null;
  item_variants?: { size: string; items?: { code?: string; name: string; unit: string } | null } | null
}>>([])

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

const prefetched = new Set<string>()
function prefetchNav(name: string) {
  if (prefetched.has(name)) return
  prefetched.add(name)
  if (name === 'inventory') {
    void import('@/pages/InventoryPage.vue')
    prefetchApi('/api/inventory?page=1&limit=200&search=')
  } else if (name === 'stocktakes') {
    void import('@/pages/StocktakesPage.vue')
    prefetchApi('/api/transactions/stocktakes')
  } else if (name === 'procurements') {
    void import('@/pages/ProcurementsPage.vue')
    prefetchApi('/api/procurements')
  } else if (name === 'receipts') {
    void import('@/pages/ReceiptsPage.vue')
    prefetchApi('/api/transactions/purchases')
  } else if (name === 'issuances') {
    void import('@/pages/IssuancesPage.vue')
    prefetchApi('/api/transactions/issuances')
  } else if (name === 'returns') {
    void import('@/pages/ReturnsPage.vue')
    prefetchApi('/api/transactions/returns')
  } else if (name === 'employees') {
    void import('@/pages/EmployeesPage.vue')
    prefetchApi('/api/transactions/issuances')
    prefetchApi('/api/transactions/returns')
  } else if (name === 'payments') {
    void import('@/pages/PaymentsPage.vue')
    prefetchApi('/api/procurements')
    prefetchApi('/api/transactions/purchases')
  } else if (name === 'reports') {
    void import('@/pages/ReportsPage.vue')
    prefetchApi('/api/inventory/movements?limit=300')
  } else if (name === 'master') {
    void import('@/pages/MasterDataPage.vue')
  }
}

const allNav = navGroups.flatMap((g) => g.items)
const pageTitle = computed(() => allNav.find((item) => item.name === route.name)?.label || 'Inventaris APD')
const alertCount = computed(() => master.variants.filter((v) => v.stock_status !== 'safe').length)
const lowVariants = computed(() =>
  master.variants
    .filter((v) => v.stock_status !== 'safe')
    .sort((a, b) => (a.stock_status === 'out' ? -1 : 1) - (b.stock_status === 'out' ? -1 : 1)),
)

const filteredMovements = computed(() => {
  const q = activitySearch.value.trim().toLowerCase()
  return recentMovements.value.filter((m) => {
    if (activityTypeFilter.value === 'other') {
      if (['receipt', 'issuance', 'return', 'stocktake_adjustment'].includes(m.movement_type)) return false
    } else if (activityTypeFilter.value !== 'all' && m.movement_type !== activityTypeFilter.value) {
      return false
    }
    if (!q) return true
    const itemName = variantLabel({ name: m.item_variants?.items?.name, size: m.item_variants?.size }).toLowerCase()
    const typeName = movementLabel(m.movement_type).toLowerCase()
    const notes = (m.notes || '').toLowerCase()
    const code = (m.item_variants?.items?.code || '').toLowerCase()
    return itemName.includes(q) || typeName.includes(q) || notes.includes(q) || code.includes(q)
  })
})

function movementLabel(t: string) {
  const map: Record<string, string> = {
    opening_stock: 'Stok Awal',
    receipt: 'Barang Masuk',
    issuance: 'Barang Keluar',
    return: 'Pengembalian APD',
    stocktake_adjustment: 'Stok Opname',
    condition_transfer: 'Pindah Kondisi',
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

async function fetchActivity(force = false) {
  if (force) invalidateApiCache('/api/inventory/movements')
  loadingActivity.value = true
  activityError.value = ''
  try {
    const [movRes] = await Promise.all([
      api<{ data: typeof recentMovements.value }>('/api/inventory/movements?limit=30'),
      master.refresh(force),
    ])
    recentMovements.value = movRes.data
  } catch (e) {
    activityError.value = e instanceof Error ? e.message : 'Gagal memuat pergerakan terbaru'
  } finally {
    loadingActivity.value = false
  }
}

function openActivityModal() {
  showActivityModal.value = true
  activityTab.value = 'feed'
  activityTypeFilter.value = 'all'
  activitySearch.value = ''
  void fetchActivity(true)
}

function goToAlertItem(stockStatus: 'low' | 'out') {
  showActivityModal.value = false
  void router.push({ name: 'inventory', query: { status: stockStatus } })
}

function goToReports() {
  showActivityModal.value = false
  void router.push({ name: 'reports' })
}

function onQuickSearch() {
  const q = quickQuery.value.trim()
  if (!q) return
  void router.push({ name: 'inventory', query: { search: q } })
  quickQuery.value = ''
}

onMounted(() => {
  master.refresh().catch(() => {})
})
</script>

<template>
  <div class="app-shell">
    <div v-if="sidebarOpen" class="sidebar-backdrop" @click="sidebarOpen = false" />
    <aside class="sidebar" :class="{ open: sidebarOpen }">
      <div class="brand-panel">
        <div class="brand-top">
          <div class="brand-mark"><ShieldCheck :size="20" /></div>
          <div class="brand-titles"><strong>INVENTRA</strong><span>APD Asset Control</span></div>
          <button class="icon-button sidebar-close" aria-label="Tutup menu" @click="sidebarOpen = false"><X :size="18" /></button>
        </div>

        <RouterLink :to="{ name: 'master' }" class="workspace-pill" title="Ubah identitas & logo perusahaan" @click="sidebarOpen = false">
          <div class="workspace-icon" :class="{ 'has-logo': Boolean(master.company.logoKey) }">
            <img v-if="master.company.logoKey" :src="attachmentUrl(master.company.logoKey)" :alt="master.company.name" />
            <span v-else>{{ master.companyInitials }}</span>
          </div>
          <div class="workspace-meta">
            <strong>{{ master.company.name }}</strong>
            <small>{{ master.company.tagline }}</small>
          </div>
          <Settings2 :size="14" class="workspace-gear" />
        </RouterLink>
      </div>

      <nav class="nav-plots">
        <div v-for="group in navGroups" :key="group.section" class="nav-plot">
          <p class="nav-section">{{ group.section }}</p>
          <div class="nav-list">
            <RouterLink
              v-for="item in group.items"
              :key="item.name"
              :to="{ name: item.name }"
              @mouseenter="prefetchNav(item.name)"
              @focus="prefetchNav(item.name)"
              @click="sidebarOpen = false"
            >
              <component :is="item.icon" :size="17" />
              <span>{{ item.label }}</span>
            </RouterLink>
          </div>
        </div>
      </nav>

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
          <LiveClock />
        </div>

        <div class="top-actions">
          <form class="global-search" @submit.prevent="onQuickSearch">
            <Search :size="16" />
            <input v-model="quickQuery" placeholder="Cari barang di stok inventaris..." />
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
          <KeepAlive :max="8">
            <component :is="Component" />
          </KeepAlive>
        </RouterView>
      </div>
      <footer class="app-footer">
        <div class="footer-left">
          <span>INVENTRA · <strong>{{ master.company.name }}</strong> — Sistem Kontrol Inventaris APD</span>
        </div>
        <a href="https://daysheet.id" target="_blank" rel="noopener noreferrer" class="footer-copyright" title="Kunjungi situs resmi DaySheet.id">
          <span>© {{ currentYear }}</span>
          <span class="footer-logo-chip"><img src="/daysheet-logo.png" alt="DaySheet.id" /></span>
          <span>All rights reserved</span>
        </a>
      </footer>
    </main>

    <BaseModal
      :open="showActivityModal"
      title="Pergerakan & Aktivitas Terbaru"
      eyebrow="Monitor Real-Time"
      subtitle="Pantau seluruh arus mutasi gudang terbaru dan peringatan stok menipis atau habis."
      size="xl"
      @close="showActivityModal = false"
    >
      <div class="activity-center-header">
        <div class="record-tabs" style="margin-bottom:0;">
          <button type="button" :class="{ active: activityTab === 'feed' }" @click="activityTab = 'feed'">
            Aktivitas Mutasi ({{ recentMovements.length }})
          </button>
          <button type="button" :class="{ active: activityTab === 'alerts' }" @click="activityTab = 'alerts'">
            Peringatan Stok ({{ lowVariants.length }})
          </button>
        </div>
        <div class="activity-center-actions">
          <button type="button" class="secondary-button xs" :disabled="loadingActivity" @click="fetchActivity(true)">
            <RefreshCw :size="14" :class="{ spinning: loadingActivity }" /> Segarkan
          </button>
          <button type="button" class="secondary-button xs" @click="goToReports">
            Buka Laporan <ArrowUpRight :size="14" />
          </button>
        </div>
      </div>

      <div v-if="activityError" class="inline-alert" style="margin-top:12px;">
        <AlertTriangle :size="16" /> {{ activityError }}
        <button type="button" @click="fetchActivity(true)">Coba lagi</button>
      </div>

      <!-- Tab 1: Modern Activity Feed -->
      <div v-if="activityTab === 'feed'" class="activity-feed-panel">
        <div class="activity-filter-bar">
          <label class="search-field" style="flex:1;min-width:200px;">
            <Search :size="15" />
            <input v-model="activitySearch" placeholder="Cari nama barang, jenis aktivitas, atau catatan..." />
          </label>
          <div class="activity-type-chips">
            <button type="button" :class="{ active: activityTypeFilter === 'all' }" @click="activityTypeFilter = 'all'">Semua</button>
            <button type="button" :class="{ active: activityTypeFilter === 'receipt' }" @click="activityTypeFilter = 'receipt'">Masuk</button>
            <button type="button" :class="{ active: activityTypeFilter === 'issuance' }" @click="activityTypeFilter = 'issuance'">Keluar</button>
            <button type="button" :class="{ active: activityTypeFilter === 'return' }" @click="activityTypeFilter = 'return'">Kembali</button>
            <button type="button" :class="{ active: activityTypeFilter === 'stocktake_adjustment' }" @click="activityTypeFilter = 'stocktake_adjustment'">Opname</button>
            <button type="button" :class="{ active: activityTypeFilter === 'other' }" @click="activityTypeFilter = 'other'">Lainnya</button>
          </div>
        </div>

        <div v-if="loadingActivity" class="loading-row">Memuat aktivitas mutasi terbaru...</div>

        <div v-else-if="!filteredMovements.length" class="empty-state compact">
          <Boxes :size="26" />
          <strong>Belum ada aktivitas mutasi yang cocok.</strong>
          <span>Coba ubah filter atau lakukan transaksi baru.</span>
        </div>

        <ul v-else class="activity-feed-list">
          <li v-for="m in filteredMovements" :key="m.id" class="activity-feed-item">
            <span class="activity-feed-icon">
              <component :is="movementIcon(m.movement_type)" :size="17" />
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
      </div>

      <!-- Tab 2: Stock Alerts -->
      <div v-else class="activity-feed-panel">
        <div v-if="!lowVariants.length" class="empty-state compact">
          <ShieldCheck :size="28" />
          <strong>Semua stok berada dalam batas aman!</strong>
          <span>Tidak ada item APD yang menipis atau habis saat ini.</span>
        </div>
        <ul v-else class="activity-alert-list">
          <li v-for="v in lowVariants" :key="v.variant_id">
            <button type="button" class="activity-alert-row" @click="goToAlertItem(v.stock_status as 'low' | 'out')">
              <span class="activity-feed-icon"><AlertTriangle :size="17" /></span>
              <div class="activity-feed-body">
                <strong>{{ variantLabel(v) }}</strong>
                <small class="table-sub">Kode {{ v.code }} · Batas minimum {{ formatNumber(v.minimum_stock) }} {{ v.unit }}</small>
              </div>
              <div class="activity-feed-numbers">
                <span class="status-pill" :class="v.stock_status">
                  {{ v.stock_status === 'out' ? 'Habis' : 'Menipis' }} · {{ formatNumber(v.total_available) }} {{ v.unit }}
                </span>
                <small>Klik lihat di Stok Inventaris →</small>
              </div>
            </button>
          </li>
        </ul>
      </div>
    </BaseModal>
  </div>
</template>
