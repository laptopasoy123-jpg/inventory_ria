<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { AlertTriangle, CheckCircle2, Edit3, PackageCheck, Plus, Search, Upload } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { api, formatDate, formatNumber, generateUuid, uploadAttachment, variantLabel } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore } from '@/stores/master'

interface ReturnRow {
  id: string; transaction_no: string; returned_at: string; employee_id: string; inspector_name: string;
  proof_key?: string | null;
  employees?: { nik: string; name: string; departments?: { name: string } | null } | null;
  return_items: Array<{
    id: string; issuance_item_id: string; quantity: number; result: 'used_good' | 'maintenance' | 'damaged' | 'lost'; reusable?: boolean; reason: string | null;
    issuance_items?: { item_variants?: { size: string; items?: { name: string; unit: string } | null } | null } | null
  }>
}

interface OpenIssuanceItem {
  id: string; quantity: number; returned_quantity: number; resolved_lost_quantity: number; purpose: string;
  issuances?: { transaction_no: string; issued_at: string } | null;
  item_variants?: { size: string; items?: { code: string; name: string; unit: string; return_required: boolean } | null } | null
}

const master = useMasterStore()
const toast = useToast()

const rows = ref<ReturnRow[]>([])
const loading = ref(true)
const filterResult = ref('all')
const search = ref('')
const page = ref(1)

const showModal = ref(false)
const editingId = ref<string | null>(null)
const loadingOpen = ref(false)
const saving = ref(false)
const uploading = ref(false)

interface ReturnDraftLine {
  selected: boolean
  issuanceItemId: string
  label: string
  unit: string
  txNo: string
  remaining: number
  returnedQty: number
  lostQty: number
  notes: string
}

const form = reactive({
  returnedAt: new Date().toISOString().slice(0, 10),
  employeeId: '',
  inspectorName: 'Inspektor K3',
  proofKey: '',
  lines: [] as ReturnDraftLine[],
})

const filtered = computed(() => {
  return rows.value.filter((r) => {
    if (filterResult.value === 'returned' && !r.return_items.some((it) => it.result !== 'lost')) return false
    if (filterResult.value === 'lost' && !r.return_items.some((it) => it.result === 'lost')) return false
    if (!search.value.trim()) return true
    const q = search.value.toLowerCase()
    return r.transaction_no.toLowerCase().includes(q) || (r.employees?.name || '').toLowerCase().includes(q) || r.inspector_name.toLowerCase().includes(q)
  })
})

const pagedRows = computed(() => filtered.value.slice((page.value - 1) * 10, page.value * 10))
watch([filterResult, search], () => { page.value = 1 })

async function load() {
  loading.value = true
  try {
    const res = await api<{ data: ReturnRow[] }>('/api/transactions/returns')
    rows.value = res.data
  } finally {
    loading.value = false
  }
}

