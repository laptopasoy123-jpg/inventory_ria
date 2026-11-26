<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { Building2, Edit3, ImagePlus, Package, Plus, RotateCcw, Save, Search, ShieldCheck, ShoppingBag, Trash2, Truck, Wallet } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ItemFormModal from '@/components/ItemFormModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { api, attachmentUrl, uploadAttachment } from '@/lib/api'
import { itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore, type ItemMaster } from '@/stores/master'

type MasterTab = 'items' | 'departments' | 'officers' | 'suppliers' | 'online_shops' | 'funders'

const master = useMasterStore()
const toast = useToast()

const activeTab = ref<MasterTab>('items')
const search = ref('')
const statusFilter = ref<'all' | 'active' | 'inactive'>('all')
const unitFilter = ref('all')
const returnReqFilter = ref<'all' | 'yes' | 'no'>('all')
const officerRoleFilter = ref('all')
const page = ref(1)
const saving = ref(false)
const savingCompany = ref(false)
const uploadingLogo = ref(false)

const companyForm = reactive({
  name: master.company.name,
  tagline: master.company.tagline,
  logoKey: master.company.logoKey || '',
})

watch(() => master.company, (c) => {
  companyForm.name = c.name
  companyForm.tagline = c.tagline
  companyForm.logoKey = c.logoKey || ''
}, { immediate: true, deep: true })

async function handleLogoUpload(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  if (!file.type.startsWith('image/')) {
    toast.error('Logo perusahaan harus berupa gambar (JPG, PNG, atau WebP)')
    return
  }
  uploadingLogo.value = true
  try {
    const uploaded = await uploadAttachment(file)
    companyForm.logoKey = uploaded.key
    await master.saveCompany({
      name: companyForm.name,
      tagline: companyForm.tagline,
      logoKey: uploaded.key,
    })
    toast.success(`Logo "${uploaded.name}" berhasil diunggah & diterapkan ke sistem!`, 'Logo Perusahaan Diperbarui')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal mengunggah logo perusahaan')
  } finally {
    uploadingLogo.value = false
    input.value = ''
  }
}

async function removeCompanyLogo() {
  savingCompany.value = true
  try {
    companyForm.logoKey = ''
    await master.saveCompany({
      name: companyForm.name,
      tagline: companyForm.tagline,
      logoKey: null,
    })
    toast.success('Logo perusahaan dihapus (kembali ke inisial)', 'Logo Dihapus')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal menghapus logo')
  } finally {
    savingCompany.value = false
  }
}

async function saveCompanySettings() {
  if (!companyForm.name.trim()) return
  savingCompany.value = true
  try {
    await master.saveCompany({
      name: companyForm.name.trim(),
      tagline: companyForm.tagline.trim() || null,
      logoKey: companyForm.logoKey || null,
    })
    toast.success(`Identitas "${companyForm.name.trim()}" berhasil diterapkan ke seluruh halaman & PDF!`, 'Identitas PT Disimpan')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal menyimpan identitas perusahaan')
  } finally {
    savingCompany.value = false
  }
}

const activeOptions = [
  { value: true, label: 'Aktif', badge: 'Tersedia' },
  { value: false, label: 'Nonaktif', badge: 'Arsip' },
]

const roleOptions = [
  { value: 'Petugas Gudang / Penerima', label: 'Petugas Gudang / Penerima' },
  { value: 'Petugas Penyerah APD', label: 'Petugas Penyerah APD' },
  { value: 'Inspektor K3', label: 'Inspektor K3' },
  { value: 'Admin Inventaris & Opname', label: 'Admin Inventaris & Opname' },
]

const showItemModal = ref(false)
const editingItem = ref<ItemMaster | null>(null)

const showGenericModal = ref(false)
const editingId = ref<string | null>(null)

const genericForm = reactive({
  code: '',
  name: '',
  active: true,
  roleLabel: 'Petugas Gudang / Penerima',
  vendorType: 'supplier' as 'supplier' | 'online_shop',
  contactName: '',
  phone: '',
  address: '',
  notes: '',
  nik: '',
  position: '',
  departmentId: '',
  contractStatus: 'permanent' as 'permanent' | 'contract' | 'intern' | 'inactive',
})

