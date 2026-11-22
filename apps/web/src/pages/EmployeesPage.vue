<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import {
  AlertTriangle, CheckCircle2, Edit3, Eye, History, PackageCheck, PackageMinus, Plus, Search, Trash2, UsersRound,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, conditionLabel, formatDate, formatNumber, variantLabel } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore, type Employee } from '@/stores/master'

interface IssuanceRecord {
  id: string
  transaction_no: string
  issued_at: string
  employee_id: string
  officer_name: string
  notes: string | null
  issuance_items: Array<{
    id: string
    variant_id: string
    condition: string
    quantity: number
    returned_quantity: number
    resolved_lost_quantity: number
    purpose: string
    item_variants?: { size: string; items?: { code: string; name: string; unit: string; return_required: boolean } | null } | null
  }>
}

interface ReturnRecord {
  id: string
  transaction_no: string
  returned_at: string
  employee_id: string
  inspector_name: string
  return_items: Array<{
    id: string
    quantity: number
    result: 'used_good' | 'maintenance' | 'damaged' | 'lost'
    reason: string | null
    issuance_items?: { item_variants?: { size: string; items?: { name: string; unit: string } | null } | null } | null
  }>
}

const master = useMasterStore()
const toast = useToast()

const loading = ref(true)
const search = ref('')
const filterMode = ref<'all' | 'holding' | 'clear' | 'returned'>('all')
const page = ref(1)

const issuances = ref<IssuanceRecord[]>([])
const returns = ref<ReturnRecord[]>([])

// Add/Edit Employee Modal
const showFormModal = ref(false)
const editingId = ref<string | null>(null)
const saving = ref(false)
const form = reactive({
  nik: '',
  name: '',
  position: '',
  departmentId: '',
  contractStatus: 'permanent' as 'permanent' | 'contract' | 'intern' | 'inactive',
})

// Detail & History Modal
const showDetailModal = ref(false)
const activeEmployee = ref<Employee | null>(null)
const detailTab = ref<'holding' | 'issued' | 'returned'>('holding')

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

