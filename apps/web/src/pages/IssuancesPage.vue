<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { AlertTriangle, ArrowUpDown, CalendarRange, Edit3, Eye, PackageMinus, Plus, RotateCcw, Search, Trash2, Upload } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { api, attachmentUrl, conditionLabel, formatDate, formatNumber, generateUuid, getApiCacheVersion, uploadAttachment, variantLabel } from '@/lib/api'
import { itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface IssuanceRow {
  id: string; transaction_no: string; issued_at: string; employee_id: string; officer_name: string;
  handover_proof_key?: string | null; notes: string | null;
  employees?: { nik: string; name: string; position: string; departments?: { name: string } | null } | null;
  issuance_items: Array<{
    id: string; variant_id: string; condition: 'new' | 'used_good'; quantity: number;
    returned_quantity: number; resolved_lost_quantity: number; purpose: string;
    item_variants?: { size: string; items?: { code: string; name: string; unit: string; return_required: boolean } | null } | null
  }>
}

const route = useRoute()
const master = useMasterStore()
const toast = useToast()

const rows = ref<IssuanceRow[]>([])
const loading = ref(true)
const search = ref('')
const employeeFilter = ref('all')
const departmentFilter = ref('all')
const officerFilter = ref('all')
const itemFilter = ref('all')
const liabilityFilter = ref('all')
const dateFrom = ref('')
const dateTo = ref('')
const page = ref(1)
const showModal = ref(false)
const editingId = ref<string | null>(null)
const showPreviewModal = ref(false)
const previewRow = ref<IssuanceRow | null>(null)
const saving = ref(false)
const uploading = ref(false)

function openPreview(row: IssuanceRow) {
  previewRow.value = row
  showPreviewModal.value = true
}

const form = reactive({
  issuedAt: new Date().toISOString().slice(0, 10),
  employeeId: '',
  officerName: 'Petugas K3 / Gudang',
  handoverProofKey: '',
  notes: '',
  items: [] as Array<{ variantId: string; quantity: number; purpose: string }>,
})

const editingRow = computed(() => rows.value.find((r) => r.id === editingId.value) || null)

const sortDir = ref<'desc' | 'asc'>('desc')

const employeeFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Karyawan' },
  ...master.employees.map((e) => ({ value: e.id, label: e.name, sublabel: e.nik })),
])

const departmentFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Departemen' },
  ...master.departments.map((d) => ({ value: d.name, label: d.name, sublabel: d.code })),
])

const officerFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) if (r.officer_name) names.add(r.officer_name)
  for (const o of master.officers) if (o.name) names.add(o.name)
  return [
    { value: 'all', label: 'Semua Petugas' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const itemFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Barang APD' },
  ...master.variants.map((v) => ({ value: v.variant_id, label: variantLabel(v), sublabel: v.code })),
])

const liabilityFilterOptions = [
  { value: 'all', label: 'Semua Status Tanggungan' },
  { value: 'open', label: 'Masih Dibawa Karyawan' },
  { value: 'closed', label: 'Sudah Kembali / Lunas' },
  { value: 'consumable', label: 'Habis Pakai' },
]

const hasActiveFilters = computed(() =>
  Boolean(
    search.value.trim() ||
    employeeFilter.value !== 'all' ||
    departmentFilter.value !== 'all' ||
    officerFilter.value !== 'all' ||
    itemFilter.value !== 'all' ||
    liabilityFilter.value !== 'all' ||
    dateFrom.value ||
    dateTo.value,
  ),
)