const tabs = [
  { key: 'items' as const, label: 'Nama APD', icon: Package },
  { key: 'departments' as const, label: 'Departemen', icon: Building2 },
  { key: 'officers' as const, label: 'Petugas Sistem', icon: ShieldCheck },
  { key: 'suppliers' as const, label: 'Supplier', icon: Truck },
  { key: 'online_shops' as const, label: 'Toko Online', icon: ShoppingBag },
  { key: 'funders' as const, label: 'Pihak Penalang', icon: Wallet },
]

const statusFilterOptions = [
  { value: 'all', label: 'Semua Status' },
  { value: 'active', label: 'Aktif' },
  { value: 'inactive', label: 'Nonaktif' },
]

const unitFilterOptions = computed(() => {
  const units = new Set<string>()
  for (const it of master.items) if (it.unit) units.add(it.unit)
  return [
    { value: 'all', label: 'Semua Satuan' },
    ...[...units].sort((a, b) => a.localeCompare(b)).map((u) => ({ value: u, label: `Satuan: ${u}` })),
  ]
})

const returnReqFilterOptions = [
  { value: 'all', label: 'Semua Tipe APD' },
  { value: 'yes', label: 'Wajib Kembali' },
  { value: 'no', label: 'Habis Pakai' },
]

const officerRoleFilterOptions = computed(() => {
  const roles = new Set<string>()
  for (const o of master.officers) if (o.role_label) roles.add(o.role_label)
  return [
    { value: 'all', label: 'Semua Peran Petugas' },
    ...[...roles].sort((a, b) => a.localeCompare(b)).map((r) => ({ value: r, label: r })),
  ]
})

const hasMasterFilters = computed(() =>
  Boolean(search.value.trim() || statusFilter.value !== 'all' || unitFilter.value !== 'all' || returnReqFilter.value !== 'all' || officerRoleFilter.value !== 'all'),
)

function resetMasterFilters() {
  search.value = ''
  statusFilter.value = 'all'
  unitFilter.value = 'all'
  returnReqFilter.value = 'all'
  officerRoleFilter.value = 'all'
}

function matchActive(active: boolean) {
  if (statusFilter.value === 'active') return active !== false
  if (statusFilter.value === 'inactive') return active === false
  return true
}

const filteredItems = computed(() => {
  const q = search.value.toLowerCase()
  return master.items.filter((i) => {
    if (!matchActive(i.active)) return false
    if (unitFilter.value !== 'all' && i.unit !== unitFilter.value) return false
    if (returnReqFilter.value === 'yes' && !i.return_required) return false
    if (returnReqFilter.value === 'no' && i.return_required) return false
    return !q || i.name.toLowerCase().includes(q) || i.code.toLowerCase().includes(q)
  })
})
const filteredDepartments = computed(() => {
  const q = search.value.toLowerCase()
  return master.departments.filter((d) => matchActive(d.active) && (!q || d.name.toLowerCase().includes(q) || d.code.toLowerCase().includes(q)))
})
const filteredOfficers = computed(() => {
  const q = search.value.toLowerCase()
  return master.officers.filter((o) => {
    if (!matchActive(o.active)) return false
    if (officerRoleFilter.value !== 'all' && o.role_label !== officerRoleFilter.value) return false
    return !q || o.name.toLowerCase().includes(q) || o.role_label.toLowerCase().includes(q)
  })
})
const filteredSuppliers = computed(() => {
  const q = search.value.toLowerCase()
  return master.suppliers.filter((s) => matchActive(s.active) && (s.vendor_type || 'supplier') === 'supplier' && (!q || s.name.toLowerCase().includes(q) || s.code.toLowerCase().includes(q)))
})
const filteredOnlineShops = computed(() => {
  const q = search.value.toLowerCase()
  return master.suppliers.filter((s) => matchActive(s.active) && s.vendor_type === 'online_shop' && (!q || s.name.toLowerCase().includes(q) || s.code.toLowerCase().includes(q)))
})
const filteredFunders = computed(() => {
  const q = search.value.toLowerCase()
  return master.funders.filter((f) => matchActive(f.active) && (!q || f.name.toLowerCase().includes(q)))
})

const paginate = <T>(list: T[]) => list.slice((page.value - 1) * 10, page.value * 10)
const activeTotalCount = computed(() => {
  const map: Record<MasterTab, number> = {
    items: filteredItems.value.length,
    departments: filteredDepartments.value.length,
    officers: filteredOfficers.value.length,
    suppliers: filteredSuppliers.value.length,
    online_shops: filteredOnlineShops.value.length,
    funders: filteredFunders.value.length,
  }
  return map[activeTab.value]
})
watch([activeTab, search, statusFilter, unitFilter, returnReqFilter, officerRoleFilter], () => { page.value = 1 })