function openStatHistory(kind: 'all' | 'holding' | 'clear' | 'returned') {
  statModalOpen.value = true
  if (kind === 'all') {
    statModalTitle.value = 'Daftar Seluruh Karyawan'
    statModalSubtitle.value = `Total ${employeeSummaries.value.length} karyawan terdaftar`
    statModalEmpty.value = 'Belum ada data karyawan.'
    statModalColumns.value = [
      { key: 'emp', label: 'Karyawan' },
      { key: 'dept', label: 'Departemen' },
      { key: 'status', label: 'Status' },
      { key: 'holding', label: 'APD Dipegang' },
      { key: 'returns', label: 'Riwayat Kembali' },
    ]
    statModalRows.value = employeeSummaries.value.map((s) => ({
      emp: { text: s.employee.name, sub: `NIK: ${s.employee.nik} · ${s.employee.position}`, strong: true },
      dept: s.employee.departments?.name || '-',
      status: contractLabel(s.employee.contract_status),
      holding: { text: `${formatNumber(s.totalHoldingUnits)} unit`, pill: s.totalHoldingUnits > 0 ? 'amber' : 'safe' },
      returns: `${s.returnHistory.length} transaksi`,
    }))
  } else if (kind === 'holding') {
    statModalTitle.value = 'Riwayat APD Aktif yang Sedang Dipegang Karyawan'
    statModalSubtitle.value = `${totalHoldingEmployees.value} karyawan memegang total ${formatNumber(totalHoldingUnitsAll.value)} unit APD`
    statModalEmpty.value = 'Tidak ada APD yang sedang dipegang karyawan.'
    statModalColumns.value = [
      { key: 'emp', label: 'Karyawan' },
      { key: 'doc', label: 'No. & Tanggal Keluar' },
      { key: 'item', label: 'Alat APD' },
      { key: 'qty', label: 'Sedang Dipegang' },
      { key: 'purpose', label: 'Keperluan' },
    ]
    const out: Array<Record<string, HistoryCell>> = []
    for (const s of employeeSummaries.value) {
      for (const a of s.activeItems) {
        out.push({
          emp: { text: s.employee.name, sub: `${s.employee.nik} · ${s.employee.departments?.name || '-'}`, strong: true },
          doc: { text: a.txNo, sub: formatDate(a.issuedAt) },
          item: { text: a.itemName, strong: true },
          qty: { text: `${formatNumber(a.remaining)} ${a.unit}`, pill: 'amber' },
          purpose: a.purpose || '-',
        })
      }
    }
    statModalRows.value = out
  } else if (kind === 'clear') {
    const list = employeeSummaries.value.filter((s) => s.totalHoldingUnits <= 0)
    statModalTitle.value = 'Daftar Karyawan Bebas Tanggungan APD'
    statModalSubtitle.value = `${list.length} karyawan tidak sedang memegang APD wajib kembali`
    statModalEmpty.value = 'Semua karyawan sedang memegang APD.'
    statModalColumns.value = [
      { key: 'emp', label: 'Karyawan' },
      { key: 'dept', label: 'Departemen' },
      { key: 'issuedCount', label: 'Total Pernah Terima' },
      { key: 'returnedCount', label: 'Total Pengembalian' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = list.map((s) => ({
      emp: { text: s.employee.name, sub: `NIK: ${s.employee.nik} · ${s.employee.position}`, strong: true },
      dept: s.employee.departments?.name || '-',
      issuedCount: `${s.issuedHistory.length} riwayat`,
      returnedCount: `${s.returnHistory.length} riwayat`,
      status: { text: 'Bebas Tanggungan', pill: 'safe' },
    }))
  } else {
    statModalTitle.value = 'Riwayat Pengembalian & Kehilangan APD Karyawan'
    statModalSubtitle.value = `Total ${totalReturnedEvents.value} catatan pengembalian / kehilangan APD`
    statModalEmpty.value = 'Belum ada riwayat pengembalian APD.'
    statModalColumns.value = [
      { key: 'date', label: 'Tanggal & No. Dokumen' },
      { key: 'emp', label: 'Karyawan' },
      { key: 'item', label: 'Barang APD' },
      { key: 'qty', label: 'Jumlah' },
      { key: 'result', label: 'Hasil' },
      { key: 'reason', label: 'Catatan' },
    ]
    const out: Array<Record<string, HistoryCell>> = []
    for (const s of employeeSummaries.value) {
      for (const r of s.returnHistory) {
        out.push({
          date: { text: r.txNo, sub: formatDate(r.returnedAt), strong: true },
          emp: { text: s.employee.name, sub: s.employee.nik },
          item: { text: r.itemName, strong: true },
          qty: `${formatNumber(r.qty)} ${r.unit}`,
          result: { text: r.result === 'lost' ? 'Hilang' : conditionLabel(r.result), pill: r.result === 'lost' ? 'out' : 'safe' },
          reason: r.reason || '-',
        })
      }
    }
    statModalRows.value = out
  }
}

const contractOptions = [
  { value: 'permanent', label: 'Tetap' },
  { value: 'contract', label: 'Kontrak' },
  { value: 'intern', label: 'Magang' },
  { value: 'inactive', label: 'Nonaktif' },
]

const departmentOptions = computed(() =>
  master.departments.map((d) => ({ value: d.id, label: d.name, sublabel: d.code })),
)

interface EmployeeApdSummary {
  employee: Employee
  activeItems: Array<{
    txNo: string
    issuedAt: string
    itemName: string
    unit: string
    remaining: number
    purpose: string
  }>
  totalHoldingUnits: number
  issuedHistory: Array<{
    txNo: string
    issuedAt: string
    officer: string
    itemName: string
    unit: string
    qty: number
    condition: string
    purpose: string
  }>
  returnHistory: Array<{
    txNo: string
    returnedAt: string
    inspector: string
    itemName: string
    unit: string
    qty: number
    result: string
    reason: string | null
  }>
}

const employeeSummaries = computed<EmployeeApdSummary[]>(() => {
  const issuedByEmp = new Map<string, IssuanceRecord[]>()
  for (const iss of issuances.value) {
    const arr = issuedByEmp.get(iss.employee_id) ?? []
    arr.push(iss)
    issuedByEmp.set(iss.employee_id, arr)
  }
  const returnedByEmp = new Map<string, ReturnRecord[]>()
  for (const ret of returns.value) {
    const arr = returnedByEmp.get(ret.employee_id) ?? []
    arr.push(ret)
    returnedByEmp.set(ret.employee_id, arr)
  }

  return master.employees.map((employee) => {
    const empIss = issuedByEmp.get(employee.id) ?? []
    const empRet = returnedByEmp.get(employee.id) ?? []
    const activeItems: EmployeeApdSummary['activeItems'] = []
    const issuedHistory: EmployeeApdSummary['issuedHistory'] = []

    for (const iss of empIss) {
      for (const it of iss.issuance_items ?? []) {
        const itemName = variantLabel({
          name: it.item_variants?.items?.name || 'Barang APD',
          size: it.item_variants?.size,
        })
        const unit = it.item_variants?.items?.unit || 'unit'
        issuedHistory.push({
          txNo: iss.transaction_no,
          issuedAt: iss.issued_at,
          officer: iss.officer_name,
          itemName,
          unit,
          qty: Number(it.quantity),
          condition: conditionLabel(it.condition),
          purpose: it.purpose,
        })
        const rem = Number(it.quantity) - Number(it.returned_quantity) - Number(it.resolved_lost_quantity)
        if (rem > 0 && it.item_variants?.items?.return_required !== false) {
          activeItems.push({
            txNo: iss.transaction_no,
            issuedAt: iss.issued_at,
            itemName,
            unit,
            remaining: rem,
            purpose: it.purpose,
          })
        }
      }
    }

    const returnHistory: EmployeeApdSummary['returnHistory'] = []
    for (const ret of empRet) {
      for (const it of ret.return_items ?? []) {
        returnHistory.push({
          txNo: ret.transaction_no,
          returnedAt: ret.returned_at,
          inspector: ret.inspector_name,
          itemName: variantLabel({
            name: it.issuance_items?.item_variants?.items?.name || 'Barang APD',
            size: it.issuance_items?.item_variants?.size,
          }),
          unit: it.issuance_items?.item_variants?.items?.unit || 'unit',
          qty: Number(it.quantity),
          result: it.result,
          reason: it.reason,
        })
      }
    }

    return {
      employee,
      activeItems,
      totalHoldingUnits: activeItems.reduce((s, a) => s + a.remaining, 0),
      issuedHistory,
      returnHistory,
    }
  })
})

const totalHoldingEmployees = computed(() => employeeSummaries.value.filter((s) => s.totalHoldingUnits > 0).length)
const totalHoldingUnitsAll = computed(() => employeeSummaries.value.reduce((s, x) => s + x.totalHoldingUnits, 0))
const totalReturnedEvents = computed(() => employeeSummaries.value.reduce((s, x) => s + x.returnHistory.length, 0))

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  return employeeSummaries.value.filter((row) => {
    if (filterMode.value === 'holding' && row.totalHoldingUnits <= 0) return false
    if (filterMode.value === 'clear' && row.totalHoldingUnits > 0) return false
    if (filterMode.value === 'returned' && row.returnHistory.length === 0) return false
    if (!q) return true
    return (
      row.employee.name.toLowerCase().includes(q) ||
      row.employee.nik.toLowerCase().includes(q) ||
      row.employee.position.toLowerCase().includes(q) ||
      (row.employee.departments?.name || '').toLowerCase().includes(q) ||
      row.activeItems.some((a) => a.itemName.toLowerCase().includes(q))
    )
  })
})