async function loadEmployeeOpenItems(employeeId: string) {
  if (!employeeId) {
    form.lines = []
    return
  }
  loadingOpen.value = true
  try {
    const res = await api<{ data: OpenIssuanceItem[] }>(`/api/transactions/issuances/open-by-employee/${employeeId}`)
    form.lines = res.data.map((it) => {
      const rem = Number(it.quantity) - Number(it.returned_quantity) - Number(it.resolved_lost_quantity)
      return {
        selected: true,
        issuanceItemId: it.id,
        label: variantLabel({ name: it.item_variants?.items?.name || 'Barang', size: it.item_variants?.size }),
        unit: it.item_variants?.items?.unit || 'unit',
        txNo: `${it.issuances?.transaction_no || '-'} · ${formatDate(it.issuances?.issued_at)}`,
        remaining: rem,
        returnedQty: rem,
        lostQty: 0,
        notes: '',
      }
    })
  } finally {
    loadingOpen.value = false
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

function onLostQtyChange(line: ReturnDraftLine) {
  const lost = Math.max(0, Math.min(line.remaining, Number(line.lostQty || 0)))
  line.lostQty = lost
  if (line.returnedQty + lost > line.remaining) {
    line.returnedQty = Math.max(0, line.remaining - lost)
  }
}

function onReturnedQtyChange(line: ReturnDraftLine) {
  const ret = Math.max(0, Math.min(line.remaining, Number(line.returnedQty || 0)))
  line.returnedQty = ret
  if (ret + line.lostQty > line.remaining) {
    line.lostQty = Math.max(0, line.remaining - ret)
  }
}

async function openModal() {
  editingId.value = null
  form.returnedAt = new Date().toISOString().slice(0, 10)
  form.proofKey = ''
  showModal.value = true

  try {
    await master.refresh()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memuat data master')
  }

  form.employeeId = master.employees[0]?.id || ''
  form.inspectorName = activeOfficers.value[0]?.name || 'Inspektor K3'
  if (form.employeeId) await loadEmployeeOpenItems(form.employeeId)
}

async function openEditModal(row: ReturnRow) {
  editingId.value = row.id
  form.returnedAt = row.returned_at.slice(0, 10)
  form.employeeId = row.employee_id
  form.inspectorName = row.inspector_name
  form.proofKey = row.proof_key || ''
  showModal.value = true

  loadingOpen.value = true
  try {
    await master.refresh()
    const res = await api<{ data: OpenIssuanceItem[] }>(`/api/transactions/issuances/open-by-employee/${row.employee_id}`)
    const openMap = new Map(res.data.map((it) => [it.id, it]))
    const grouped = new Map<string, ReturnDraftLine>()
    for (const it of row.return_items) {
      const openItem = openMap.get(it.issuance_item_id)
      const extra = openItem ? Number(openItem.quantity) - Number(openItem.returned_quantity) - Number(openItem.resolved_lost_quantity) : 0
      const prev = grouped.get(it.issuance_item_id)
      const qty = Number(it.quantity)
      if (prev) {
        prev.remaining += qty
        if (it.result === 'lost') prev.lostQty += qty
        else prev.returnedQty += qty
        if (it.reason && !prev.notes) prev.notes = it.reason
      } else {
        grouped.set(it.issuance_item_id, {
          selected: true,
          issuanceItemId: it.issuance_item_id,
          label: variantLabel({ name: it.issuance_items?.item_variants?.items?.name || 'Barang', size: it.issuance_items?.item_variants?.size }),
          unit: it.issuance_items?.item_variants?.items?.unit || 'unit',
          txNo: row.transaction_no,
          remaining: qty + extra,
          returnedQty: it.result === 'lost' ? 0 : qty,
          lostQty: it.result === 'lost' ? qty : 0,
          notes: it.reason || '',
        })
      }
    }
    form.lines = [...grouped.values()]
  } finally {
    loadingOpen.value = false
  }
}

watch(() => form.employeeId, (val) => {
  if (showModal.value && !editingId.value) loadEmployeeOpenItems(val)
})

async function handleUpload(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const res = await uploadAttachment(file)
    form.proofKey = res.key
    toast.success('Bukti pengembalian diunggah')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal unggah')
  } finally {
    uploading.value = false
  }
}

async function submit() {
  const chosen = form.lines.filter((l) => l.selected && (Number(l.returnedQty || 0) > 0 || Number(l.lostQty || 0) > 0))
  if (!chosen.length) {
    toast.error('Pilih minimal 1 item dengan Qty Dikembalikan atau Qty Hilang > 0')
    return
  }

  const payloadItems: Array<{
    issuanceItemId: string
    quantity: number
    inspectionResult: 'used_good' | 'lost'
    reusable: boolean
    reason: string | null
  }> = []

  for (const l of chosen) {
    const ret = Number(l.returnedQty || 0)
    const lost = Number(l.lostQty || 0)
    if (ret + lost > l.remaining) {
      toast.error(`Total kembali + hilang melebihi sisa tanggungan ${l.remaining} (${l.label})`)
      return
    }
    if (lost > 0 && !l.notes.trim()) {
      toast.error(`Catatan tambahan wajib diisi jika ada barang hilang (${l.label})`)
      return
    }
    if (ret > 0) {
      payloadItems.push({
        issuanceItemId: l.issuanceItemId,
        quantity: ret,
        inspectionResult: 'used_good',
        reusable: true,
        reason: l.notes.trim() || null,
      })
    }
    if (lost > 0) {
      payloadItems.push({
        issuanceItemId: l.issuanceItemId,
        quantity: lost,
        inspectionResult: 'lost',
        reusable: false,
        reason: l.notes.trim(),
      })
    }
  }

  saving.value = true
  try {
    const endpoint = editingId.value ? `/api/transactions/returns/${editingId.value}` : '/api/transactions/returns'
    const method = editingId.value ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      headers: editingId.value ? {} : { 'X-Idempotency-Key': generateUuid() },
      body: JSON.stringify({
        returnedAt: form.returnedAt,
        employeeId: form.employeeId,
        inspectorName: form.inspectorName,
        proofKey: form.proofKey || null,
        items: payloadItems,
      }),
    })
    await Promise.all([load(), master.refresh(true)])
    toast.success(editingId.value ? 'Pengembalian APD berhasil diperbarui!' : 'Pengembalian APD diproses! Barang yang kembali masuk ke stok tersedia & kehilangan tercatat.')
    showModal.value = false
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal memproses pengembalian')
  } finally {
    saving.value = false
  }
}

