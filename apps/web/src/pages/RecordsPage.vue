<script setup lang="ts">
import { computed, ref, type Component } from 'vue'
import { useRoute } from 'vue-router'
import { Building2, CheckCircle2, ChevronRight, ClipboardCheck, Download, FileBarChart, HandCoins, PackageCheck, PackageMinus, PackagePlus, Plus, Search, Truck, UserRound, UsersRound, WalletCards, X } from '@lucide/vue'

const route = useRoute()
const showPanel = ref(false)
const activeTab = ref('Semua')

type ModuleConfig = {
  eyebrow: string; title: string; description: string; action: string; icon: Component;
  tabs: readonly string[]; emptyTitle: string; emptyText: string;
  cards?: readonly { label: string; icon: Component }[]
}

const modules: Record<string, ModuleConfig> = {
  master: { eyebrow: 'Referensi sistem', title: 'Master Data', description: 'Kelola barang, karyawan, departemen, supplier, dan pihak penalang.', action: 'Tambah data', icon: UsersRound, tabs: ['Barang','Karyawan','Departemen','Supplier','Pihak penalang'], emptyTitle: 'Pilih kelompok master data', emptyText: 'Data referensi menjadi dasar seluruh transaksi inventaris.', cards: [{label:'Barang',icon:PackageCheck},{label:'Karyawan',icon:UserRound},{label:'Departemen',icon:Building2},{label:'Supplier',icon:Truck}] },
  purchases: { eyebrow: 'Penerimaan stok', title: 'Pembelian & Barang Masuk', description: 'Catat satu pembelian dengan beberapa item dan dokumen pendukung.', action: 'Catat pembelian', icon: PackagePlus, tabs: ['Semua','Perusahaan','Ditalangi'], emptyTitle: 'Belum ada transaksi pembelian', emptyText: 'Pembelian yang diterima akan menambah stok sesuai ukuran dan kondisi.' },
  issuances: { eyebrow: 'Distribusi APD', title: 'Barang Keluar', description: 'Serahkan beberapa item ke karyawan tanpa mengizinkan stok negatif.', action: 'Catat barang keluar', icon: PackageMinus, tabs: ['Semua','Hari ini','Bulan ini'], emptyTitle: 'Belum ada barang keluar', emptyText: 'Tanggungan otomatis dibuat untuk APD yang wajib dikembalikan.' },
  returns: { eyebrow: 'Pemeriksaan APD', title: 'Pengembalian APD', description: 'Periksa pengembalian parsial dan arahkan barang ke kondisi yang tepat.', action: 'Periksa pengembalian', icon: PackageCheck, tabs: ['Semua','Layak','Karantina','Rusak','Hilang'], emptyTitle: 'Belum ada pengembalian', emptyText: 'Pilih karyawan untuk menarik transaksi dan sisa tanggungannya.' },
  stocktakes: { eyebrow: 'Rekonsiliasi saldo', title: 'Stok Opname', description: 'Bandingkan saldo sistem dan fisik dengan jejak penyesuaian yang aman.', action: 'Buat stok opname', icon: ClipboardCheck, tabs: ['Semua','Draft','Menunggu pemeriksaan','Selesai'], emptyTitle: 'Belum ada stok opname', emptyText: 'Draft tidak mengubah stok. Penyesuaian dibuat saat finalisasi.' },
  payments: { eyebrow: 'Kontrol pendanaan', title: 'Pembayaran & Reimbursement', description: 'Pantau dana perusahaan, talangan, riwayat penggantian, dan sisa.', action: 'Catat penggantian', icon: HandCoins, tabs: ['Semua','Belum diajukan','Diajukan','Dibayar sebagian','Lunas'], emptyTitle: 'Belum ada reimbursement', emptyText: 'Penggantian dana tidak membuat pembelian baru dan tidak mengubah stok.' },
  reports: { eyebrow: 'Analitik terfilter', title: 'Laporan', description: 'Ekspor laporan transaksi, penggunaan, tanggungan, dan mutasi stok.', action: 'Ekspor laporan', icon: FileBarChart, tabs: ['Mutasi stok','Penggunaan','Tanggungan','Pembelian','Reimbursement'], emptyTitle: 'Tentukan jenis dan periode laporan', emptyText: 'Hasil ekspor akan mengikuti filter aktif tanpa mencampur satuan.' },
}

const current = computed(() => modules[String(route.meta.module)] || modules.purchases!)
</script>

<template>
  <div>
    <section class="page-intro">
      <div><p class="eyebrow">{{ current.eyebrow }}</p><h2>{{ current.title }}</h2><p>{{ current.description }}</p></div>
      <div class="intro-actions"><button v-if="route.meta.module === 'reports'" class="secondary-button"><Download :size="17" /> Template</button><button class="primary-button" @click="showPanel = true"><Plus v-if="route.meta.module !== 'reports'" :size="18" /><Download v-else :size="17" /> {{ current.action }}</button></div>
    </section>

    <div v-if="current.cards" class="master-cards">
      <button v-for="card in current.cards" :key="card.label"><span><component :is="card.icon" :size="22" /></span><strong>{{ card.label }}</strong><small>Kelola data</small><ChevronRight :size="18" /></button>
    </div>

    <section class="panel data-panel">
      <div class="record-tabs"><button v-for="tab in current.tabs" :key="tab" :class="{ active: activeTab === tab }" @click="activeTab = tab">{{ tab }}</button></div>
      <div class="table-toolbar"><label class="search-field"><Search :size="18" /><input :placeholder="`Cari di ${current.title.toLowerCase()}...`" /></label><button class="secondary-button">Filter</button></div>
      <div class="empty-state records-empty"><span class="empty-illustration"><component :is="current.icon" :size="34" /></span><strong>{{ current.emptyTitle }}</strong><p>{{ current.emptyText }}</p><button class="primary-button" @click="showPanel = true">{{ current.action }}</button></div>
    </section>

    <Transition name="fade"><div v-if="showPanel" class="drawer-backdrop" @click.self="showPanel = false"><aside class="form-drawer">
      <header><div><p class="eyebrow">Formulir baru</p><h3>{{ current.action }}</h3></div><button class="icon-button" @click="showPanel = false"><X :size="20" /></button></header>
      <div class="drawer-body">
        <div class="form-note"><CheckCircle2 :size="19" /><span><strong>Validasi transaksi aktif</strong><small>Data akan diperiksa terhadap saldo, peran, dan aturan bisnis sebelum disimpan.</small></span></div>
        <label class="field"><span>Tanggal transaksi</span><input type="date" :value="new Date().toISOString().slice(0,10)" /></label>
        <label class="field"><span>Referensi / keterangan</span><input placeholder="Masukkan referensi transaksi" /></label>
        <label class="field"><span>Catatan</span><textarea rows="4" placeholder="Tambahkan catatan bila diperlukan" /></label>
        <div class="upload-zone"><WalletCards :size="25" /><strong>Tambahkan dokumen pendukung</strong><small>JPG, PNG, WEBP, atau PDF · maksimal 10 MB</small></div>
        <p class="drawer-help">Form rinci menggunakan endpoint transaksi atomik yang tersedia di API. Master pilihan akan tampil setelah migrasi dan data awal Supabase tersedia.</p>
      </div>
      <footer><button class="secondary-button" @click="showPanel = false">Batal</button><button class="primary-button" disabled>Simpan transaksi</button></footer>
    </aside></div></Transition>
  </div>
</template>