function openAdd() {
  if (activeTab.value === 'items') {
    editingItem.value = null
    showItemModal.value = true
    return
  }
  editingId.value = null
  genericForm.code = ''
  genericForm.name = ''
  genericForm.active = true
  genericForm.roleLabel = 'Petugas Gudang / Penerima'
  genericForm.vendorType = activeTab.value === 'online_shops' ? 'online_shop' : 'supplier'
  genericForm.contactName = ''
  genericForm.phone = ''
  genericForm.address = ''
  genericForm.notes = ''
  genericForm.nik = ''
  genericForm.position = ''
  genericForm.departmentId = master.departments[0]?.id || ''
  genericForm.contractStatus = 'permanent'
  showGenericModal.value = true
}

function openEdit(row: Record<string, unknown>) {
  if (activeTab.value === 'items') {
    editingItem.value = row as unknown as ItemMaster
    showItemModal.value = true
    return
  }
  editingId.value = String(row.id)
  genericForm.code = String(row.code ?? '')
  genericForm.name = String(row.name ?? '')
  genericForm.active = row.active !== false
  genericForm.roleLabel = String(row.role_label ?? 'Petugas Gudang / Penerima')
  genericForm.vendorType = (row.vendor_type as 'supplier' | 'online_shop') || (activeTab.value === 'online_shops' ? 'online_shop' : 'supplier')
  genericForm.contactName = String(row.contact_name ?? '')
  genericForm.phone = String(row.phone ?? '')
  genericForm.address = String(row.address ?? '')
  genericForm.notes = String(row.notes ?? '')
  genericForm.nik = String(row.nik ?? '')
  genericForm.position = String(row.position ?? '')
  genericForm.departmentId = String(row.department_id ?? master.departments[0]?.id ?? '')
  genericForm.contractStatus = (row.contract_status as typeof genericForm.contractStatus) || 'permanent'
  showGenericModal.value = true
}

const modalTitle = computed(() => {
  const prefix = editingId.value ? 'Edit' : 'Tambah'
  const map: Record<MasterTab, string> = {
    items: 'Nama APD',
    departments: 'Departemen',
    officers: 'Petugas Sistem',
    suppliers: 'Supplier',
    online_shops: 'Toko Online',
    funders: 'Pihak Penalang',
  }
  return `${prefix} ${map[activeTab.value]}`
})

async function submitGeneric() {
  saving.value = true
  try {
    const id = editingId.value
    const method = id ? 'PUT' : 'POST'
    const suffix = id ? `/${id}` : ''
    let endpoint = ''
    let payload: Record<string, unknown> = {}

    if (activeTab.value === 'departments') {
      endpoint = `/api/master/departments${suffix}`
      payload = { code: genericForm.code, name: genericForm.name, active: genericForm.active }
    } else if (activeTab.value === 'officers') {
      endpoint = `/api/master/officers${suffix}`
      payload = { name: genericForm.name, roleLabel: genericForm.roleLabel, active: genericForm.active }
    } else if (activeTab.value === 'suppliers' || activeTab.value === 'online_shops') {
      endpoint = `/api/master/suppliers${suffix}`
      payload = {
        code: genericForm.code,
        name: genericForm.name,
        vendorType: activeTab.value === 'online_shops' ? 'online_shop' : genericForm.vendorType,
        contactName: genericForm.contactName || null,
        phone: genericForm.phone || null,
        address: genericForm.address || null,
        active: genericForm.active,
      }
    } else if (activeTab.value === 'funders') {
      endpoint = `/api/master/funders${suffix}`
      payload = {
        name: genericForm.name,
        phone: genericForm.phone || null,
        notes: genericForm.notes || null,
        active: genericForm.active,
      }
    }

    await api(endpoint, { method, body: JSON.stringify(payload) })
    await master.refresh(true)
    toast.success(`${modalTitle.value} berhasil disimpan`)
    showGenericModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan data')
  } finally {
    saving.value = false
  }
}

