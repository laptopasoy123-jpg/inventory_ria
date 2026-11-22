<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { CheckCheck, PackageCheck, Plus, Search, ShoppingBag, Trash2, Truck, Upload } from '@lucide/vue'
import BaseModal from './BaseModal.vue'
import ModernSelect from './ModernSelect.vue'
import { api, attachmentUrl, formatNumber, generateUuid, uploadAttachment, variantLabel } from '@/lib/api'
import { itemFlaticonIcon } from '@/lib/icons'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

export interface ProcurementOption {
  id: string
  procurement_no: string
  po_number: string | null
  pr_number: string | null
  procurement_date: string
  supplier_id: string
  supplier_name: string
  vendor_type?: 'supplier' | 'online_shop'
  reason: string
  funding_source: 'company' | 'advanced'
  payment_method: 'cash' | 'transfer'
  funder_id: string | null
  total_ordered: number
  total_received: number
  progress_percent: number
  status: string
  items: Array<{
    id: string
    variant_id: string
    ordered_quantity: number
    received_quantity: number
    unit_price: number
    item_variants?: {
      id: string
      size: string
      items?: { id: string; code: string; name: string; unit: string } | null
    } | null
  }>
}

export interface EditablePurchase {
  id: string
  procurement_id?: string | null
  received_date: string
  supplier_id?: string
  reason: string
  funding_source: 'company' | 'advanced'
  payment_method?: 'cash' | 'transfer'
  funder_id?: string | null
  billing_proof_key?: string | null
  purchase_items: Array<{
    id: string
    procurement_item_id?: string | null
    variant_id: string
    quantity: number
    condition: 'new' | 'used_good' | 'quarantine' | 'damaged'
    receiver_name: string
    notes?: string | null
    item_variants?: { size: string; items?: { code: string; name: string; unit: string } | null } | null
  }>
}

const props = defineProps<{
  open: boolean
  initialProcurementId?: string | null
  editingPurchase?: EditablePurchase | null
}>()

const emit = defineEmits<{ close: []; saved: [] }>()
const master = useMasterStore()
const toast = useToast()

const mode = ref<'procurement' | 'direct'>('procurement')
const directVendorType = ref<'online_shop' | 'supplier'>('online_shop')
const pendingProcurements = ref<ProcurementOption[]>([])
const procSearch = ref('')
const filterByVariantId = ref('')
const selectedProcId = ref('')
const loadingProcs = ref(false)
const saving = ref(false)
const uploading = ref(false)

interface ReceiptLine {
  procurementItemId?: string | null
  variantId: string
  label: string
  unit?: string
  orderedQty?: number
  alreadyReceived?: number
  remainingQty?: number
  quantity: number
  condition: 'new' | 'used_good' | 'quarantine' | 'damaged'
  receiverName: string
  notes: string
}

const form = reactive({
  receivedDate: new Date().toISOString().slice(0, 10),
  supplierId: '',
  reason: '',
  fundingSource: 'company' as 'company' | 'advanced',
  paymentMethod: 'transfer' as 'cash' | 'transfer',
  funderId: '',
  billingProofKey: '',
  receiverNameDefault: '',
  lines: [] as ReceiptLine[],
})

const activeOfficers = computed(() => master.officers.filter((o) => o.active))
const filteredDirectVendors = computed(() => {
  const list = master.suppliers.filter((s) => (s.vendor_type || 'supplier') === directVendorType.value)
  return list.length ? list : master.suppliers
})

function setDirectVendorType(kind: 'online_shop' | 'supplier') {
  directVendorType.value = kind
  const list = master.suppliers.filter((s) => (s.vendor_type || 'supplier') === kind)
  form.supplierId = list[0]?.id || master.suppliers[0]?.id || ''
}

const filteredProcurements = computed(() => {
  return pendingProcurements.value.filter((p) => {
    if (filterByVariantId.value) {
      const hasVar = p.items.some((it) => it.variant_id === filterByVariantId.value && it.ordered_quantity > it.received_quantity)
      if (!hasVar) return false
    }
    if (!procSearch.value.trim()) return true
    const q = procSearch.value.toLowerCase()
    return (
      p.procurement_no.toLowerCase().includes(q) ||
      (p.po_number || '').toLowerCase().includes(q) ||
      (p.pr_number || '').toLowerCase().includes(q) ||
      p.supplier_name.toLowerCase().includes(q) ||
      p.items.some((it) => (it.item_variants?.items?.name || '').toLowerCase().includes(q))
    )
  })
})

