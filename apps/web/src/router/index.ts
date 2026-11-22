import { createRouter, createWebHistory } from 'vue-router'
import MainLayout from '@/layouts/MainLayout.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', redirect: '/' },
    {
      path: '/',
      component: MainLayout,
      children: [
        { path: '', name: 'dashboard', component: () => import('@/pages/DashboardPage.vue') },
        { path: 'master-data', name: 'master', component: () => import('@/pages/MasterDataPage.vue') },
        { path: 'pengadaan', name: 'procurements', component: () => import('@/pages/ProcurementsPage.vue') },
        { path: 'barang-masuk', name: 'receipts', component: () => import('@/pages/ReceiptsPage.vue') },
        { path: 'pembelian', redirect: '/barang-masuk' },
        { path: 'barang-keluar', name: 'issuances', component: () => import('@/pages/IssuancesPage.vue') },
        { path: 'pengembalian', name: 'returns', component: () => import('@/pages/ReturnsPage.vue') },
        { path: 'stok', name: 'inventory', component: () => import('@/pages/InventoryPage.vue') },
        { path: 'stok-opname', name: 'stocktakes', component: () => import('@/pages/StocktakesPage.vue') },
        { path: 'pembayaran', name: 'payments', component: () => import('@/pages/PaymentsPage.vue') },
        { path: 'laporan', name: 'reports', component: () => import('@/pages/ReportsPage.vue') },
      ],
    },
  ],
})

export default router
