import { createRouter, createWebHistory } from 'vue-router'
import MainLayout from '@/layouts/MainLayout.vue'
import DashboardPage from '@/pages/DashboardPage.vue'
import InventoryPage from '@/pages/InventoryPage.vue'
import RecordsPage from '@/pages/RecordsPage.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', redirect: '/' },
    {
      path: '/', component: MainLayout, children: [
        { path: '', name: 'dashboard', component: DashboardPage },
        { path: 'master-data', name: 'master', component: RecordsPage, meta: { module: 'master' } },
        { path: 'pembelian', name: 'purchases', component: RecordsPage, meta: { module: 'purchases' } },
        { path: 'barang-keluar', name: 'issuances', component: RecordsPage, meta: { module: 'issuances' } },
        { path: 'pengembalian', name: 'returns', component: RecordsPage, meta: { module: 'returns' } },
        { path: 'stok', name: 'inventory', component: InventoryPage },
        { path: 'stok-opname', name: 'stocktakes', component: RecordsPage, meta: { module: 'stocktakes' } },
        { path: 'pembayaran', name: 'payments', component: RecordsPage, meta: { module: 'payments' } },
        { path: 'laporan', name: 'reports', component: RecordsPage, meta: { module: 'reports' } },
      ],
    },
  ],
})

export default router