async function deleteRow(tab: MasterTab, id: string, label: string) {
  if (!window.confirm(`Hapus "${label}" secara permanen?`)) return
  const resourceMap: Record<MasterTab, string> = {
    items: 'items',
    departments: 'departments',
    officers: 'officers',
    suppliers: 'suppliers',
    online_shops: 'suppliers',
    funders: 'funders',
  }
  try {
    await api(`/api/master/${resourceMap[tab]}/${id}`, { method: 'DELETE' })
    await master.refresh(true)
    toast.success(`"${label}" berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus data')
  }
}

onMounted(() => {
  master.refresh().catch((e) => toast.error(e instanceof Error ? e.message : 'Gagal memuat pengaturan'))
})
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Pengaturan Sistem & Master Data</p>
        <h2>Pengaturan & Referensi</h2>
        <p>Kelola nama barang APD, departemen, daftar petugas sistem (penerima/inspektor), karyawan, supplier, toko online, dan pihak penalang.</p>
      </div>
      <div class="intro-actions">
        <button type="button" class="primary-button" @click="openAdd"><Plus :size="17" /> Tambah {{ tabs.find(t => t.key === activeTab)?.label }}</button>
      </div>
    </section>

    <!-- Company Identity & Logo Card -->
    <section class="panel company-brand-card">
      <div class="company-brand-left">
        <div class="company-logo-preview" :class="{ 'has-img': Boolean(companyForm.logoKey) }">
          <img v-if="companyForm.logoKey" :src="attachmentUrl(companyForm.logoKey)" alt="Logo Perusahaan" />
          <span v-else>{{ master.companyInitials }}</span>
        </div>
        <div class="company-logo-actions">
          <strong>Identitas & Logo Perusahaan</strong>
          <small>Nama PT dan logo tampil di sidebar, footer, cetakan, dan laporan PDF.</small>
          <div class="tag-group" style="margin-top: 6px;">
            <label class="secondary-button xs" style="cursor: pointer;">
              <ImagePlus :size="13" /> {{ uploadingLogo ? 'Mengunggah...' : (companyForm.logoKey ? 'Ganti Logo PT' : 'Upload Logo PT') }}
              <input type="file" accept=".jpg,.jpeg,.png,.webp" hidden @change="handleLogoUpload" />
            </label>
            <button v-if="companyForm.logoKey" type="button" class="icon-button danger" style="width: 28px; height: 28px;" title="Hapus logo" :disabled="savingCompany" @click="removeCompanyLogo">
              <Trash2 :size="13" />
            </button>
          </div>
        </div>
      </div>

      <form class="company-brand-form" @submit.prevent="saveCompanySettings">
        <label class="field">
          <span>Nama Perusahaan / PT *</span>
          <input v-model="companyForm.name" required minlength="2" placeholder="Contoh: PT Ria Industri" />
        </label>
        <label class="field">
          <span>Subjudul / Divisi</span>
          <input v-model="companyForm.tagline" placeholder="Contoh: Divisi K3 & Gudang APD" />
        </label>
        <button type="submit" class="primary-button" :disabled="savingCompany || uploadingLogo">
          <Save :size="15" /> {{ savingCompany ? 'Menyimpan...' : 'Simpan Nama & Logo' }}
        </button>
      </form>
    </section>

    <section class="master-summary-grid seven">
      <button v-for="t in tabs" :key="t.key" class="master-stat-card" :class="{ active: activeTab === t.key }" @click="activeTab = t.key">
        <span class="mini-icon teal"><component :is="t.icon" :size="18" /></span>
        <div>
          <small>{{ t.label }}</small>
          <strong>
            {{
              t.key === 'items' ? master.items.length
              : t.key === 'departments' ? master.departments.length
              : t.key === 'officers' ? master.officers.length
              : t.key === 'suppliers' ? master.suppliers.filter((s) => (s.vendor_type || 'supplier') === 'supplier').length
              : t.key === 'online_shops' ? master.suppliers.filter((s) => s.vendor_type === 'online_shop').length
              : master.funders.length
            }}
          </strong>
        </div>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button v-for="t in tabs" :key="t.key" :class="{ active: activeTab === t.key }" @click="activeTab = t.key">{{ t.label }}</button>
      </div>
      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari kode, nama, atau keterangan..." /></label>
        <ModernSelect v-model="statusFilter" :options="statusFilterOptions" compact searchable search-placeholder="Cari status..." />
        <template v-if="activeTab === 'items'">
          <ModernSelect v-model="unitFilter" :options="unitFilterOptions" compact searchable search-placeholder="Cari satuan..." />
          <ModernSelect v-model="returnReqFilter" :options="returnReqFilterOptions" compact searchable search-placeholder="Cari tipe APD..." />
        </template>
        <ModernSelect v-if="activeTab === 'officers'" v-model="officerRoleFilter" :options="officerRoleFilterOptions" compact searchable search-placeholder="Cari peran..." />
        <button v-if="hasMasterFilters" type="button" class="secondary-button xs" @click="resetMasterFilters">
          <RotateCcw :size="13" /> Reset
        </button>
      </div>

      <!-- Items Table -->
      <div v-if="activeTab === 'items'" class="table-wrap">
        <table>
          <thead><tr><th>Kode & Nama APD</th><th>Satuan</th><th>Min. Stok</th><th>Wajib Kembali</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredItems)" :key="row.id">
              <td>
                <span class="item-cell">
                  <img v-if="row.photo_key" :src="attachmentUrl(row.photo_key)" class="item-thumb" alt="Foto barang" />
                  <span v-else class="item-flaticon-box"><img :src="itemFlaticonIcon(row.name)" alt="" loading="lazy" /></span>
                  <span><strong>{{ row.name }}</strong><small>{{ row.code }}</small></span>
                </span>
              </td>
              <td>{{ row.unit }}</td>
              <td>{{ row.minimum_stock }}</td>
              <td><span class="status-pill" :class="row.return_required ? 'safe' : 'neutral'">{{ row.return_required ? 'Wajib Kembali' : 'Habis Pakai' }}</span></td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit barang" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus barang" @click="deleteRow('items', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredItems.length"><td colspan="6"><div class="empty-state compact">Belum ada data barang.</div></td></tr>
          </tbody>
        </table>
      </div>

      <!-- Departments Table -->
      <div v-else-if="activeTab === 'departments'" class="table-wrap">
        <table>
          <thead><tr><th>Kode</th><th>Nama Departemen</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredDepartments)" :key="row.id">
              <td><strong>{{ row.code }}</strong></td>
              <td>{{ row.name }}</td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit departemen" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus departemen" @click="deleteRow('departments', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredDepartments.length"><td colspan="4"><div class="empty-state compact">Belum ada departemen.</div></td></tr>
          </tbody>
        </table>
      </div>

      <!-- System Officers Table -->
      <div v-else-if="activeTab === 'officers'" class="table-wrap">
        <table>
          <thead><tr><th>Nama Petugas / Operator</th><th>Peran / Bagian</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredOfficers)" :key="row.id">
              <td><strong>{{ row.name }}</strong></td>
              <td>{{ row.role_label }}</td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit petugas" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus petugas" @click="deleteRow('officers', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredOfficers.length"><td colspan="4"><div class="empty-state compact">Belum ada nama petugas terdaftar.</div></td></tr>
          </tbody>
        </table>
      </div>

      <!-- Suppliers Table -->
      <div v-else-if="activeTab === 'suppliers'" class="table-wrap">
        <table>
          <thead><tr><th>Kode & Nama Supplier</th><th>Kontak</th><th>Telepon</th><th>Alamat</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredSuppliers)" :key="row.id">
              <td><strong>{{ row.name }}</strong><small class="table-sub">{{ row.code }}</small></td>
              <td>{{ row.contact_name || '-' }}</td>
              <td>{{ row.phone || '-' }}</td>
              <td>{{ row.address || '-' }}</td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit supplier" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus supplier" @click="deleteRow('suppliers', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredSuppliers.length"><td colspan="6"><div class="empty-state compact">Belum ada supplier.</div></td></tr>
          </tbody>
        </table>
      </div>

      <!-- Online Shops Table -->
      <div v-else-if="activeTab === 'online_shops'" class="table-wrap">
        <table>
          <thead><tr><th>Kode & Nama Toko Online</th><th>PIC / Akun</th><th>Telepon</th><th>Link / Platform</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredOnlineShops)" :key="row.id">
              <td><strong>{{ row.name }}</strong><small class="table-sub">{{ row.code }}</small></td>
              <td>{{ row.contact_name || '-' }}</td>
              <td>{{ row.phone || '-' }}</td>
              <td>{{ row.address || '-' }}</td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit toko online" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus toko online" @click="deleteRow('online_shops', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredOnlineShops.length"><td colspan="6"><div class="empty-state compact">Belum ada toko online terdaftar.</div></td></tr>
          </tbody>
        </table>
      </div>

      <!-- Funders Table -->
      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>Nama Pihak Penalang</th><th>Telepon</th><th>Catatan</th><th>Status</th><th /></tr></thead>
          <tbody>
            <tr v-for="row in paginate(filteredFunders)" :key="row.id">
              <td><strong>{{ row.name }}</strong></td>
              <td>{{ row.phone || '-' }}</td>
              <td>{{ row.notes || '-' }}</td>
              <td><span class="status-pill" :class="row.active ? 'safe' : 'out'">{{ row.active ? 'Aktif' : 'Nonaktif' }}</span></td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Edit penalang" @click="openEdit(row as unknown as Record<string, unknown>)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus penalang" @click="deleteRow('funders', row.id, row.name)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!filteredFunders.length"><td colspan="5"><div class="empty-state compact">Belum ada pihak penalang.</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="activeTotalCount" />
    </section>

    <ItemFormModal :open="showItemModal" :item="editingItem" @close="showItemModal = false" />

    <BaseModal :open="showGenericModal" :title="modalTitle" eyebrow="Pengaturan Sistem" size="sm" @close="showGenericModal = false">
      <form id="master-generic-form" class="modal-form" @submit.prevent="submitGeneric">
        <template v-if="activeTab === 'departments'">
          <label class="field"><span>Kode Departemen *</span><input v-model="genericForm.code" required placeholder="Contoh: LOG" /></label>
          <label class="field"><span>Nama Departemen *</span><input v-model="genericForm.name" required placeholder="Contoh: Logistik & Gudang" /></label>
          <label class="field"><span>Status</span><ModernSelect v-model="genericForm.active" :options="activeOptions" :searchable="false" /></label>
        </template>

        <template v-else-if="activeTab === 'officers'">
          <label class="field"><span>Nama Lengkap Petugas *</span><input v-model="genericForm.name" required placeholder="Contoh: Budi Santoso" /></label>
          <label class="field"><span>Peran / Tugas</span>
            <ModernSelect v-model="genericForm.roleLabel" :options="roleOptions" :searchable="false" />
          </label>
          <label class="field"><span>Status</span><ModernSelect v-model="genericForm.active" :options="activeOptions" :searchable="false" /></label>
        </template>

        <template v-else-if="activeTab === 'suppliers' || activeTab === 'online_shops'">
          <div class="form-grid-2">
            <label class="field"><span>{{ activeTab === 'online_shops' ? 'Kode Toko Online *' : 'Kode Supplier *' }}</span><input v-model="genericForm.code" required :placeholder="activeTab === 'online_shops' ? 'OL-04' : 'SUP-04'" /></label>
            <label class="field"><span>Telepon / CS</span><input v-model="genericForm.phone" placeholder="0812..." /></label>
          </div>
          <label class="field"><span>{{ activeTab === 'online_shops' ? 'Nama Toko Online *' : 'Nama Supplier *' }}</span><input v-model="genericForm.name" required :placeholder="activeTab === 'online_shops' ? 'Contoh: Shopee (Official Safety)' : 'Contoh: PT Mitra Safety'" /></label>
          <label class="field"><span>{{ activeTab === 'online_shops' ? 'Nama Akun / PIC' : 'Nama Kontak / PIC' }}</span><input v-model="genericForm.contactName" /></label>
          <label class="field"><span>{{ activeTab === 'online_shops' ? 'Link / Platform / Keterangan' : 'Alamat' }}</span><textarea v-model="genericForm.address" rows="2" :placeholder="activeTab === 'online_shops' ? 'Contoh: shopee.co.id/toko-safety' : ''" /></label>
        </template>

        <template v-else-if="activeTab === 'funders'">
          <label class="field"><span>Nama Pihak Penalang *</span><input v-model="genericForm.name" required placeholder="Nama perorangan / kas" /></label>
          <label class="field"><span>No. Telepon</span><input v-model="genericForm.phone" /></label>
          <label class="field"><span>Catatan</span><textarea v-model="genericForm.notes" rows="2" /></label>
        </template>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showGenericModal = false">Batal</button>
        <button type="submit" form="master-generic-form" class="primary-button" :disabled="saving">
          {{ saving ? 'Menyimpan...' : 'Simpan' }}
        </button>
      </template>
    </BaseModal>
  </div>
</template>