function resetFilters() {
  search.value = ''
  employeeFilter.value = 'all'
  departmentFilter.value = 'all'
  officerFilter.value = 'all'
  itemFilter.value = 'all'
  liabilityFilter.value = 'all'
  dateFrom.value = ''
  dateTo.value = ''
}

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  const list = rows.value.filter((r) => {
    if (employeeFilter.value !== 'all' && r.employee_id !== employeeFilter.value) return false
    if (departmentFilter.value !== 'all' && (r.employees?.departments?.name || '') !== departmentFilter.value) return false
    if (officerFilter.value !== 'all' && r.officer_name !== officerFilter.value) return false
    if (itemFilter.value !== 'all' && !r.issuance_items.some((it) => it.variant_id === itemFilter.value)) return false
    if (liabilityFilter.value === 'open' && !r.issuance_items.some((it) => it.item_variants?.items?.return_required && (it.quantity - it.returned_quantity - it.resolved_lost_quantity) > 0)) return false
    if (liabilityFilter.value === 'closed' && !r.issuance_items.some((it) => it.item_variants?.items?.return_required && (it.quantity - it.returned_quantity - it.resolved_lost_quantity) <= 0)) return false
    if (liabilityFilter.value === 'consumable' && !r.issuance_items.some((it) => it.item_variants?.items?.return_required === false)) return false
    const d = (r.issued_at || '').slice(0, 10)
    if (dateFrom.value && d < dateFrom.value) return false
    if (dateTo.value && d > dateTo.value) return false
    if (!q) return true
    return (
      r.transaction_no.toLowerCase().includes(q) ||
      r.officer_name.toLowerCase().includes(q) ||
      (r.employees?.name || '').toLowerCase().includes(q) ||
      (r.employees?.nik || '').toLowerCase().includes(q) ||
      r.issuance_items.some((it) => (it.item_variants?.items?.name || '').toLowerCase().includes(q))
    )
  })
  return [...list].sort((a, b) => {
    const cmp = a.transaction_no.localeCompare(b.transaction_no, undefined, { numeric: true })
    return sortDir.value === 'asc' ? cmp : -cmp
  })
})

const pagedRows = computed(() => filtered.value.slice((page.value - 1) * 10, page.value * 10))
watch([search, employeeFilter, departmentFilter, officerFilter, itemFilter, liabilityFilter, dateFrom, dateTo], () => { page.value = 1 })

function variantInfo(variantId: string) {
  return master.variants.find((x) => x.variant_id === variantId) || null
}

function availableFor(variantId: string): number {
  const v = variantInfo(variantId)
  let base = !v ? 0 : Number(v.total_available)
  if (editingRow.value) {
    for (const old of editingRow.value.issuance_items) {
      if (old.variant_id === variantId) base += Number(old.quantity)
    }
  }
  return base
}

async function load() {
  loading.value = true
  try {
    const res = await api<{ data: IssuanceRow[] }>('/api/transactions/issuances')
    rows.value = res.data
  } finally {
    loading.value = false
  }
}

const activeOfficers = computed(() => master.officers.filter((o) => o.active))

const employeeOptions = computed(() =>
  master.employees.map((e) => ({
    value: e.id,
    label: e.name,
    sublabel: `${e.nik}${e.departments?.name ? ` · ${e.departments.name}` : ''}`,
  })),
)

const officerOptions = computed(() =>
  activeOfficers.value.map((off) => ({ value: off.name, label: off.name, sublabel: off.role_label })),
)

const variantOptions = computed(() =>
  master.variants.map((v) => ({
    value: v.variant_id,
    label: variantLabel(v),
    sublabel: `Kode ${v.code}`,
    badge: `${formatNumber(v.total_available)} ${v.unit}`,
    icon: v.photo_key ? attachmentUrl(v.photo_key) : itemFlaticonIcon(v.name),
  })),
)

async function openModal() {
  editingId.value = null
  form.issuedAt = new Date().toISOString().slice(0, 10)
  form.handoverProofKey = ''
  form.notes = ''
  showModal.value = true

  try {
    await master.refresh()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data master')
  }

  form.employeeId = master.employees[0]?.id || ''
  form.officerName = activeOfficers.value[0]?.name || 'Petugas K3 / Gudang'
  const firstAvailable = master.variants.find((v) => v.total_available > 0) || master.variants[0]
  form.items = [{
    variantId: firstAvailable?.variant_id || '',
    quantity: 1,
    purpose: 'Penggunaan kerja harian / proyek',
  }]
}