const selectedProcurement = computed(() =>
  pendingProcurements.value.find((p) => p.id === selectedProcId.value) || null,
)

const accumulatedSummary = computed(() => {
  const map = new Map<string, { name: string; total: number }>()
  for (const l of form.lines) {
    const qty = Number(l.quantity || 0)
    if (qty <= 0) continue
    const v = master.variants.find((x) => x.variant_id === l.variantId)
    const name = v?.name || l.label.split(' (')[0] || 'Barang'
    const key = name.toLowerCase()
    const prev = map.get(key)
    if (prev) prev.total += qty
    else map.set(key, { name, total: qty })
  }
  return [...map.values()]
})

function onDropdownSelect(val: string) {
  const found = pendingProcurements.value.find((p) => p.id === val)
  if (found) selectProcurement(found)
  else {
    selectedProcId.value = ''
    form.lines = []
  }
}

const procSelectOptions = computed(() =>
  filteredProcurements.value.map((proc) => ({
    value: proc.id,
    label: proc.po_number || proc.procurement_no,
    sublabel: `${proc.procurement_no} · ${proc.supplier_name}`,
    badge: `Sisa ${formatNumber(proc.total_ordered - proc.total_received)}`,
  })),
)

const officerOptions = computed(() =>
  activeOfficers.value.map((off) => ({ value: off.name, label: off.name, sublabel: off.role_label })),
)

const directVendorOptions = computed(() =>
  filteredDirectVendors.value.map((s) => ({ value: s.id, label: s.name, badge: s.code })),
)

const variantOptions = computed(() =>
  master.variants.map((v) => ({
    value: v.variant_id,
    label: variantLabel(v),
    sublabel: `Kode ${v.code} · Tersedia ${formatNumber(v.total_available)} ${v.unit}`,
    icon: v.photo_key ? attachmentUrl(v.photo_key) : itemFlaticonIcon(v.name),
  })),
)

const receiptConditionOptions = [
  { value: 'new', label: 'Baru' },
  { value: 'used_good', label: 'Bekas Layak' },
  { value: 'quarantine', label: 'Karantina' },
  { value: 'damaged', label: 'Rusak' },
]

watch(procSearch, (val) => {
  if (!val.trim() || props.editingPurchase || mode.value !== 'procurement') return
  const q = val.trim().toLowerCase()
  const exact = filteredProcurements.value.find(
    (p) => (p.po_number || '').toLowerCase() === q || p.procurement_no.toLowerCase() === q,
  )
  const target = exact || (filteredProcurements.value.length === 1 ? filteredProcurements.value[0] : null)
  if (target && target.id !== selectedProcId.value) {
    selectProcurement(target)
  }
})

async function loadPendingProcurements() {
  loadingProcs.value = true
  try {
    const res = await api<{ data: ProcurementOption[] }>('/api/procurements?pending=true')
    pendingProcurements.value = res.data
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat daftar pengadaan')
  } finally {
    loadingProcs.value = false
  }
}

function selectProcurement(proc: ProcurementOption) {
  selectedProcId.value = proc.id
  form.supplierId = proc.supplier_id
  form.reason = `Penerimaan ${proc.procurement_no}${proc.po_number ? ` (PO: ${proc.po_number})` : ''}`
  form.fundingSource = proc.funding_source
  form.paymentMethod = proc.payment_method
  form.funderId = proc.funder_id || ''
  form.lines = proc.items
    .filter((it) => it.ordered_quantity > it.received_quantity)
    .map((it) => {
      const rem = Number(it.ordered_quantity) - Number(it.received_quantity)
      const itemName = it.item_variants?.items?.name || 'Barang'
      const size = it.item_variants?.size || '-'
      const unit = it.item_variants?.items?.unit || ''
      return {
        procurementItemId: it.id,
        variantId: it.variant_id,
        label: variantLabel({ name: itemName, size }),
        unit,
        orderedQty: Number(it.ordered_quantity),
        alreadyReceived: Number(it.received_quantity),
        remainingQty: rem,
        quantity: rem,
        condition: 'new',
        receiverName: form.receiverNameDefault,
        notes: '',
      }
    })
}

