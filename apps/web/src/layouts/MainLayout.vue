<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import {
  Bell, Boxes, ClipboardCheck, FileBarChart, LayoutDashboard, Menu,
  PackageCheck, PackageMinus, PackagePlus, ReceiptText, Search, Settings2, ShieldCheck, UsersRound, X,
} from '@lucide/vue'

const route = useRoute()
const sidebarOpen = ref(false)

const nav = [
  { name: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { name: 'master', label: 'Master Data', icon: UsersRound },
  { name: 'purchases', label: 'Pembelian & Masuk', icon: PackagePlus },
  { name: 'issuances', label: 'Barang Keluar', icon: PackageMinus },
  { name: 'returns', label: 'Pengembalian APD', icon: PackageCheck },
  { name: 'inventory', label: 'Stok Inventaris', icon: Boxes },
  { name: 'stocktakes', label: 'Stok Opname', icon: ClipboardCheck },
  { name: 'payments', label: 'Pembayaran', icon: ReceiptText },
  { name: 'reports', label: 'Laporan', icon: FileBarChart },
]

const pageTitle = computed(() => nav.find((item) => item.name === route.name)?.label || 'Inventaris APD')
</script>

<template>
  <div class="app-shell">
    <div v-if="sidebarOpen" class="sidebar-backdrop" @click="sidebarOpen = false" />
    <aside class="sidebar" :class="{ open: sidebarOpen }">
      <div class="brand">
        <div class="brand-mark"><ShieldCheck :size="25" stroke-width="2.2" /></div>
        <div><strong>INVENTRA</strong><span>Asset Control</span></div>
        <button class="icon-button sidebar-close" aria-label="Tutup menu" @click="sidebarOpen = false"><X :size="20" /></button>
      </div>

      <div class="workspace-card">
        <span class="workspace-icon">RIA</span>
        <div><strong>PT Ria Industri</strong><small>Inventaris APD</small></div>
        <Settings2 :size="16" />
      </div>

      <p class="nav-section">Menu utama</p>
      <nav class="nav-list">
        <RouterLink v-for="item in nav" :key="item.name" :to="{ name: item.name }" @click="sidebarOpen = false">
          <component :is="item.icon" :size="19" />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <div class="sidebar-foot">
        <div class="support-card">
          <span><ShieldCheck :size="17" /> Data terlindungi</span>
          <small>Sinkronisasi terakhir baru saja</small>
        </div>
        <div class="user-card">
          <span class="avatar">IN</span>
          <span><strong>Inventaris APD</strong><small>Operasional</small></span>
        </div>
      </div>
    </aside>

    <main class="main-area">
      <header class="topbar">
        <button class="icon-button menu-button" aria-label="Buka menu" @click="sidebarOpen = true"><Menu :size="22" /></button>
        <div class="page-heading"><span>Operasional</span><h1>{{ pageTitle }}</h1></div>
        <div class="top-actions">
          <label class="global-search"><Search :size="18" /><input placeholder="Cari data..." /></label>
          <button class="icon-button notification" aria-label="Notifikasi"><Bell :size="20" /><i /></button>
          <span class="top-avatar">IN</span>
        </div>
      </header>
      <div class="page-content"><RouterView /></div>
    </main>
  </div>
</template>