async function openEditModal(row: IssuanceRow) {
  editingId.value = row.id
  form.issuedAt = row.issued_at.slice(0, 10)
  form.employeeId = row.employee_id
  form.officerName = row.officer_name
  form.handoverProofKey = row.handover_proof_key || ''
  form.notes = row.notes || ''
  const grouped = new Map<string, { variantId: string; quantity: number; purpose: string }>()
  for (const it of row.issuance_items) {
    const prev = grouped.get(it.variant_id)
    if (prev) prev.quantity += Number(it.quantity)
    else grouped.set(it.variant_id, { variantId: it.variant_id, quantity: Number(it.quantity), purpose: it.purpose })
  }
  form.items = [...grouped.values()]
  showModal.value = true
  master.refresh(true).catch(() => {})
}

function addLine() {
  const firstAvailable = master.variants.find((v) => v.total_available > 0) || master.variants[0]
  form.items.push({
    variantId: firstAvailable?.variant_id || '',
    quantity: 1,
    purpose: 'Penggunaan kerja harian',
  })
}

async function handleUpload(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const res = await uploadAttachment(file)
    form.handoverProofKey = res.key
    toast.success('Bukti serah terima diunggah')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal mengunggah')
  } finally {
    uploading.value = false
  }
}

async function submit() {
  const valid = form.items.filter((i) => i.variantId && Number(i.quantity) > 0)
  if (!valid.length) {
    toast.error('Minimal 1 barang keluar wajib diisi')
    return
  }
  for (const line of valid) {
    const avail = availableFor(line.variantId)
    if (line.quantity > avail) {
      toast.error(`Stok tersedia tidak cukup untuk ${variantInfo(line.variantId)?.name || 'barang ini'} (tersedia ${avail})`)
      return
    }
  }
  saving.value = true
  try {
    const endpoint = editingId.value ? `/api/transactions/issuances/${editingId.value}` : '/api/transactions/issuances'
    const method = editingId.value ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      headers: editingId.value ? {} : { 'X-Idempotency-Key': generateUuid() },
      body: JSON.stringify({
        issuedAt: form.issuedAt,
        employeeId: form.employeeId,
        officerName: form.officerName,
        handoverProofKey: form.handoverProofKey || null,
        notes: form.notes || null,
        items: valid.map((l) => ({ ...l, condition: 'auto' })),
      }),
    })
    await Promise.all([load(), master.refresh(true)])
    toast.success(editingId.value ? 'Barang keluar berhasil diperbarui & stok disesuaikan!' : 'Barang keluar berhasil dicatat & stok tersedia otomatis berkurang!')
    showModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan barang keluar')
  } finally {
    saving.value = false
  }
}