function fillAllRemaining() {
  for (const line of form.lines) {
    if (line.remainingQty !== undefined) line.quantity = line.remainingQty
  }
}

function addDirectLine() {
  const first = master.variants[0]
  form.lines.push({
    procurementItemId: null,
    variantId: first?.variant_id || '',
    label: '',
    quantity: 1,
    condition: 'new',
    receiverName: form.receiverNameDefault,
    notes: '',
  })
}

function removeLine(idx: number) {
  form.lines.splice(idx, 1)
}

async function handleFileUpload(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const uploaded = await uploadAttachment(file)
    form.billingProofKey = uploaded.key
    toast.success(`Bukti penerimaan "${uploaded.name}" berhasil diunggah`)
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal mengunggah file')
  } finally {
    uploading.value = false
  }
}

watch(() => props.open, async (val) => {
  if (!val) return
  procSearch.value = ''
  filterByVariantId.value = ''
  form.receivedDate = new Date().toISOString().slice(0, 10)
  form.billingProofKey = ''
  selectedProcId.value = ''
  form.lines = []

  try {
    await Promise.all([master.refresh(), loadPendingProcurements()])
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data master')
  }

  form.receiverNameDefault = activeOfficers.value[0]?.name || 'Petugas Gudang'

  if (props.editingPurchase) {
    const ep = props.editingPurchase
    mode.value = ep.procurement_id ? 'procurement' : 'direct'
    selectedProcId.value = ep.procurement_id || ''
    form.receivedDate = ep.received_date.slice(0, 10)
    const matchedVendor = master.suppliers.find((s) => s.id === ep.supplier_id)
    directVendorType.value = matchedVendor?.vendor_type === 'online_shop' ? 'online_shop' : 'supplier'
    form.supplierId = ep.supplier_id || master.suppliers[0]?.id || ''
    form.reason = ep.reason || ''
    form.fundingSource = ep.funding_source || 'company'
    form.paymentMethod = ep.payment_method || 'transfer'
    form.funderId = ep.funder_id || ''
    form.billingProofKey = ep.billing_proof_key || ''
    form.receiverNameDefault = ep.purchase_items[0]?.receiver_name || form.receiverNameDefault
    form.lines = ep.purchase_items.map((it) => ({
      procurementItemId: it.procurement_item_id || null,
      variantId: it.variant_id,
      label: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }),
      unit: it.item_variants?.items?.unit || '',
      quantity: Number(it.quantity),
      condition: it.condition,
      receiverName: it.receiver_name,
      notes: it.notes || '',
    }))
    return
  }

  if (props.initialProcurementId) {
    mode.value = 'procurement'
    const found = pendingProcurements.value.find((p) => p.id === props.initialProcurementId)
    if (found) {
      selectProcurement(found)
      return
    }
  }

  mode.value = pendingProcurements.value.length ? 'procurement' : 'direct'
  const hasOnlineShop = master.suppliers.some((s) => s.vendor_type === 'online_shop')
  directVendorType.value = hasOnlineShop ? 'online_shop' : 'supplier'
  form.supplierId = filteredDirectVendors.value[0]?.id || master.suppliers[0]?.id || ''
  form.reason = ''
  form.fundingSource = 'company'
  form.paymentMethod = 'transfer'
  form.funderId = ''
  if (mode.value === 'direct') addDirectLine()
})

watch(mode, (val) => {
  if (props.editingPurchase) return
  if (val === 'direct') {
    const hasOnlineShop = master.suppliers.some((s) => s.vendor_type === 'online_shop')
    directVendorType.value = hasOnlineShop ? 'online_shop' : 'supplier'
    if (!form.supplierId || !filteredDirectVendors.value.some((v) => v.id === form.supplierId)) {
      form.supplierId = filteredDirectVendors.value[0]?.id || master.suppliers[0]?.id || ''
    }
  }
  if (val === 'direct' && !form.lines.some((l) => !l.procurementItemId)) {
    selectedProcId.value = ''
    form.lines = []
    addDirectLine()
  } else if (val === 'procurement') {
    form.lines = []
    if (selectedProcurement.value) selectProcurement(selectedProcurement.value)
  }
})

