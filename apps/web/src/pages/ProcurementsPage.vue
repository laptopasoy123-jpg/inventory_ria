<script setup lang="ts">
import { computed, onActivated, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowUpDown, CalendarRange, CheckCircle2, Edit3, Eye, PackageCheck, Plus, RotateCcw, Search, ShoppingBag, Trash2, Truck, XCircle } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import ReceiptModal from '@/components/ReceiptModal.vue'
import StatHistoryModal, { type HistoryCell, type HistoryColumn } from '@/components/StatHistoryModal.vue'
import { api, attachmentUrl, formatCurrency, formatDate, formatNumber, generateUuid, getApiCacheVersion, variantLabel } from '@/lib/api'
import { itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface ProcurementRow {
  id: string
  procurement_no: string
  po_number: string | null
  supplier_name: string
  funding_source: 'company' | 'advanced'
  funder_name: string | null
  total_amount: number
  paid_amount: number
  remaining_amount: number
  payment_status: 'unpaid' | 'partial' | 'paid'
  reimbursement_status: string | null
  reimbursed_amount: number
  procurement_date: string
  expected_date: string | null
  pr_number: string | null
  department_id?: string | null
  department_name: string | null
  supplier_id?: string
  vendor_type?: 'supplier' | 'online_shop'
  payment_method?: 'cash' | 'transfer'
  funder_id?: string | null
  reason: string
  notes?: string | null
  total_ordered: number
  total_received: number
  progress_percent: number
  status: 'draft' | 'ordered' | 'partial' | 'completed' | 'cancelled'
  items: Array<{
    id: string; variant_id: string; ordered_quantity: number; received_quantity: number; unit_price: number; notes?: string | null;
    item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null
  }>
}

interface ProcurementDetail extends ProcurementRow {
  receipts: Array<{ id: string; transaction_no: string; received_date: string; delivery_note_number: string | null }>
  payments: Array<{ id: string; paid_at: string; amount: number; payment_type: string; payment_method: string; reference_no: string | null }>
}

const route = useRoute()
const master = useMasterStore()
const toast = useToast()

const rows = ref<ProcurementRow[]>([])
const loading = ref(true)
const statusFilter = ref('all')
const search = ref('')
const supplierFilter = ref('all')
const vendorTypeFilter = ref('all')
const departmentFilter = ref('all')
const fundingFilter = ref('all')
const methodFilter = ref('all')
const dateFrom = ref('')
const dateTo = ref('')
const page = ref(1)

// Create / Edit Modal
const showCreateModal = ref(false)
const editingProcId = ref<string | null>(null)
const saving = ref(false)
const vendorKind = ref<'supplier' | 'online_shop'>('online_shop')
const form = reactive({
  procurementDate: new Date().toISOString().slice(0, 10),
  expectedDate: '',
  prNumber: '',
  poNumber: '',
  departmentId: '',
  supplierId: '',
  reason: '',
  fundingSource: 'company' as 'company' | 'advanced',
  paymentMethod: 'transfer' as 'cash' | 'transfer',
  funderId: '',
  notes: '',
  items: [] as Array<{ id?: string; variantId: string; orderedQuantity: number; unitPrice: number; notes: string }>,
})

// Detail Modal
const showDetailModal = ref(false)
const detail = ref<ProcurementDetail | null>(null)
const loadingDetail = ref(false)

// Receipt direct modal
const showReceiptModal = ref(false)
const receiptProcId = ref<string | null>(null)

// Cancel with Note Confirmation Modal
const showCancelModal = ref(false)
const cancellingRow = ref<ProcurementRow | null>(null)
const cancelNote = ref('')
const cancelling = ref(false)

const sortDir = ref<'desc' | 'asc'>('desc')

const supplierFilterOptions = computed(() => {
  const names = new Set<string>()
  for (const r of rows.value) if (r.supplier_name) names.add(r.supplier_name)
  for (const s of master.suppliers) if (s.name) names.add(s.name)
  return [
    { value: 'all', label: 'Semua Supplier / Toko' },
    ...[...names].sort((a, b) => a.localeCompare(b)).map((n) => ({ value: n, label: n })),
  ]
})

const vendorTypeFilterOptions = [
  { value: 'all', label: 'Semua Jenis Vendor' },
  { value: 'supplier', label: 'Supplier Resmi' },
  { value: 'online_shop', label: 'Toko Online' },
]

const departmentFilterOptions = computed(() => [
  { value: 'all', label: 'Semua Departemen' },
  ...master.departments.map((d) => ({ value: d.name, label: d.name, sublabel: d.code })),
])

const fundingFilterOptions = [
  { value: 'all', label: 'Semua Sumber Dana' },
  { value: 'company', label: 'Dana Perusahaan' },
  { value: 'advanced', label: 'Talangan' },
]

const methodFilterOptions = [
  { value: 'all', label: 'Semua Metode' },
  { value: 'transfer', label: 'Transfer Bank' },
  { value: 'cash', label: 'Tunai / Kas' },
]

const hasActiveFilters = computed(() =>
  Boolean(
    search.value.trim() ||
    supplierFilter.value !== 'all' ||
    vendorTypeFilter.value !== 'all' ||
    departmentFilter.value !== 'all' ||
    fundingFilter.value !== 'all' ||
    methodFilter.value !== 'all' ||
    dateFrom.value ||
    dateTo.value,
  ),
)

function resetFilters() {
  search.value = ''
  supplierFilter.value = 'all'
  vendorTypeFilter.value = 'all'
  departmentFilter.value = 'all'
  fundingFilter.value = 'all'
  methodFilter.value = 'all'
  dateFrom.value = ''
  dateTo.value = ''
}

const filteredRows = computed(() => {
  const list = rows.value.filter((r) => {
    if (statusFilter.value === 'pending_progress' && !(r.status === 'ordered' || r.status === 'partial')) return false
    else if (statusFilter.value !== 'all' && statusFilter.value !== 'pending_progress' && r.status !== statusFilter.value) return false
    if (supplierFilter.value !== 'all' && r.supplier_name !== supplierFilter.value) return false
    if (vendorTypeFilter.value !== 'all' && (r.vendor_type || 'supplier') !== vendorTypeFilter.value) return false
    if (departmentFilter.value !== 'all' && (r.department_name || '') !== departmentFilter.value) return false
    if (fundingFilter.value !== 'all' && r.funding_source !== fundingFilter.value) return false
    if (methodFilter.value !== 'all' && (r.payment_method || 'transfer') !== methodFilter.value) return false
    const d = (r.procurement_date || '').slice(0, 10)
    if (dateFrom.value && d < dateFrom.value) return false
    if (dateTo.value && d > dateTo.value) return false
    if (!search.value.trim()) return true
    const q = search.value.toLowerCase()
    return (
      r.procurement_no.toLowerCase().includes(q) ||
      (r.po_number || '').toLowerCase().includes(q) ||
      (r.pr_number || '').toLowerCase().includes(q) ||
      r.supplier_name.toLowerCase().includes(q) ||
      r.reason.toLowerCase().includes(q) ||
      r.items.some((it) => (it.item_variants?.items?.name || '').toLowerCase().includes(q))
    )
  })
  return [...list].sort((a, b) => {
    const cmp = a.procurement_no.localeCompare(b.procurement_no, undefined, { numeric: true })
    return sortDir.value === 'asc' ? cmp : -cmp
  })
})

const filteredModalVendors = computed(() => {
  const list = master.suppliers.filter((s) => (s.vendor_type || 'supplier') === vendorKind.value)
  return list.length ? list : master.suppliers
})

const departmentOptions = computed(() => [
  { value: '', label: 'Umum / Semua Departemen' },
  ...master.departments.map((d) => ({ value: d.id, label: d.name, sublabel: d.code })),
])

const modalVendorOptions = computed(() =>
  filteredModalVendors.value.map((s) => ({
    value: s.id,
    label: s.name,
    sublabel: s.contact_name || s.address || undefined,
    badge: s.code,
  })),
)

const fundingOptions = [
  { value: 'company', label: 'Dana Perusahaan' },
  { value: 'advanced', label: 'Ditalangi (Reimbursement)' },
]

const payMethodOptions = [
  { value: 'transfer', label: 'Transfer Bank' },
  { value: 'cash', label: 'Tunai / Kas' },
]

const funderOptions = computed(() =>
  master.funders.map((f) => ({ value: f.id, label: f.name, sublabel: f.notes || undefined })),
)

const variantOptions = computed(() =>
  master.variants.map((v) => ({
    value: v.variant_id,
    label: variantLabel(v),
    sublabel: `Kode ${v.code} · Sisa ${formatNumber(v.total_available)} ${v.unit}`,
    icon: v.photo_key ? attachmentUrl(v.photo_key) : itemFlaticonIcon(v.name),
  })),
)

const pagedRows = computed(() => {
  const maxPage = Math.max(1, Math.ceil(filteredRows.value.length / 10))
  const cur = Math.min(Math.max(1, page.value), maxPage)
  return filteredRows.value.slice((cur - 1) * 10, cur * 10)
})
watch([statusFilter, search, supplierFilter, vendorTypeFilter, departmentFilter, fundingFilter, methodFilter, dateFrom, dateTo], () => { page.value = 1 })

function variantInfo(variantId: string) {
  return master.variants.find((v) => v.variant_id === variantId) || null
}

function summarizeProcItems(items: ProcurementRow['items']) {
  const map = new Map<string, { name: string; unit: string; ordered: number; received: number }>()
  for (const it of items) {
    const name = it.item_variants?.items?.name || 'Barang'
    const unit = it.item_variants?.items?.unit || ''
    const size = it.item_variants?.size
    const key = name.toLowerCase()
    const prev = map.get(key)
    if (prev) {
      prev.ordered += Number(it.ordered_quantity)
      prev.received += Number(it.received_quantity)
    } else {
      map.set(key, {
        name: size && size !== '-' && size !== 'All Size' ? `${name} (${size})` : name,
        unit,
        ordered: Number(it.ordered_quantity),
        received: Number(it.received_quantity),
      })
    }
  }
  return [...map.values()]
}

function setVendorKind(kind: 'supplier' | 'online_shop') {
  vendorKind.value = kind
  const list = master.suppliers.filter((s) => (s.vendor_type || 'supplier') === kind)
  form.supplierId = list[0]?.id || master.suppliers[0]?.id || ''
}

const calcGrandTotal = computed(() =>
  form.items.reduce((sum, item) => sum + Number(item.orderedQuantity || 0) * Number(item.unitPrice || 0), 0),
)

async function load() {
  loading.value = true
  try {
    const res = await api<{ data: ProcurementRow[] }>('/api/procurements')
    rows.value = res.data
  } finally {
    loading.value = false
  }
}

async function openCreateModal() {
  editingProcId.value = null
  form.procurementDate = new Date().toISOString().slice(0, 10)
  form.expectedDate = ''
  form.prNumber = ''
  form.poNumber = ''
  form.reason = ''
  form.fundingSource = 'company'
  form.paymentMethod = 'transfer'
  form.notes = ''
  showCreateModal.value = true

  try {
    await master.refresh()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data master')
  }

  const hasOnlineShop = master.suppliers.some((s) => s.vendor_type === 'online_shop')
  vendorKind.value = hasOnlineShop ? 'online_shop' : 'supplier'
  form.departmentId = master.departments[0]?.id || ''
  form.supplierId = filteredModalVendors.value[0]?.id || master.suppliers[0]?.id || ''
  form.funderId = master.funders[0]?.id || ''
  form.items = [{ variantId: master.variants[0]?.variant_id || '', orderedQuantity: 10, unitPrice: 0, notes: '' }]
}

async function openEditModal(row: ProcurementRow) {
  editingProcId.value = row.id
  form.procurementDate = row.procurement_date.slice(0, 10)
  form.expectedDate = row.expected_date ? row.expected_date.slice(0, 10) : ''
  form.prNumber = row.pr_number || ''
  form.poNumber = row.po_number || ''
  form.departmentId = row.department_id || ''
  const matchedSup = master.suppliers.find((s) => s.id === row.supplier_id)
  vendorKind.value = (matchedSup?.vendor_type || row.vendor_type) === 'online_shop' ? 'online_shop' : 'supplier'
  form.supplierId = row.supplier_id || filteredModalVendors.value[0]?.id || ''
  form.reason = row.reason
  form.fundingSource = row.funding_source
  form.paymentMethod = row.payment_method || 'transfer'
  form.funderId = row.funder_id || ''
  form.notes = row.notes || ''
  form.items = row.items.map((it) => ({
    id: it.id,
    variantId: it.variant_id,
    orderedQuantity: Number(it.ordered_quantity),
    unitPrice: Number(it.unit_price),
    notes: it.notes || '',
  }))
  showCreateModal.value = true
  master.refresh().catch(() => {})
}

function addItemLine() {
  form.items.push({ variantId: master.variants[0]?.variant_id || '', orderedQuantity: 1, unitPrice: 0, notes: '' })
}

async function submitProcurement() {
  const validItems = form.items.filter((i) => i.variantId && Number(i.orderedQuantity) > 0)
  if (!validItems.length) {
    toast.error('Minimal 1 barang dipesan')
    return
  }
  saving.value = true
  try {
    const endpoint = editingProcId.value ? `/api/procurements/${editingProcId.value}` : '/api/procurements'
    const method = editingProcId.value ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      headers: editingProcId.value ? {} : { 'X-Idempotency-Key': generateUuid() },
      body: JSON.stringify({
        procurementDate: form.procurementDate,
        expectedDate: form.expectedDate || null,
        prNumber: form.prNumber || null,
        poNumber: form.poNumber || null,
        departmentId: form.departmentId || null,
        supplierId: form.supplierId,
        reason: form.reason,
        fundingSource: form.fundingSource,
        paymentMethod: form.paymentMethod,
        funderId: form.fundingSource === 'advanced' ? form.funderId : null,
        totalAmount: calcGrandTotal.value,
        notes: form.notes || null,
        items: validItems.map((i) => ({
          id: i.id,
          variantId: i.variantId,
          orderedQuantity: Number(i.orderedQuantity),
          unitPrice: Number(i.unitPrice || 0),
          notes: i.notes || null,
        })),
      }),
    })
    toast.success(editingProcId.value ? 'Pengadaan barang berhasil diperbarui!' : 'Pengadaan barang berhasil dibuat! Gunakan No. Pengadaan/PO saat barang tiba.')
    showCreateModal.value = false
    await load()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan pengadaan')
  } finally {
    saving.value = false
  }
}