function resultBadge(r: string) {
  if (r === 'lost') return { label: 'Hilang', cls: 'out', effect: 'Tercatat di Log Kehilangan / SO' }
  return { label: 'Dikembalikan', cls: 'safe', effect: 'Masuk stok tersedia (Bekas Layak)' }
}

onMounted(async () => {
  await Promise.all([load(), master.refresh()])
})
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Pengembalian & Tanggungan</p>
        <h2>Pengembalian APD</h2>
        <p>Tarik tanggungan APD aktif karyawan. Barang yang dikembalikan masuk stok tersedia; barang hilang ditandai & masuk catatan Stok Opname.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" @click="openModal"><Plus :size="17" /> Catat Pengembalian</button>
      </div>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: filterResult === 'all' }" @click="filterResult = 'all'">Semua</button>
        <button :class="{ active: filterResult === 'returned' }" @click="filterResult = 'returned'">Dikembalikan ke Stok</button>
        <button :class="{ active: filterResult === 'lost' }" @click="filterResult = 'lost'">Ada Hilang</button>
      </div>
      <div class="table-toolbar">
        <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Pengembalian, karyawan, atau petugas..." /></label>
      </div>

      <div class="table-wrap">
        <table>
          <thead><tr><th>No. Pengembalian</th><th>Karyawan</th><th>APD Dikembalikan / Hilang</th><th>Status & Dampak Stok</th><th>Petugas</th><th>Aksi</th></tr></thead>
          <tbody>
            <tr v-for="row in pagedRows" :key="row.id">
              <td><strong>{{ row.transaction_no }}</strong><small class="table-sub">{{ formatDate(row.returned_at) }}</small></td>
              <td>
                <strong class="table-main">{{ row.employees?.name || '-' }}</strong>
                <small class="table-sub">{{ row.employees?.nik }} · {{ row.employees?.departments?.name || '-' }}</small>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="it in row.return_items" :key="it.id">
                    <strong>{{ formatNumber(it.quantity) }} {{ it.issuance_items?.item_variants?.items?.unit }}</strong>
                    {{ variantLabel({ name: it.issuance_items?.item_variants?.items?.name, size: it.issuance_items?.item_variants?.size }) }}
                    <span class="status-pill" :class="resultBadge(it.result).cls" style="margin-left:6px;">{{ resultBadge(it.result).label }}</span>
                  </span>
                </div>
              </td>
              <td>
                <div class="compact-items">
                  <span v-for="it in row.return_items" :key="it.id">
                    <small>{{ resultBadge(it.result).effect }} <template v-if="it.reason">({{ it.reason }})</template></small>
                  </span>
                </div>
              </td>
              <td>{{ row.inspector_name }}</td>
              <td><button class="icon-button" title="Edit pengembalian" @click="openEditModal(row)"><Edit3 :size="15" /></button></td>
            </tr>
            <tr v-if="!loading && !filtered.length">
              <td colspan="6"><div class="empty-state"><PackageCheck :size="32" /><strong>Belum ada pengembalian APD</strong><span>Pilih karyawan untuk menarik sisa tanggungan APD aktifnya.</span></div></td>
            </tr>
            <tr v-if="loading"><td colspan="6"><div class="loading-row">Memuat riwayat pengembalian...</div></td></tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filtered.length" />
    </section>

    <BaseModal
      :open="showModal"
      :title="editingId ? 'Edit Pengembalian APD' : 'Catat Pengembalian APD'"
      eyebrow="Pengembalian ke Inventaris"
      subtitle="Pilih karyawan untuk memuat otomatis daftar APD yang masih menjadi tanggungannya."
      size="lg"
      @close="showModal = false"
    >
      <form id="return-form" class="modal-form" @submit.prevent="submit">
        <div class="form-grid-3">
          <label class="field"><span>Tanggal Kembali *</span><input v-model="form.returnedAt" type="date" required /></label>
          <label class="field"><span>Karyawan *</span>
            <ModernSelect v-model="form.employeeId" :options="employeeOptions" :disabled="Boolean(editingId)" required />
          </label>
          <label class="field"><span>Petugas Penerima / Pemeriksa *</span>
            <ModernSelect v-if="activeOfficers.length" v-model="form.inspectorName" :options="officerOptions" required />
            <input v-else v-model="form.inspectorName" required />
          </label>
        </div>

        <div class="lines-section">
          <div class="lines-header">
            <div>
              <strong>Tanggungan APD Aktif Karyawan</strong>
              <small>Centang barang yang diproses, lalu isi jumlah dikembalikan atau hilang.</small>
            </div>
          </div>
          <div v-if="loadingOpen" class="loading-row">Mencari tanggungan APD...</div>
          <div v-else-if="!form.lines.length" class="empty-inline">Karyawan ini tidak memiliki sisa tanggungan APD aktif.</div>
          <div v-else class="modal-lines-list">
            <div v-for="(line, idx) in form.lines" :key="idx" class="modal-line-card">
              <div class="return-card-head">
                <label class="checkbox-inline">
                  <input v-model="line.selected" type="checkbox" />
                  <strong>{{ line.label }}</strong>
                </label>
                <div class="return-card-meta">
                  <span class="tag-pill">{{ line.txNo }}</span>
                  <span class="tag-pill">Tanggungan: <b>{{ formatNumber(line.remaining) }} {{ line.unit }}</b></span>
                  <span v-if="line.selected && line.lostQty > 0" class="status-pill out">
                    <AlertTriangle :size="12" /> Hilang: {{ line.lostQty }}
                  </span>
                </div>
              </div>
              <div v-if="line.selected" class="form-grid-3">
                <label class="field">
                  <span>Qty Dikembalikan</span>
                  <input
                    v-model.number="line.returnedQty"
                    type="number"
                    min="0"
                    :max="line.remaining"
                    step="any"
                    @input="onReturnedQtyChange(line)"
                  />
                </label>
                <label class="field">
                  <span>Qty Hilang</span>
                  <input
                    v-model.number="line.lostQty"
                    type="number"
                    min="0"
                    :max="line.remaining"
                    step="any"
                    @input="onLostQtyChange(line)"
                  />
                </label>
                <label class="field">
                  <span>Catatan Tambahan {{ line.lostQty > 0 ? '*' : '(Opsional)' }}</span>
                  <input
                    v-model="line.notes"
                    :required="line.lostQty > 0"
                    :placeholder="line.lostQty > 0 ? 'Wajib isi alasan/kronologi kehilangan' : 'Catatan kondisi / keterangan tambahan'"
                  />
                </label>
              </div>
              <div v-if="line.selected && line.returnedQty > 0" class="positive-hint">
                <CheckCircle2 :size="14" /> <b>+{{ formatNumber(line.returnedQty) }} unit</b> otomatis masuk kembali ke stok tersedia.
              </div>
              <div v-if="line.selected && line.lostQty > 0" class="error-hint" style="margin-top:4px;">
                <AlertTriangle :size="14" /> <b>{{ formatNumber(line.lostQty) }} unit hilang</b> ditandai dan tercatat di Log Kehilangan / Stok Opname (tidak masuk stok).
              </div>
            </div>
          </div>
        </div>

        <label class="field"><span>Bukti Pengembalian (Opsional)</span>
          <label class="file-upload-inline">
            <Upload :size="15" />
            <span>{{ uploading ? 'Mengunggah...' : (form.proofKey ? 'Bukti terunggah ✓' : 'Unggah JPG/PNG/PDF') }}</span>
            <input type="file" accept=".jpg,.jpeg,.png,.webp,.pdf" hidden @change="handleUpload" />
          </label>
        </label>
      </form>
      <template #footer>
        <button type="button" class="secondary-button" @click="showModal = false">Batal</button>
        <button type="submit" form="return-form" class="primary-button" :disabled="saving || !form.lines.some(l => l.selected)">
          {{ saving ? 'Memproses...' : (editingId ? 'Simpan Perubahan' : 'Simpan Pengembalian') }}
        </button>
      </template>
    </BaseModal>
  </div>
</template>