async function submit() {
  const activeLines = form.lines.filter((l) => Number(l.quantity) > 0 && l.variantId)
  if (!activeLines.length) {
    toast.error('Minimal 1 item dengan jumlah > 0 wajib diisi')
    return
  }
  if (!props.editingPurchase && mode.value === 'procurement' && !selectedProcId.value) {
    toast.error('Pilih pengadaan barang terlebih dahulu')
    return
  }
  saving.value = true
  try {
    const endpoint = props.editingPurchase ? `/api/transactions/purchases/${props.editingPurchase.id}` : '/api/transactions/purchases'
    const method = props.editingPurchase ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      headers: props.editingPurchase ? {} : { 'X-Idempotency-Key': generateUuid() },
      body: JSON.stringify({
        procurementId: mode.value === 'procurement' ? (selectedProcId.value || null) : null,
        receivedDate: form.receivedDate,
        supplierId: form.supplierId,
        reason: form.reason || 'Penerimaan barang masuk',
        fundingSource: form.fundingSource,
        paymentMethod: form.paymentMethod,
        funderId: form.fundingSource === 'advanced' ? form.funderId : null,
        totalPaid: 0,
        billingProofKey: form.billingProofKey || null,
        items: activeLines.map((l) => ({
          procurementItemId: l.procurementItemId || null,
          variantId: l.variantId,
          quantity: Number(l.quantity),
          condition: l.condition,
          receiverName: form.receiverNameDefault || 'Petugas Gudang',
          notes: l.notes || null,
        })),
      }),
    })
    await master.refresh(true)
    toast.success(props.editingPurchase ? 'Barang masuk berhasil diperbarui & stok disesuaikan!' : 'Barang masuk berhasil dicatat. Stok & progress pengadaan otomatis diperbarui!')
    emit('saved')
    emit('close')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan barang masuk')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal
    :open="open"
    :title="editingPurchase ? 'Edit Barang Masuk' : 'Catat Barang Masuk (Penerimaan)'"
    eyebrow="Penerimaan Gudang"
    subtitle="Kenali barang datang melalui No. Pengadaan / PO / Nama Barang agar progress pengadaan otomatis terupdate."
    size="lg"
    @close="emit('close')"
  >
    <form id="receipt-form" class="modal-form" @submit.prevent="submit">
      <div v-if="!editingPurchase" class="segmented-switch">
        <button type="button" :class="{ active: mode === 'procurement' }" @click="mode = 'procurement'">
          <PackageCheck :size="16" /> Berdasarkan Pengadaan (PO)
        </button>
        <button type="button" :class="{ active: mode === 'direct' }" @click="mode = 'direct'">
          <Plus :size="16" /> Pembelian Langsung (Tanpa Pengadaan)
        </button>
      </div>

      <!-- Smart Procurement Recognition Section -->
      <div v-if="mode === 'procurement' && !editingPurchase" class="lookup-box">
        <div class="lookup-header">
          <div>
            <strong>Pilih Nomor PO / Kode Pengadaan (PGD-...)</strong>
            <small>Pilih No. PO atau ketik nama barang untuk menarik otomatis daftar pengadaan barang yang sesuai.</small>
          </div>
        </div>
        <div class="form-grid-2">
          <label class="field">
            <span>Pilih Nomor PO / Pengadaan</span>
            <ModernSelect
              :model-value="selectedProcId"
              :options="procSelectOptions"
              placeholder="-- Pilih Nomor PO / Pengadaan --"
              @change="onDropdownSelect"
            />
          </label>
          <label class="field">
            <span>Cari Cepat No. PO / Nama Barang</span>
            <div class="search-field full">
              <Search :size="16" />
              <input v-model="procSearch" placeholder="Ketik No. PO, PGD-..., atau nama barang..." />
            </div>
          </label>
        </div>

        <div v-if="loadingProcs" class="muted-text">Memuat pengadaan aktif...</div>
        <div v-else-if="!pendingProcurements.length" class="empty-inline">
          Tidak ada pengadaan aktif yang menunggu penerimaan barang.
        </div>
        <div v-else-if="procSearch.trim() && !filteredProcurements.length" class="empty-inline">
          Tidak ada pengadaan aktif yang cocok dengan pencarian "{{ procSearch }}".
        </div>
        <div v-else-if="procSearch.trim() && filteredProcurements.length > 1" class="tag-group">
          <button
            v-for="proc in filteredProcurements"
            :key="proc.id"
            type="button"
            class="secondary-button xs"
            :class="{ highlight: selectedProcId === proc.id }"
            @click="selectProcurement(proc)"
          >
            {{ proc.po_number || proc.procurement_no }} · {{ proc.supplier_name }} ({{ proc.progress_percent }}%)
          </button>
        </div>

        <div v-if="selectedProcurement" class="proc-summary-card">
          <div class="proc-summary-head">
            <div class="tag-group">
              <span class="status-pill safe">{{ selectedProcurement.procurement_no }}</span>
              <span v-if="selectedProcurement.po_number" class="tag-pill">PO: {{ selectedProcurement.po_number }}</span>
              <span class="tag-pill">{{ selectedProcurement.vendor_type === 'online_shop' ? 'Toko Online' : 'Supplier' }}: {{ selectedProcurement.supplier_name }}</span>
            </div>
            <span class="progress-badge">{{ selectedProcurement.progress_percent }}% diterima</span>
          </div>
          <div class="proc-summary-meta">
            <span>Tanggal Order: <strong>{{ selectedProcurement.procurement_date }}</strong></span>
            <span>Total Diterima: <strong>{{ formatNumber(selectedProcurement.total_received) }} / {{ formatNumber(selectedProcurement.total_ordered) }} unit</strong></span>
            <span v-if="selectedProcurement.reason && selectedProcurement.reason.toLowerCase() !== 'kosong'">Keterangan: <strong>{{ selectedProcurement.reason }}</strong></span>
          </div>
          <div class="proc-items-list">
            <div v-for="it in selectedProcurement.items" :key="it.id" class="proc-item-row">
              <strong>{{ variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }) }}</strong>
              <div class="proc-item-stats">
                <span>Dipesan: <strong>{{ formatNumber(it.ordered_quantity) }}</strong> {{ it.item_variants?.items?.unit }}</span>
                <span>·</span>
                <span>Sudah Masuk: <strong>{{ formatNumber(it.received_quantity) }}</strong></span>
                <span>·</span>
                <span>Sisa: <b>{{ formatNumber(it.ordered_quantity - it.received_quantity) }} {{ it.item_variants?.items?.unit }}</b></span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="form-grid-3">
        <label class="field">
          <span>Tanggal Terima *</span>
          <input v-model="form.receivedDate" type="date" required />
        </label>
        <label class="field">
          <span>Petugas Penerima *</span>
          <ModernSelect v-if="activeOfficers.length" v-model="form.receiverNameDefault" :options="officerOptions" required />
          <input v-else v-model="form.receiverNameDefault" required placeholder="Atur nama petugas di Master & Pengaturan" />
        </label>
        <label class="field">
          <span>Bukti Penerimaan</span>
          <label class="file-upload-inline">
            <Upload :size="15" />
            <span>{{ uploading ? 'Mengunggah...' : (form.billingProofKey ? 'Bukti terunggah ✓' : 'Unggah JPG/PNG/PDF') }}</span>
            <input type="file" accept=".jpg,.jpeg,.png,.webp,.pdf" hidden @change="handleFileUpload" />
          </label>
        </label>
      </div>

      <div v-if="mode === 'direct'" class="modal-form" style="gap: 12px;">
        <div class="segmented-switch">
          <button type="button" :class="{ active: directVendorType === 'online_shop' }" @click="setDirectVendorType('online_shop')">
            <ShoppingBag :size="15" /> Pembelian via Toko Online
          </button>
          <button type="button" :class="{ active: directVendorType === 'supplier' }" @click="setDirectVendorType('supplier')">
            <Truck :size="15" /> Pembelian via Supplier
          </button>
        </div>
        <div class="form-grid-2">
          <label class="field">
            <span>{{ directVendorType === 'online_shop' ? 'Pilih Toko Online *' : 'Pilih Supplier *' }}</span>
            <ModernSelect v-model="form.supplierId" :options="directVendorOptions" required />
          </label>
          <label class="field">
            <span>Keperluan / Keterangan *</span>
            <input v-model="form.reason" required placeholder="Contoh: Beli sarung tangan di Shopee / supplier luar pengadaan" />
          </label>
        </div>
      </div>

      <!-- Items table inside modal -->
      <div class="lines-section">
        <div class="lines-header">
          <div>
            <strong>Daftar Barang Masuk</strong>
            <small v-if="selectedProcurement">Progress saat ini: {{ selectedProcurement.progress_percent }}% ({{ selectedProcurement.procurement_no }})</small>
          </div>
          <div class="lines-actions">
            <button v-if="mode === 'procurement' && form.lines.length" type="button" class="secondary-button sm" @click="fillAllRemaining">
              <CheckCheck :size="15" /> Isi Semua Sisa
            </button>
            <button v-if="mode === 'direct'" type="button" class="secondary-button sm" @click="addDirectLine">
              <Plus :size="15" /> Tambah Baris
            </button>
          </div>
        </div>

        <div v-if="form.lines.length" class="modal-lines-list">
          <div v-for="(line, idx) in form.lines" :key="idx" class="modal-line-card">
            <div class="line-top">
              <template v-if="line.procurementItemId">
                <div class="line-title">
                  <strong>{{ line.label }}</strong>
                  <span v-if="line.unit" class="tag-pill">Satuan: {{ line.unit }}</span>
                  <span class="tag-pill">Pesan: {{ line.orderedQty }} · Masuk: {{ line.alreadyReceived }} · Sisa: <b>{{ line.remainingQty }}</b></span>
                </div>
              </template>
              <template v-else>
                <ModernSelect v-model="line.variantId" :options="variantOptions" required search-placeholder="Cari nama APD..." style="flex:1;" />
              </template>
              <button v-if="mode === 'direct' && form.lines.length > 1" type="button" class="icon-button danger" @click="removeLine(idx)">
                <Trash2 :size="15" />
              </button>
            </div>
            <div class="form-grid-3">
              <label class="field">
                <span>Qty Datang {{ line.remainingQty !== undefined ? `(Maks ${line.remainingQty})` : '*' }}</span>
                <input
                  v-model.number="line.quantity"
                  type="number"
                  min="0"
                  :max="line.remainingQty"
                  step="any"
                />
              </label>
              <label class="field">
                <span>Kondisi Barang *</span>
                <ModernSelect v-model="line.condition" :options="receiptConditionOptions" :searchable="false" />
              </label>
              <label class="field">
                <span>Catatan Barang</span>
                <input v-model="line.notes" placeholder="Opsional (mis. 1 dus penyok)" />
              </label>
            </div>
          </div>
        </div>
        <div v-if="accumulatedSummary.length" class="variant-stock-chip">
          <strong>Akumulasi Masuk:</strong>
          <div class="tag-group">
            <span v-for="(acc, aIdx) in accumulatedSummary" :key="aIdx" class="tag-pill">
              {{ acc.name }}: <b>+{{ formatNumber(acc.total) }}</b>
            </span>
          </div>
        </div>
        <div v-else-if="!form.lines.length" class="empty-inline">Pilih Nomor PO / Pengadaan di atas untuk memuat daftar barang yang akan diterima.</div>
      </div>
    </form>

    <template #footer>
      <button type="button" class="secondary-button" @click="emit('close')">Batal</button>
      <button type="submit" form="receipt-form" class="primary-button" :disabled="saving || !form.lines.length">
        {{ saving ? 'Menyimpan...' : 'Simpan Barang Masuk & Tambah Stok' }}
      </button>
    </template>
  </BaseModal>
</template>