const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * 10, page.value * 10))
watch([search, filterMode], () => { page.value = 1 })

const activeSummary = computed(() =>
  activeEmployee.value ? employeeSummaries.value.find((s) => s.employee.id === activeEmployee.value?.id) || null : null,
)

function contractLabel(c: string) {
  const map: Record<string, string> = { permanent: 'Tetap', contract: 'Kontrak', intern: 'Magang', inactive: 'Nonaktif' }
  return map[c] || c
}

async function load() {
  loading.value = true
  try {
    const [issRes, retRes] = await Promise.all([
      api<{ data: IssuanceRecord[] }>('/api/transactions/issuances'),
      api<{ data: ReturnRecord[] }>('/api/transactions/returns'),
      master.refresh(),
    ])
    issuances.value = issRes.data
    returns.value = retRes.data
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data karyawan')
  } finally {
    loading.value = false
  }
}

function openAdd() {
  editingId.value = null
  form.nik = ''
  form.name = ''
  form.position = ''
  form.departmentId = master.departments[0]?.id || ''
  form.contractStatus = 'permanent'
  showFormModal.value = true
}

function openEdit(emp: Employee) {
  editingId.value = emp.id
  form.nik = emp.nik
  form.name = emp.name
  form.position = emp.position
  form.departmentId = emp.department_id
  form.contractStatus = (emp.contract_status as typeof form.contractStatus) || 'permanent'
  showFormModal.value = true
}