async function deleteIssuance(row: IssuanceRow) {
  if (!window.confirm(`Hapus transaksi barang keluar "${row.transaction_no}"? Stok barang akan otomatis dikembalikan ke gudang.`)) return
  try {
    await api(`/api/transactions/issuances/${row.id}`, { method: 'DELETE' })
    await Promise.all([load(), master.refresh(true)])
    toast.success(`Barang keluar ${row.transaction_no} berhasil dihapus & stok dikembalikan`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus barang keluar')
  }
}

let lastCacheVer = -1
onMounted(() => {
  if (route.query.action === 'new') void openModal()
  lastCacheVer = getApiCacheVersion()
  void Promise.all([load(), master.refresh()])
})
onActivated(() => {
  if (route.query.action === 'new') void openModal()
  if (getApiCacheVersion() !== lastCacheVer) {
    lastCacheVer = getApiCacheVersion()
    void Promise.all([load(), master.refresh()])
  }
})
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Distribusi APD</p>
        <h2>Barang Keluar</h2>
        <p>Serahkan APD ke karyawan. Saldo stok tersedia otomatis berkurang dan tanggungan tercatat untuk APD wajib kembali.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openModal"><Plus :size="17" /> Catat Barang Keluar</button>
      </div>
    </section>

    <section class="panel data-panel">
      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Transaksi, karyawan, NIK, barang, atau petugas..." /></label>
        <div class="date-range-inline">
          <CalendarRange :size="15" />
          <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" />
          <span class="date-sep">s/d</span>
          <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" />
        </div>
        <ModernSelect v-model="employeeFilter" :options="employeeFilterOptions" compact searchable search-placeholder="Cari karyawan..." />
        <ModernSelect v-model="departmentFilter" :options="departmentFilterOptions" compact searchable search-placeholder="Cari departemen..." />
        <ModernSelect v-model="itemFilter" :options="itemFilterOptions" compact searchable search-placeholder="Cari barang APD..." />
        <ModernSelect v-model="officerFilter" :options="officerFilterOptions" compact searchable search-placeholder="Cari petugas..." />
        <ModernSelect v-model="liabilityFilter" :options="liabilityFilterOptions" compact searchable search-placeholder="Cari status tanggungan..." />
        <button v-if="hasActiveFilters" type="button" class="secondary-button xs" @click="resetFilters">
          <RotateCcw :size="13" /> Reset
        </button>
      </div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>
                <button type="button" class="th-sort-btn" @click="sortDir = sortDir === 'asc' ? 'desc' : 'asc'">
                  No. Transaksi <ArrowUpDown :size="13" /> <span>{{ sortDir === 'asc' ? '↑' : '↓' }}</span>
                </button>
              </th>
              <th>Penerima (Karyawan)</th><th>Barang Dikeluarkan</th><th>Status Tanggungan</th><th>Petugas</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td><strong>{{ row.transaction_no }}</strong><small class="table-sub">{{ formatDate(row.issued_at) }}</small></td>
              <td>
                <strong class="table-main">{{ row.employees?.name || '-' }}</strong>
                <small class="table-sub">{{ row.employees?.nik }} · {{ row.employees?.departments?.name || '-' }}</small>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="it in row.issuance_items" :key="it.id">
                    <strong>-{{ formatNumber(it.quantity) }} {{ it.item_variants?.items?.unit }}</strong>
                    {{ variantLabel({ name: it.item_variants?.items?.name, size: it.item_variants?.size }) }} · <em>{{ conditionLabel(it.condition) }}</em>
                  </span>
                </div>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="it in row.issuance_items" :key="it.id">
                    <template v-if="it.item_variants?.items?.return_required">
                      <span
                        class="status-pill"
                        :class="it.quantity - it.returned_quantity - it.resolved_lost_quantity > 0 ? 'amber' : 'safe'"
                      >
                        {{
                          it.quantity - it.returned_quantity - it.resolved_lost_quantity > 0
                            ? `Dibawa: ${formatNumber(it.quantity - it.returned_quantity - it.resolved_lost_quantity)}`
                            : 'Sudah Kembali'
                        }}
                      </span>
                    </template>
                    <span v-else class="tag-pill">Habis Pakai</span>
                  </span>
                </div>
              </td>
              <td>{{ row.officer_name }}</td>
              <td>
                <div class="row-actions">
                  <button class="icon-button" title="Preview detail barang keluar" @click="openPreview(row)"><Eye :size="15" /></button>
                  <button
                    class="icon-button"
                    :disabled="row.issuance_items.some((it) => it.returned_quantity > 0 || it.resolved_lost_quantity > 0)"
                    :title="row.issuance_items.some((it) => it.returned_quantity > 0 || it.resolved_lost_quantity > 0) ? 'Sudah ada pengembalian' : 'Edit barang keluar'"
                    @click="openEditModal(row)"
                  >
                    <Edit3 :size="15" />
                  </button>
                  <button
                    class="icon-button danger"
                    :disabled="row.issuance_items.some((it) => it.returned_quantity > 0 || it.resolved_lost_quantity > 0)"
                    :title="row.issuance_items.some((it) => it.returned_quantity > 0 || it.resolved_lost_quantity > 0) ? 'Hapus data pengembalian terkait terlebih dahulu' : 'Hapus barang keluar'"
                    @click="deleteIssuance(row)"
                  >
                    <Trash2 :size="15" />
                  </button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filtered.length">
              <td colspan="6"><div class="empty-state"><PackageMinus :size="32" /><strong>Belum ada barang keluar</strong><span>Klik "Catat Barang Keluar" untuk menyerahkan APD ke karyawan.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat data barang keluar...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filtered.length" />
    </section>

    <BaseModal
      :open="showPreviewModal"
      :title="`Detail Barang Keluar · ${previewRow?.transaction_no || ''}`"
      eyebrow="Preview Distribusi APD"
      :subtitle="previewRow ? `Tanggal Penyerahan: ${formatDate(previewRow.issued_at)}` : ''"
      size="lg"
      @close="showPreviewModal = false"
    >
      <div v-if="previewRow" class="detail-stack">
        <div class="summary-banner">
          <div><small>Karyawan Penerima</small><strong>{{ previewRow.employees?.name || '-' }} ({{ previewRow.employees?.nik || '-' }})</strong></div>
          <div><small>Departemen &amp; Jabatan</small><strong>{{ previewRow.employees?.departments?.name || '-' }} · {{ previewRow.employees?.position || '-' }}</strong></div>
          <div><small>Petugas Penyerah</small><strong>{{ previewRow.officer_name }}</strong></div>
        </div>
        <p v-if="previewRow.notes" class="muted-text" style="font-size:12.5px;"><strong>Catatan:</strong> {{ previewRow.notes }}</p>
        <div v-if="previewRow.handover_proof_key">
          <a :href="attachmentUrl(previewRow.handover_proof_key)" target="_blank" rel="noopener noreferrer" class="secondary-button xs highlight">
            Lihat Foto Bukti / Berita Acara ↗
          </a>
        </div>
        <div class="table-wrap" style="margin-top:0;">
          <table>
            <thead><tr><th>Barang &amp; Ukuran</th><th>Kondisi</th><th>Keluar</th><th>Kembali / Hilang</th><th>Sisa Dibawa</th><th>Keperluan</th></tr></thead>
            <tbody>
              <tr v-for="it in previewRow.issuance_items" :key="it.id">
                <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }) }}</strong></td>
                <td><span class="tag-pill">{{ conditionLabel(it.condition) }}</span></td>
                <td><span class="delta-pill minus">-{{ formatNumber(it.quantity) }} {{ it.item_variants?.items?.unit }}</span></td>
                <td>{{ formatNumber(it.returned_quantity) }} kembali / {{ formatNumber(it.resolved_lost_quantity) }} hilang</td>
                <td>
                  <strong v-if="it.item_variants?.items?.return_required" :class="it.quantity - it.returned_quantity - it.resolved_lost_quantity > 0 ? 'text-amber' : 'text-primary'">
                    {{ formatNumber(it.quantity - it.returned_quantity - it.resolved_lost_quantity) }} {{ it.item_variants?.items?.unit }}
                  </strong>
                  <span v-else class="tag-pill">Habis Pakai</span>
                </td>
                <td>{{ it.purpose }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showPreviewModal = false">Tutup</button>
        <button
          v-if="previewRow && !previewRow.issuance_items.some((it) => it.returned_quantity > 0 || it.resolved_lost_quantity > 0)"
          type="button"
          class="primary-button"
          @click="showPreviewModal = false; openEditModal(previewRow)"
        >
          <Edit3 :size="15" /> Edit Barang Keluar
        </button>
      </template>
    </BaseModal>

    <BaseModal
      :open="showModal"
      :title="editingId ? 'Edit Barang Keluar' : 'Catat Barang Keluar (Penyerahan APD)'"
      eyebrow="Distribusi Inventaris"
      subtitle="Pilih barang dan jumlah keluar; saldo stok tersedia otomatis berkurang."
      size="lg"
      @close="showModal = false"
    >
      <form id="issuance-form" class="modal-form" @submit.prevent="submit">
        <div class="form-grid-3">
          <label class="field"><span>Tanggal Penyerahan *</span><input v-model="form.issuedAt" type="date" required /></label>
          <label class="field"><span>Karyawan Penerima *</span>
            <ModernSelect v-model="form.employeeId" :options="employeeOptions" required />
          </label>
          <label class="field"><span>Petugas Penyerah *</span>
            <ModernSelect v-if="activeOfficers.length" v-model="form.officerName" :options="officerOptions" required />
            <input v-else v-model="form.officerName" required />
          </label>
        </div>

        <div class="lines-section">
          <div class="lines-header">
            <strong>Daftar APD yang Diserahkan</strong>
            <button type="button" class="secondary-button sm" @click="addLine"><Plus :size="14" /> Tambah Barang</button>
          </div>
          <div class="modal-lines-list">
            <div v-for="(line, idx) in form.items" :key="idx" class="modal-line-card">
              <div class="line-top">
                <ModernSelect v-model="line.variantId" :options="variantOptions" required search-placeholder="Cari APD..." style="flex:1;" />
                <button v-if="form.items.length > 1" type="button" class="icon-button danger" @click="form.items.splice(idx, 1)">
                  <Trash2 :size="15" />
                </button>
              </div>
              <div v-if="variantInfo(line.variantId)" class="variant-stock-chip">
                <div class="variant-stock-left">
                  <img
                    v-if="variantInfo(line.variantId)?.photo_key"
                    :src="attachmentUrl(variantInfo(line.variantId)?.photo_key)"
                    class="item-thumb sm"
                    alt="Foto barang"
                  />
                  <span><strong>{{ variantLabel(variantInfo(line.variantId)!) }}</strong> · Kode: {{ variantInfo(line.variantId)?.code }}</span>
                </div>
                <div class="variant-stock-right">
                  <span>Stok tersedia terakhir: <strong>{{ formatNumber(availableFor(line.variantId)) }} {{ variantInfo(line.variantId)?.unit }}</strong></span>
                  <span class="status-pill" :class="availableFor(line.variantId) <= 0 ? 'out' : availableFor(line.variantId) <= (variantInfo(line.variantId)?.minimum_stock || 0) ? 'low' : 'safe'">
                    {{ availableFor(line.variantId) <= 0 ? 'Habis' : availableFor(line.variantId) <= (variantInfo(line.variantId)?.minimum_stock || 0) ? 'Menipis' : 'Aman' }}
                  </span>
                </div>
              </div>
              <div class="form-grid-2">
                <label class="field">
                  <span>Jumlah Keluar (Maks {{ formatNumber(availableFor(line.variantId)) }} {{ variantInfo(line.variantId)?.unit || 'unit' }}) *</span>
                  <input v-model.number="line.quantity" type="number" min="0.01" :max="availableFor(line.variantId)" step="any" required />
                  <small v-if="line.quantity > availableFor(line.variantId)" class="error-hint">
                    <AlertTriangle :size="12" /> Melebihi stok tersedia!
                  </small>
                </label>
                <label class="field"><span>Keperluan / Lokasi *</span><input v-model="line.purpose" required placeholder="Proyek / Area kerja" /></label>
              </div>
            </div>
          </div>
        </div>

        <div class="form-grid-2">
          <label class="field"><span>Catatan</span><input v-model="form.notes" placeholder="Opsional" /></label>
          <label class="field"><span>Foto Bukti / Berita Acara</span>
            <label class="file-upload-inline">
              <Upload :size="15" />
              <span>{{ uploading ? 'Mengunggah...' : (form.handoverProofKey ? 'File terunggah ✓' : 'Unggah JPG/PNG/PDF') }}</span>
              <input type="file" accept=".jpg,.jpeg,.png,.webp,.pdf" hidden @change="handleUpload" />
            </label>
          </label>
        </div>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showModal = false">Batal</button>
        <button type="submit" form="issuance-form" class="primary-button" :disabled="saving">
          {{ saving ? 'Menyimpan...' : (editingId ? 'Simpan Perubahan' : 'Simpan Barang Keluar') }}
        </button>
      </template>
    </BaseModal>
  </div>
</template>