async function openDetail(id: string) {
  showDetailModal.value = true
  loadingDetail.value = true
  try {
    const res = await api<{ data: ProcurementDetail }>(`/api/procurements/${id}`)
    detail.value = res.data
  } finally {
    loadingDetail.value = false
  }
}

function openReceiveFor(id: string) {
  receiptProcId.value = id
  showReceiptModal.value = true
}

// Stat History Drill-down Modal
const statModalOpen = ref(false)
const statModalTitle = ref('')
const statModalSubtitle = ref('')
const statModalEmpty = ref('')
const statModalColumns = ref<HistoryColumn[]>([])
const statModalRows = ref<Array<Record<string, HistoryCell>>>([])

function openStatHistory(kind: 'all' | 'pending_progress' | 'completed') {
  statModalOpen.value = true
  if (kind === 'all') {
    statModalTitle.value = 'Riwayat Semua Pengadaan Barang (PO)'
    statModalSubtitle.value = `Total ${rows.value.length} dokumen pengadaan tercatat`
    statModalEmpty.value = 'Belum ada data pengadaan barang.'
    statModalColumns.value = [
      { key: 'doc', label: 'Kode Pengadaan / PO' },
      { key: 'supplier', label: 'Supplier / Toko' },
      { key: 'progress', label: 'Progress Barang' },
      { key: 'amount', label: 'Nilai Pengadaan' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = rows.value.map((r) => {
      const sb = statusBadge(r.status)
      return {
        doc: { text: r.procurement_no, sub: `${formatDate(r.procurement_date)}${r.po_number ? ` · PO: ${r.po_number}` : ''}`, strong: true },
        supplier: r.supplier_name,
        progress: `${formatNumber(r.total_received)} / ${formatNumber(r.total_ordered)} (${r.progress_percent}%)`,
        amount: { text: formatCurrency(r.total_amount), sub: r.payment_method === 'cash' ? 'Tunai' : 'Transfer', strong: true },
        status: { text: sb.label, pill: (sb.cls === 'blue' ? 'amber' : sb.cls) as 'safe' | 'amber' | 'out' | 'neutral' },
      }
    })
  } else if (kind === 'pending_progress') {
    const list = rows.value.filter((r) => r.status === 'ordered' || r.status === 'partial')
    statModalTitle.value = 'Riwayat Pengadaan Menunggu / Diterima Sebagian'
    statModalSubtitle.value = `${list.length} pengadaan masih menunggu kelengkapan barang datang`
    statModalEmpty.value = 'Tidak ada pengadaan yang sedang menunggu barang.'
    statModalColumns.value = [
      { key: 'doc', label: 'Kode Pengadaan / PO' },
      { key: 'supplier', label: 'Supplier / Toko' },
      { key: 'ordered', label: 'Dipesan' },
      { key: 'received', label: 'Sudah Masuk' },
      { key: 'remaining', label: 'Sisa' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = list.map((r) => {
      const rem = Math.max(0, Number(r.total_ordered || 0) - Number(r.total_received || 0))
      return {
        doc: { text: r.procurement_no, sub: `${formatDate(r.procurement_date)}${r.po_number ? ` · PO: ${r.po_number}` : ''}`, strong: true },
        supplier: r.supplier_name,
        ordered: `${formatNumber(r.total_ordered)} unit`,
        received: `${formatNumber(r.total_received)} unit (${r.progress_percent}%)`,
        remaining: { text: `${formatNumber(rem)} unit`, strong: true },
        status: { text: r.status === 'partial' ? 'Diterima Sebagian' : 'Menunggu Barang', pill: 'amber' },
      }
    })
  } else {
    const list = rows.value.filter((r) => r.status === 'completed')
    statModalTitle.value = 'Riwayat Pengadaan Terpenuhi (Selesai)'
    statModalSubtitle.value = `${list.length} pengadaan sudah diterima lengkap 100%`
    statModalEmpty.value = 'Belum ada pengadaan yang terpenuhi lengkap.'
    statModalColumns.value = [
      { key: 'doc', label: 'Kode Pengadaan / PO' },
      { key: 'supplier', label: 'Supplier / Toko' },
      { key: 'received', label: 'Total Diterima' },
      { key: 'amount', label: 'Nilai Pengadaan' },
      { key: 'status', label: 'Status' },
    ]
    statModalRows.value = list.map((r) => ({
      doc: { text: r.procurement_no, sub: `${formatDate(r.procurement_date)}${r.po_number ? ` · PO: ${r.po_number}` : ''}`, strong: true },
      supplier: r.supplier_name,
      received: `${formatNumber(r.total_received)} unit (100%)`,
      amount: { text: formatCurrency(r.total_amount), strong: true },
      status: { text: 'Terpenuhi', pill: 'safe' },
    }))
  }
}

// Restore (Batal Cancel) Modal
const showRestoreModal = ref(false)
const restoringRow = ref<ProcurementRow | null>(null)
const restoreNote = ref('')
const restoring = ref(false)

function expectedRestoredStatusLabel(row: ProcurementRow) {
  const ordered = Number(row.total_ordered || 0)
  const received = Number(row.total_received || 0)
  if (ordered > 0 && received >= ordered) return 'Terpenuhi (100%)'
  if (received > 0) return `Diterima Sebagian (${row.progress_percent}%)`
  return 'Menunggu Barang'
}

function openRestoreModal(row: ProcurementRow) {
  if (row.status !== 'cancelled') return
  restoringRow.value = row
  restoreNote.value = ''
  showRestoreModal.value = true
}

async function confirmRestoreProcurement() {
  const row = restoringRow.value
  if (!row) return
  restoring.value = true
  try {
    await api(`/api/procurements/${row.id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'ordered',
        cancelNote: restoreNote.value.trim() || undefined,
      }),
    })
    showRestoreModal.value = false
    showDetailModal.value = false
    toast.success(`Pengadaan ${row.procurement_no} diaktifkan kembali (${expectedRestoredStatusLabel(row)})`, 'Batal Cancel Berhasil')
    await load()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal mengaktifkan kembali pengadaan')
  } finally {
    restoring.value = false
  }
}

function cancelProcurement(row: ProcurementRow) {
  if (row.status === 'completed' || row.status === 'cancelled') return
  cancellingRow.value = row
  cancelNote.value = ''
  showCancelModal.value = true
}

async function confirmCancelProcurement() {
  const row = cancellingRow.value
  if (!row) return
  if (!cancelNote.value.trim()) {
    toast.error('Keterangan / alasan pembatalan wajib diisi')
    return
  }
  cancelling.value = true
  try {
    await api(`/api/procurements/${row.id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'cancelled',
        cancelNote: cancelNote.value.trim(),
      }),
    })
    showCancelModal.value = false
    showDetailModal.value = false
    toast.success(`Pengadaan ${row.procurement_no} berhasil dibatalkan`, 'Pengadaan Dibatalkan')
    await load()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal membatalkan pengadaan')
  } finally {
    cancelling.value = false
  }
}

async function deleteProcurement(row: ProcurementRow) {
  if (!window.confirm(`Hapus permanen data pengadaan "${row.procurement_no}"${row.po_number ? ` (PO: ${row.po_number})` : ''}? Stok barang yang sudah diterima sebelumnya tetap aman di inventaris.`)) return
  try {
    await api(`/api/procurements/${row.id}`, { method: 'DELETE' })
    showDetailModal.value = false
    toast.success(`Pengadaan ${row.procurement_no} berhasil dihapus`)
    await load()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menghapus pengadaan')
  }
}

function statusBadge(s: string) {
  const map: Record<string, { label: string; cls: string }> = {
    ordered: { label: 'Menunggu Barang', cls: 'amber' },
    partial: { label: 'Diterima Sebagian', cls: 'blue' },
    completed: { label: 'Terpenuhi', cls: 'safe' },
    cancelled: { label: 'Dibatalkan', cls: 'out' },
    draft: { label: 'Draft', cls: 'neutral' },
  }
  return map[s] || { label: s, cls: 'neutral' }
}

let lastCacheVer = -1
onMounted(() => {
  if (route.query.action === 'new') void openCreateModal()
  lastCacheVer = getApiCacheVersion()
  void Promise.all([load(), master.refresh()])
})
onActivated(() => {
  if (route.query.action === 'new') void openCreateModal()
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
        <p class="eyebrow">Database Pengadaan Barang</p>
        <h2>Pengadaan Barang (PO)</h2>
        <p>Buat rencana pengadaan dan pantau progress kedatangan barang. Nominal pengadaan otomatis tercatat di History Pembayaran.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openCreateModal"><Plus :size="17" /> Buat Pengadaan Barang</button>
      </div>
    </section>

    <section class="mini-stats">
      <button type="button" class="mini-stat-btn" @click="openStatHistory('all')">
        <span class="mini-icon unified"><ShoppingBag :size="19" /></span>
        <p>Total pengadaan<strong>{{ rows.length }}</strong></p>
      </button>
      <button type="button" class="mini-stat-btn" @click="openStatHistory('pending_progress')">
        <span class="mini-icon unified"><PackageCheck :size="19" /></span>
        <p>Menunggu / Sebagian<strong>{{ rows.filter(r => r.status === 'ordered' || r.status === 'partial').length }}</strong></p>
      </button>
      <button type="button" class="mini-stat-btn" @click="openStatHistory('completed')">
        <span class="mini-icon unified"><CheckCircle2 :size="19" /></span>
        <p>Terpenuhi (Selesai)<strong>{{ rows.filter(r => r.status === 'completed').length }}</strong></p>
      </button>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: statusFilter === 'all' }" @click="statusFilter = 'all'">Semua</button>
        <button :class="{ active: statusFilter === 'ordered' }" @click="statusFilter = 'ordered'">Menunggu Barang</button>
        <button :class="{ active: statusFilter === 'partial' }" @click="statusFilter = 'partial'">Diterima Sebagian</button>
        <button :class="{ active: statusFilter === 'completed' }" @click="statusFilter = 'completed'">Terpenuhi</button>
        <button :class="{ active: statusFilter === 'cancelled' }" @click="statusFilter = 'cancelled'">Dibatalkan ({{ rows.filter(r => r.status === 'cancelled').length }})</button>
      </div>
      <div class="table-toolbar filter-toolbar-rich">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Pengadaan (PGD), No. PO, PR, barang, atau supplier..." /></label>
        <div class="date-range-inline">
          <CalendarRange :size="15" />
          <input v-model="dateFrom" type="date" class="compact-date" title="Dari tanggal" />
          <span class="date-sep">s/d</span>
          <input v-model="dateTo" type="date" class="compact-date" title="Sampai tanggal" />
        </div>
        <ModernSelect v-model="supplierFilter" :options="supplierFilterOptions" compact searchable search-placeholder="Cari supplier / toko..." />
        <ModernSelect v-model="vendorTypeFilter" :options="vendorTypeFilterOptions" compact searchable search-placeholder="Cari jenis vendor..." />
        <ModernSelect v-model="departmentFilter" :options="departmentFilterOptions" compact searchable search-placeholder="Cari departemen..." />
        <ModernSelect v-model="fundingFilter" :options="fundingFilterOptions" compact searchable search-placeholder="Cari sumber dana..." />
        <ModernSelect v-model="methodFilter" :options="methodFilterOptions" compact searchable search-placeholder="Cari metode..." />
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
                  Kode Pengadaan / PO <ArrowUpDown :size="13" /> <span>{{ sortDir === 'asc' ? '↑' : '↓' }}</span>
                </button>
              </th>
              <th>Toko Online / Supplier</th><th>Item Dipesan</th>
              <th>Progress Kedatangan</th><th>Nilai Pengadaan</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td>
                <strong>{{ row.procurement_no }}</strong>
                <small class="table-sub">{{ formatDate(row.procurement_date) }} <span v-if="row.po_number">· PO: {{ row.po_number }}</span></small>
              </td>
              <td>
                <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                  <span class="tag-pill">{{ row.vendor_type === 'online_shop' ? 'Toko Online' : 'Supplier' }}</span>
                  <strong class="table-main">{{ row.supplier_name }}</strong>
                </div>
                <small class="table-sub">{{ row.department_name || 'Umum' }} · {{ row.reason }}</small>
                <small v-if="row.status === 'cancelled' && row.notes" class="table-sub" style="color:#b92b27;font-weight:600;">
                  {{ row.notes }}
                </small>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="(it, sIdx) in summarizeProcItems(row.items).slice(0, 3)" :key="sIdx">
                    {{ it.name }} · <b>{{ formatNumber(it.received) }}/{{ formatNumber(it.ordered) }} {{ it.unit }}</b>
                  </span>
                  <small v-if="summarizeProcItems(row.items).length > 3" class="table-sub">+{{ summarizeProcItems(row.items).length - 3 }} barang lainnya</small>
                </div>
              </td>
              <td>
                <div class="progress-cell">
                  <div class="progress-head">
                    <span class="status-pill" :class="statusBadge(row.status).cls">{{ statusBadge(row.status).label }}</span>
                    <strong>{{ row.progress_percent }}%</strong>
                  </div>
                  <div class="progress-track"><div class="progress-fill" :style="{ width: `${row.progress_percent}%` }" /></div>
                  <small class="table-sub">{{ formatNumber(row.total_received) }} / {{ formatNumber(row.total_ordered) }} unit diterima</small>
                </div>
              </td>
              <td>
                <strong class="table-main">{{ formatCurrency(row.total_amount) }}</strong>
                <div class="tag-group" style="margin-top: 4px;">
                  <span class="tag-pill">{{ row.payment_method === 'cash' ? 'Tunai / Kas' : 'Transfer' }}</span>
                  <span v-if="row.funding_source === 'advanced'" class="tag-pill">Talangan</span>
                </div>
                <small v-if="Number(row.total_amount) > 0 && row.status !== 'cancelled'" class="table-sub">Tercatat di History Pembayaran</small>
              </td>
              <td>
                <div class="row-actions">
                  <button
                    v-if="row.status === 'ordered' || row.status === 'partial'"
                    class="primary-button xs"
                    title="Catat barang datang untuk pengadaan ini"
                    @click="openReceiveFor(row.id)"
                  >
                    <PackageCheck :size="13" /> Terima
                  </button>
                  <button
                    v-if="row.status === 'ordered' || row.status === 'partial' || row.status === 'draft'"
                    class="secondary-button xs danger-soft"
                    title="Batalkan pengadaan yang sedang berjalan"
                    @click="cancelProcurement(row)"
                  >
                    <XCircle :size="13" /> Cancel
                  </button>
                  <button
                    v-if="row.status === 'cancelled'"
                    class="secondary-button xs highlight"
                    title="Tidak jadi dibatalkan — aktifkan kembali pengadaan ini"
                    @click="openRestoreModal(row)"
                  >
                    <RotateCcw :size="13" /> Aktifkan Lagi
                  </button>
                  <button
                    class="icon-button"
                    title="Lihat detail & progress"
                    @click="openDetail(row.id)"
                  >
                    <Eye :size="15" />
                  </button>
                  <button
                    class="icon-button"
                    title="Edit pengadaan"
                    @click="openEditModal(row)"
                  >
                    <Edit3 :size="15" />
                  </button>
                  <button class="icon-button danger" title="Hapus pengadaan" @click="deleteProcurement(row)"><Trash2 :size="15" /></button>
                </div>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRows.length">
              <td colspan="6"><div class="empty-state"><ShoppingBag :size="32" /><strong>Belum ada pengadaan barang</strong><span>Klik "Buat Pengadaan Barang" untuk mencatat rencana pengadaan APD.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat database pengadaan...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" />
    </section>

    <!-- Create / Edit Procurement Modal -->
    <BaseModal
      :open="showCreateModal"
      :title="editingProcId ? 'Edit Pengadaan Barang' : 'Buat Pengadaan Barang Baru'"
      eyebrow="Pengadaan APD"
      subtitle="Sistem otomatis membuat Kode Pengadaan (PGD-...) untuk mengenali barang saat tiba di gudang."
      size="lg"
      @close="showCreateModal = false"
    >
      <form id="procurement-form" class="modal-form" @submit.prevent="submitProcurement">
        <div class="form-grid-3">
          <label class="field"><span>Tanggal Pengadaan *</span><input v-model="form.procurementDate" type="date" required /></label>
          <label class="field"><span>Estimasi Tiba</span><input v-model="form.expectedDate" type="date" /></label>
          <label class="field"><span>Departemen Pemohon</span>
            <ModernSelect v-model="form.departmentId" :options="departmentOptions" />
          </label>
        </div>

        <div class="segmented-switch">
          <button type="button" :class="{ active: vendorKind === 'online_shop' }" @click="setVendorKind('online_shop')">
            <ShoppingBag :size="15" /> Toko Online (Shopee / Tokopedia / dll)
          </button>
          <button type="button" :class="{ active: vendorKind === 'supplier' }" @click="setVendorKind('supplier')">
            <Truck :size="15" /> Supplier Resmi
          </button>
        </div>

        <div class="form-grid-2">
          <label class="field"><span>{{ vendorKind === 'online_shop' ? 'Pilih Toko Online *' : 'Pilih Supplier *' }}</span>
            <ModernSelect v-model="form.supplierId" :options="modalVendorOptions" required />
          </label>
          <label class="field">
            <span>Nomor PO / Pesanan <small style="font-weight:500;color:#687686;">(Otomatis jika dikosongkan)</small></span>
            <input v-model="form.poNumber" placeholder="Otomatis dibuat: PO-YYYYMM-..." />
          </label>
        </div>

        <label class="field"><span>Keperluan / Alasan Pengadaan *</span><input v-model="form.reason" required placeholder="Contoh: Pengadaan APD rutin pekerja proyek Q4" /></label>

        <div :class="form.fundingSource === 'advanced' ? 'form-grid-3' : 'form-grid-2'">
          <label class="field"><span>Sumber Dana</span>
            <ModernSelect v-model="form.fundingSource" :options="fundingOptions" :searchable="false" />
          </label>
          <label class="field"><span>Metode Pembayaran</span>
            <ModernSelect v-model="form.paymentMethod" :options="payMethodOptions" :searchable="false" />
          </label>
          <label v-if="form.fundingSource === 'advanced'" class="field"><span>Pihak Penalang *</span>
            <ModernSelect v-model="form.funderId" :options="funderOptions" required />
          </label>
        </div>

        <div class="lines-section">
          <div class="lines-header">
            <div><strong>Daftar Barang yang Dipesan</strong><small>Total estimasi: {{ formatCurrency(calcGrandTotal) }}</small></div>
            <button type="button" class="secondary-button sm" @click="addItemLine"><Plus :size="14" /> Tambah Item</button>
          </div>
          <div class="modal-lines-list">
            <div v-for="(line, idx) in form.items" :key="idx" class="modal-line-card">
              <div class="line-top">
                <ModernSelect v-model="line.variantId" :options="variantOptions" required search-placeholder="Cari nama APD..." style="flex:1;" />
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
                  <span>Sisa stok gudang: <strong>{{ formatNumber(variantInfo(line.variantId)?.total_available || 0) }} {{ variantInfo(line.variantId)?.unit }}</strong></span>
                  <span class="status-pill" :class="variantInfo(line.variantId)?.stock_status">
                    {{ variantInfo(line.variantId)?.stock_status === 'safe' ? 'Aman' : variantInfo(line.variantId)?.stock_status === 'low' ? 'Menipis' : 'Habis' }}
                  </span>
                </div>
              </div>
              <div class="form-grid-3">
                <label class="field">
                  <span>Jumlah Dipesan ({{ variantInfo(line.variantId)?.unit || 'unit' }}) *</span>
                  <input v-model.number="line.orderedQuantity" type="number" min="0.01" step="any" required />
                </label>
                <label class="field">
                  <span>Harga Satuan (per {{ variantInfo(line.variantId)?.unit || 'unit' }})</span>
                  <div class="price-input-wrap">
                    <span class="price-prefix">Rp</span>
                    <input v-model.number="line.unitPrice" type="number" min="0" step="100" placeholder="0" />
                  </div>
                  <small class="price-formatted-hint">{{ formatCurrency(line.unitPrice || 0) }} / {{ variantInfo(line.variantId)?.unit || 'unit' }}</small>
                </label>
                <label class="field">
                  <span>Subtotal</span>
                  <input :value="formatCurrency((line.orderedQuantity || 0) * (line.unitPrice || 0))" disabled />
                </label>
              </div>
            </div>
          </div>
        </div>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showCreateModal = false">Batal</button>
        <button type="submit" form="procurement-form" class="primary-button" :disabled="saving">
          {{ saving ? 'Menyimpan...' : 'Simpan Pengadaan' }}
        </button>
      </template>
    </BaseModal>

    <!-- Procurement Detail Modal -->
    <BaseModal
      :open="showDetailModal"
      :title="`Detail Pengadaan ${detail?.procurement_no || ''}`"
      eyebrow="Pelacakan Pengadaan"
      size="lg"
      @close="showDetailModal = false"
    >
      <div v-if="loadingDetail" class="loading-row">Memuat detail pengadaan...</div>
      <div v-else-if="detail" class="detail-stack">
        <div class="summary-banner">
          <div><small>Supplier</small><strong>{{ detail.supplier_name }}</strong></div>
          <div><small>Progress Barang</small><strong>{{ detail.progress_percent }}% ({{ detail.total_received }}/{{ detail.total_ordered }})</strong></div>
          <div><small>Total Nilai Pengadaan</small><strong>{{ formatCurrency(detail.total_amount) }}</strong></div>
        </div>
        <div v-if="detail.notes" class="inline-alert" :style="detail.status === 'cancelled' ? 'background:#fef2f2;color:#991b1b;border:1px solid #fecaca;margin:0;' : 'margin:0;'">
          <strong>Catatan / Keterangan:</strong> {{ detail.notes }}
        </div>

        <div class="detail-section">
          <h4>Item Pengadaan & Sisa Belum Datang</h4>
          <div class="table-wrap">
            <table>
              <thead><tr><th>Barang</th><th>Ukuran</th><th>Dipesan</th><th>Sudah Datang</th><th>Sisa</th><th>Harga Satuan</th></tr></thead>
              <tbody>
                <tr v-for="it in detail.items" :key="it.id">
                  <td><strong>{{ variantLabel({ name: it.item_variants?.items?.name, size: it.item_variants?.size }) }}</strong></td>
                  <td>{{ it.item_variants?.size && it.item_variants.size !== '-' ? it.item_variants.size : 'Standar' }}</td>
                  <td>{{ formatNumber(it.ordered_quantity) }} {{ it.item_variants?.items?.unit }}</td>
                  <td>{{ formatNumber(it.received_quantity) }}</td>
                  <td><strong :class="it.ordered_quantity - it.received_quantity > 0 ? 'text-amber' : 'text-primary'">{{ formatNumber(it.ordered_quantity - it.received_quantity) }}</strong></td>
                  <td>{{ formatCurrency(it.unit_price) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="detail-section">
          <h4>Riwayat Penerimaan Barang Masuk ({{ detail.receipts.length }})</h4>
          <div v-if="detail.receipts.length" class="mini-list">
            <div v-for="r in detail.receipts" :key="r.id" class="mini-list-row">
              <CheckCircle2 :size="15" class="text-primary" />
              <strong>{{ r.transaction_no }}</strong>
              <span>Tanggal {{ formatDate(r.received_date) }}</span>
              <span v-if="r.delivery_note_number" class="tag-pill">SJ: {{ r.delivery_note_number }}</span>
            </div>
          </div>
          <p v-else class="muted-text">Belum ada barang masuk yang diterima untuk pengadaan ini.</p>
        </div>
      </div>
      <template #footer>
        <button type="button" class="secondary-button" @click="showDetailModal = false">Tutup</button>
        <button v-if="detail && detail.status === 'cancelled'" type="button" class="primary-button" @click="openRestoreModal(detail)">
          <RotateCcw :size="15" /> Aktifkan Lagi (Batal Cancel)
        </button>
        <button v-if="detail && (detail.status === 'ordered' || detail.status === 'partial' || detail.status === 'draft')" type="button" class="secondary-button danger-soft" @click="cancelProcurement(detail)">
          <XCircle :size="15" /> Cancel Pengadaan
        </button>
        <button v-if="detail && (detail.status === 'ordered' || detail.status === 'partial')" type="button" class="primary-button" @click="showDetailModal = false; openReceiveFor(detail.id)">
          <PackageCheck :size="16" /> Terima Barang Datang
        </button>
      </template>
    </BaseModal>

    <!-- Cancel Procurement Confirmation Modal with Note -->
    <BaseModal
      :open="showCancelModal"
      :title="`Cancel Pengadaan · ${cancellingRow?.procurement_no || ''}`"
      eyebrow="Konfirmasi Pembatalan Pengadaan"
      subtitle="Masukkan alasan atau keterangan pembatalan agar tercatat rapi dalam riwayat pengadaan."
      size="sm"
      @close="showCancelModal = false"
    >
      <form v-if="cancellingRow" id="cancel-proc-form" class="modal-form" @submit.prevent="confirmCancelProcurement">
        <div class="summary-banner" style="grid-template-columns:repeat(2,minmax(0,1fr));">
          <div>
            <small>Dokumen &amp; PO</small>
            <strong>{{ cancellingRow.procurement_no }}{{ cancellingRow.po_number ? ` · ${cancellingRow.po_number}` : '' }}</strong>
          </div>
          <div>
            <small>Supplier / Progress</small>
            <strong>{{ cancellingRow.supplier_name }} ({{ cancellingRow.progress_percent }}%)</strong>
          </div>
        </div>

        <div v-if="Number(cancellingRow.total_received) > 0" class="inline-alert" style="margin:0;">
          <span>
            Sudah ada <strong>{{ formatNumber(cancellingRow.total_received) }} unit</strong> barang yang diterima.
            Barang yang sudah masuk tetap aman di stok gudang, dan sisa pesanan ({{ formatNumber(Math.max(0, Number(cancellingRow.total_ordered) - Number(cancellingRow.total_received))) }} unit) akan dihentikan.
          </span>
        </div>

        <label class="field">
          <span>Alasan / Keterangan Pembatalan *</span>
          <textarea
            v-model="cancelNote"
            rows="3"
            required
            placeholder="Contoh: Supplier kehabisan stok / proyek dibatalkan / ganti vendor..."
          />
        </label>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" :disabled="cancelling" @click="showCancelModal = false">Kembali</button>
        <button type="submit" form="cancel-proc-form" class="secondary-button danger-soft" :disabled="cancelling || !cancelNote.trim()">
          <XCircle :size="15" /> {{ cancelling ? 'Membatalkan...' : 'Konfirmasi Cancel Pengadaan' }}
        </button>
      </template>
    </BaseModal>

    <!-- Restore / Batal Cancel Confirmation Modal -->
    <BaseModal
      :open="showRestoreModal"
      :title="`Aktifkan Lagi · ${restoringRow?.procurement_no || ''}`"
      eyebrow="Batal Cancel Pengadaan"
      subtitle="Kembalikan status pengadaan ini menjadi aktif sesuai progress kedatangan barang."
      size="sm"
      @close="showRestoreModal = false"
    >
      <form v-if="restoringRow" id="restore-proc-form" class="modal-form" @submit.prevent="confirmRestoreProcurement">
        <div class="summary-banner" style="grid-template-columns:repeat(2,minmax(0,1fr));">
          <div>
            <small>Dokumen &amp; PO</small>
            <strong>{{ restoringRow.procurement_no }}{{ restoringRow.po_number ? ` · ${restoringRow.po_number}` : '' }}</strong>
          </div>
          <div>
            <small>Status Setelah Diaktifkan</small>
            <strong>{{ expectedRestoredStatusLabel(restoringRow) }}</strong>
          </div>
        </div>

        <label class="field">
          <span>Catatan / Keterangan (Opsional)</span>
          <textarea
            v-model="restoreNote"
            rows="3"
            placeholder="Contoh: Salah pencet batal / pengadaan tetap dilanjutkan ke supplier..."
          />
        </label>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" :disabled="restoring" @click="showRestoreModal = false">Kembali</button>
        <button type="submit" form="restore-proc-form" class="primary-button" :disabled="restoring">
          <RotateCcw :size="15" /> {{ restoring ? 'Mengaktifkan...' : 'Ya, Aktifkan Lagi' }}
        </button>
      </template>
    </BaseModal>

    <ReceiptModal :open="showReceiptModal" :initial-procurement-id="receiptProcId" @close="showReceiptModal = false" @saved="load" />

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