function openHistory(emp: Employee) {
  activeEmployee.value = emp
  detailTab.value = 'holding'
  showDetailModal.value = true
}

async function submitEmployee() {
  saving.value = true
  try {
    const id = editingId.value
    const endpoint = id ? `/api/master/employees/${id}` : '/api/master/employees'
    const method = id ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      body: JSON.stringify({
        nik: form.nik,
        name: form.name,
        position: form.position,
        departmentId: form.departmentId,
        contractStatus: form.contractStatus,
      }),
    })
    await master.refresh(true)
    toast.success(id ? 'Data karyawan berhasil diperbarui' : 'Karyawan baru berhasil ditambahkan')
    showFormModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan data karyawan')
  } finally {
    saving.value = false
  }
}

async function deleteEmployee(emp: Employee) {
  if (!window.confirm(`Hapus data karyawan "${emp.name}" secara permanen?`)) return
  try {
    await api(`/api/master/employees/${emp.id}`, { method: 'DELETE' })
    await master.refresh(true)
    toast.success(`Karyawan "${emp.name}" berhasil dihapus`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus karyawan')
  }
}

onMounted(load)
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Pelacakan Pemegang & Riwayat APD</p>
        <h2>Karyawan &amp; Tanggungan APD</h2>
        <p>Pantau APD yang sedang dipegang setiap karyawan, riwayat penyerahan, dan catatan pengembalian atau kehilangan.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openAdd"><Plus :size="17" /> Tambah Karyawan</button>
      </div>
    </section>

    <section class="inv-stats-grid">
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('all')">
        <div class="inv-stat-icon"><UsersRound :size="22" /></div>
        <div>
          <span>Total Karyawan</span>
          <strong>{{ master.employees.length }}</strong>
          <small>Klik lihat daftar karyawan</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('holding')">
        <div class="inv-stat-icon"><PackageMinus :size="22" /></div>
        <div>
          <span>Sedang Pegang APD</span>
          <strong>{{ totalHoldingEmployees }}</strong>
          <small>{{ formatNumber(totalHoldingUnitsAll) }} unit aktif · klik rincian</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('clear')">
        <div class="inv-stat-icon"><CheckCircle2 :size="22" /></div>
        <div>
          <span>Bebas Tanggungan</span>
          <strong>{{ Math.max(0, master.employees.length - totalHoldingEmployees) }}</strong>
          <small>Klik daftar bebas tanggungan</small>
        </div>
      </button>
      <button type="button" class="inv-stat-card clickable modern-hover-card" @click="openStatHistory('returned')">
        <div class="inv-stat-icon"><PackageCheck :size="22" /></div>
        <div>
          <span>Riwayat Pengembalian</span>
          <strong>{{ totalReturnedEvents }}</strong>
          <small>Klik riwayat kembali / hilang</small>
        </div>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: filterMode === 'all' }" @click="filterMode = 'all'">Semua Karyawan ({{ master.employees.length }})</button>
        <button :class="{ active: filterMode === 'holding' }" @click="filterMode = 'holding'">Pegang APD Aktif ({{ totalHoldingEmployees }})</button>
        <button :class="{ active: filterMode === 'clear' }" @click="filterMode = 'clear'">Bebas Tanggungan</button>
        <button :class="{ active: filterMode === 'returned' }" @click="filterMode = 'returned'">Ada Riwayat Kembali</button>
      </div>
      <div class="table-toolbar">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari NIK, nama karyawan, departemen, atau nama APD..." /></label>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>NIK &amp; Karyawan</th>
              <th>Jabatan &amp; Departemen</th>
              <th>Status</th>
              <th>APD Sedang Dipegang</th>
              <th>Riwayat Kembali</th>
              <th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.employee.id">
              <td>
                <span class="item-cell">
                  <i>{{ row.employee.name.slice(0, 2).toUpperCase() }}</i>
                  <span><strong>{{ row.employee.name }}</strong><small>{{ row.employee.nik }}</small></span>
                </span>
              </td>
              <td>
                <strong class="table-main">{{ row.employee.position }}</strong>
                <small class="table-sub">{{ row.employee.departments?.name || '-' }}</small>
              </td>
              <td><span class="tag-pill">{{ contractLabel(row.employee.contract_status) }}</span></td>
              <td>
                <div v-if="row.activeItems.length" class="compact-items">
                  <span v-for="(item, idx) in row.activeItems.slice(0, 3)" :key="idx">
                    <strong>{{ formatNumber(item.remaining) }} {{ item.unit }}</strong> {{ item.itemName }}
                  </span>
                  <small v-if="row.activeItems.length > 3" class="table-sub">+{{ row.activeItems.length - 3 }} item lainnya</small>
                </div>
                <span v-else class="status-pill safe">Tidak ada tanggungan</span>
              </td>
              <td>
                <span class="tag-pill">{{ row.returnHistory.length }} catatan</span>
              </td>
              <td>
                <div class="row-actions">
                  <button class="secondary-button xs" title="Lihat detail & riwayat APD karyawan" @click="openHistory(row.employee)">
                    <Eye :size="13" /> Riwayat APD
                  </button>
                  <button class="icon-button" title="Edit karyawan" @click="openEdit(row.employee)"><Edit3 :size="15" /></button>
                  <button class="icon-button danger" title="Hapus karyawan" @click="deleteEmployee(row.employee)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="6"><div class="empty-state compact"><UsersRound :size="28" /><strong>Tidak ada karyawan yang cocok</strong><span>Ubah filter atau tambahkan data karyawan baru.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat data karyawan &amp; riwayat APD...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <!-- Add / Edit Employee Modal -->
    <BaseModal :open="showFormModal" :title="editingId ? 'Edit Karyawan' : 'Tambah Karyawan Baru'" eyebrow="Manajemen Karyawan" size="sm" @close="showFormModal = false">
      <form id="employee-form" class="modal-form" @submit.prevent="submitEmployee">
        <div class="form-grid-2">
          <label class="field"><span>NIK *</span><input v-model="form.nik" required placeholder="RIA-2026-001" /></label>
          <label class="field"><span>Status Kontrak</span>
            <ModernSelect v-model="form.contractStatus" :options="contractOptions" :searchable="false" />
          </label>
        </div>
        <label class="field"><span>Nama Lengkap *</span><input v-model="form.name" required /></label>
        <div class="form-grid-2">
          <label class="field"><span>Jabatan *</span><input v-model="form.position" required /></label>
          <label class="field"><span>Departemen *</span>
            <ModernSelect v-model="form.departmentId" :options="departmentOptions" required placeholder="Pilih departemen" />
          </label>
        </div>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showFormModal = false">Batal</button>
        <button type="submit" form="employee-form" class="primary-button" :disabled="saving">
          {{ saving ? 'Menyimpan...' : 'Simpan Karyawan' }}
        </button>
      </template>
    </BaseModal>

    <!-- Employee APD Detail & History Modal -->
    <BaseModal
      :open="showDetailModal"
      :title="`Riwayat APD — ${activeEmployee?.name || ''}`"
      eyebrow="Kartu Pemegang APD Karyawan"
      :subtitle="activeEmployee ? `${activeEmployee.nik} · ${activeEmployee.position} (${activeEmployee.departments?.name || '-'})` : ''"
      size="lg"
      @close="showDetailModal = false"
    >
      <div v-if="activeSummary" class="detail-stack">
        <div class="summary-banner">
          <div><small>APD Sedang Dipegang</small><strong>{{ formatNumber(activeSummary.totalHoldingUnits) }} unit ({{ activeSummary.activeItems.length }} item)</strong></div>
          <div><small>Total Pernah Diterima</small><strong>{{ activeSummary.issuedHistory.length }} kali penyerahan</strong></div>
          <div><small>Riwayat Pengembalian</small><strong>{{ activeSummary.returnHistory.length }} catatan</strong></div>
        </div>

        <div class="record-tabs" style="padding: 0; margin-top: -6px;">
          <button :class="{ active: detailTab === 'holding' }" @click="detailTab = 'holding'">
            Sedang Dipegang ({{ activeSummary.activeItems.length }})
          </button>
          <button :class="{ active: detailTab === 'issued' }" @click="detailTab = 'issued'">
            Riwayat Diterima ({{ activeSummary.issuedHistory.length }})
          </button>
          <button :class="{ active: detailTab === 'returned' }" @click="detailTab = 'returned'">
            Riwayat Dikembalikan / Hilang ({{ activeSummary.returnHistory.length }})
          </button>
        </div>

        <div v-if="detailTab === 'holding'" class="table-wrap" style="margin-top: 0;">
          <table>
            <thead><tr><th>No. Transaksi</th><th>Tanggal</th><th>Nama APD</th><th>Jumlah Dipegang</th><th>Keperluan</th></tr></thead>
            <tbody>
              <tr v-for="(it, idx) in activeSummary.activeItems" :key="idx">
                <td><strong>{{ it.txNo }}</strong></td>
                <td>{{ formatDate(it.issuedAt) }}</td>
                <td><strong>{{ it.itemName }}</strong></td>
                <td><span class="status-pill amber">{{ formatNumber(it.remaining) }} {{ it.unit }}</span></td>
                <td>{{ it.purpose }}</td>
              </tr>
              <tr v-if="!activeSummary.activeItems.length">
                <td colspan="5"><div class="empty-state compact"><CheckCircle2 :size="22" /><strong>Tidak ada APD aktif yang sedang dipegang.</strong></div></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-else-if="detailTab === 'issued'" class="table-wrap" style="margin-top: 0;">
          <table>
            <thead><tr><th>No. Keluar</th><th>Tanggal</th><th>Nama APD</th><th>Jumlah</th><th>Kondisi</th><th>Petugas</th></tr></thead>
            <tbody>
              <tr v-for="(it, idx) in activeSummary.issuedHistory" :key="idx">
                <td><strong>{{ it.txNo }}</strong></td>
                <td>{{ formatDate(it.issuedAt) }}</td>
                <td><strong>{{ it.itemName }}</strong><small class="table-sub">{{ it.purpose }}</small></td>
                <td>{{ formatNumber(it.qty) }} {{ it.unit }}</td>
                <td>{{ it.condition }}</td>
                <td>{{ it.officer }}</td>
              </tr>
              <tr v-if="!activeSummary.issuedHistory.length">
                <td colspan="6"><div class="empty-state compact"><History :size="22" /><strong>Belum ada riwayat penyerahan APD.</strong></div></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-else class="table-wrap" style="margin-top: 0;">
          <table>
            <thead><tr><th>No. Kembali</th><th>Tanggal</th><th>Nama APD</th><th>Jumlah</th><th>Status</th><th>Keterangan</th></tr></thead>
            <tbody>
              <tr v-for="(it, idx) in activeSummary.returnHistory" :key="idx">
                <td><strong>{{ it.txNo }}</strong></td>
                <td>{{ formatDate(it.returnedAt) }}</td>
                <td><strong>{{ it.itemName }}</strong></td>
                <td>{{ formatNumber(it.qty) }} {{ it.unit }}</td>
                <td>
                  <span class="status-pill" :class="it.result === 'lost' ? 'out' : 'safe'">
                    <AlertTriangle v-if="it.result === 'lost'" :size="11" />
                    {{ it.result === 'lost' ? 'Hilang' : 'Dikembalikan' }}
                  </span>
                </td>
                <td>{{ it.reason || '-' }}</td>
              </tr>
              <tr v-if="!activeSummary.returnHistory.length">
                <td colspan="6"><div class="empty-state compact"><PackageCheck :size="22" /><strong>Belum ada riwayat pengembalian APD.</strong></div></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </BaseModal>

    <StatHistoryModal
      :open="statModalOpen"
      :title="statModalTitle"
      :subtitle="statModalSubtitle"
      :columns="statModalColumns"
      :rows="statModalRows"
      :empty-text="statModalEmpty"
      @close="statModalOpen = false"
    />
  </div>
</template>
