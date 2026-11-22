<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { Upload } from '@lucide/vue'
import BaseModal from './BaseModal.vue'
import ModernSelect from './ModernSelect.vue'
import { api, formatCurrency, uploadAttachment } from '@/lib/api'
import { useToast } from '@/composables/useToast'

export interface ProcurementPayItem {
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
}

export interface EditablePayment {
  id: string
  procurement_id: string
  paid_at: string
  amount: number
  payment_method: 'cash' | 'transfer'
  payment_type: 'dp' | 'installment' | 'full' | 'reimbursement'
  reference_no: string | null
  proof_key?: string | null
  notes: string | null
}

const props = defineProps<{
  open: boolean
  procurements: ProcurementPayItem[]
  initialProcurementId?: string | null
  editingPayment?: EditablePayment | null
}>()

const emit = defineEmits<{ close: []; saved: [] }>()
const toast = useToast()
const saving = ref(false)
const uploading = ref(false)

const form = reactive({
  procurementId: '',
  paidAt: new Date().toISOString().slice(0, 10),
  paymentType: 'full' as 'dp' | 'installment' | 'full' | 'reimbursement',
  paymentMethod: 'transfer' as 'cash' | 'transfer',
  amount: 0,
  referenceNo: '',
  proofKey: '',
  notes: '',
})

const selectedProc = computed(() => props.procurements.find((p) => p.id === form.procurementId) || null)

const procOptions = computed(() =>
  props.procurements.map((p) => ({
    value: p.id,
    label: `${p.procurement_no} — ${p.supplier_name}`,
    sublabel: p.po_number ? `PO ${p.po_number}` : undefined,
    badge: `Sisa ${formatCurrency(p.remaining_amount)}`,
  })),
)

const payTypeOptions = computed(() => {
  const opts = [
    { value: 'full', label: 'Pelunasan' },
    { value: 'dp', label: 'Uang Muka (DP)' },
    { value: 'installment', label: 'Cicilan / Termin' },
  ]
  if (selectedProc.value?.funding_source === 'advanced') {
    opts.push({
      value: 'reimbursement',
      label: `Reimbursement ke ${selectedProc.value.funder_name || 'Penalang'}`,
    })
  }
  return opts
})

const payMethodOptions = [
  { value: 'transfer', label: 'Transfer Bank' },
  { value: 'cash', label: 'Tunai / Kas' },
]

const maxPayable = computed(() => {
  if (!selectedProc.value) return 0
  const editOffset = props.editingPayment && props.editingPayment.procurement_id === selectedProc.value.id && props.editingPayment.payment_type === form.paymentType
    ? Number(props.editingPayment.amount)
    : 0
  if (form.paymentType === 'reimbursement') {
    return Math.max(0, Number(selectedProc.value.total_amount) - Number(selectedProc.value.reimbursed_amount || 0) + editOffset)
  }
  return Math.max(0, Number(selectedProc.value.remaining_amount) + editOffset)
})

watch(() => props.open, (val) => {
  if (!val) return
  if (props.editingPayment) {
    const ep = props.editingPayment
    form.procurementId = ep.procurement_id
    form.paidAt = ep.paid_at.slice(0, 10)
    form.paymentType = ep.payment_type
    form.paymentMethod = ep.payment_method
    form.amount = Number(ep.amount)
    form.referenceNo = ep.reference_no || ''
    form.proofKey = ep.proof_key || ''
    form.notes = ep.notes || ''
    return
  }

  form.paidAt = new Date().toISOString().slice(0, 10)
  form.referenceNo = ''
  form.proofKey = ''
  form.notes = ''
  form.paymentMethod = 'transfer'
  const target = props.initialProcurementId
    ? props.procurements.find((p) => p.id === props.initialProcurementId)
    : props.procurements.find((p) => p.payment_status !== 'paid') || props.procurements[0]
  form.procurementId = target?.id || ''
  if (target) {
    form.paymentType = target.payment_status === 'paid' && target.funding_source === 'advanced' ? 'reimbursement' : 'full'
    form.amount = form.paymentType === 'reimbursement'
      ? Math.max(0, Number(target.total_amount) - Number(target.reimbursed_amount || 0))
      : Math.max(0, Number(target.remaining_amount))
  }
})

watch([() => form.procurementId, () => form.paymentType], () => {
  if (props.editingPayment || !selectedProc.value) return
  if (form.paymentType === 'reimbursement' && selectedProc.value.funding_source !== 'advanced') {
    form.paymentType = 'full'
  }
  form.amount = maxPayable.value
})

async function handleUpload(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const res = await uploadAttachment(file)
    form.proofKey = res.key
    toast.success('Bukti pembayaran diunggah')
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal unggah bukti')
  } finally {
    uploading.value = false
  }
}

async function submit() {
  if (!form.procurementId) return
  saving.value = true
  try {
    const endpoint = props.editingPayment ? `/api/procurements/payments/${props.editingPayment.id}` : '/api/procurements/payments'
    const method = props.editingPayment ? 'PUT' : 'POST'
    await api(endpoint, {
      method,
      body: JSON.stringify({
        procurementId: form.procurementId,
        paidAt: form.paidAt,
        amount: Number(form.amount),
        paymentMethod: form.paymentMethod,
        paymentType: form.paymentType,
        referenceNo: form.referenceNo || null,
        proofKey: form.proofKey || null,
        notes: form.notes || null,
      }),
    })
    toast.success(props.editingPayment ? 'Pembayaran berhasil diperbarui' : 'Pembayaran pengadaan berhasil dicatat')
    emit('saved')
    emit('close')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan pembayaran')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal
    :open="open"
    :title="editingPayment ? 'Edit Pembayaran Pengadaan' : 'Catat Pembayaran Pengadaan'"
    eyebrow="Pembayaran & Reimbursement"
    subtitle="Pembayaran terhubung langsung ke pengadaan barang (DP, termin, pelunasan, atau reimbursement talangan)."
    size="md"
    @close="emit('close')"
  >
    <form id="payment-form" class="modal-form" @submit.prevent="submit">
      <label class="field">
        <span>Pilih Pengadaan Barang *</span>
        <ModernSelect
          v-model="form.procurementId"
          :options="procOptions"
          :disabled="Boolean(editingPayment)"
          required
          placeholder="Pilih pengadaan"
        />
      </label>

      <div v-if="selectedProc" class="summary-banner">
        <div>
          <small>Total Nilai Pengadaan</small>
          <strong>{{ formatCurrency(selectedProc.total_amount) }}</strong>
        </div>
        <div>
          <small>Sudah Dibayar</small>
          <strong>{{ formatCurrency(selectedProc.paid_amount) }}</strong>
        </div>
        <div>
          <small>Sisa Tagihan</small>
          <strong class="text-primary">{{ formatCurrency(selectedProc.remaining_amount) }}</strong>
        </div>
      </div>

      <div class="form-grid-2">
        <label class="field">
          <span>Jenis Pembayaran *</span>
          <ModernSelect v-model="form.paymentType" :options="payTypeOptions" required :searchable="false" />
        </label>
        <label class="field">
          <span>Tanggal Bayar *</span>
          <input v-model="form.paidAt" type="date" required />
        </label>
      </div>

      <div class="form-grid-2">
        <label class="field">
          <span>Nominal Bayar (Maks {{ formatCurrency(maxPayable) }}) *</span>
          <input v-model.number="form.amount" type="number" min="1" :max="maxPayable" step="any" required />
        </label>
        <label class="field">
          <span>Metode Pembayaran *</span>
          <ModernSelect v-model="form.paymentMethod" :options="payMethodOptions" required :searchable="false" />
        </label>
      </div>

      <div class="form-grid-2">
        <label class="field">
          <span>No. Referensi / Kwitansi</span>
          <input v-model="form.referenceNo" placeholder="Contoh: TRF-20261119-01" />
        </label>
        <label class="field">
          <span>Bukti Transfer / Kwitansi</span>
          <label class="file-upload-inline">
            <Upload :size="15" />
            <span>{{ uploading ? 'Mengunggah...' : (form.proofKey ? 'Bukti terunggah ✓' : 'Unggah JPG/PNG/PDF') }}</span>
            <input type="file" accept=".jpg,.jpeg,.png,.webp,.pdf" hidden @change="handleUpload" />
          </label>
        </label>
      </div>

      <label class="field">
        <span>Catatan</span>
        <textarea v-model="form.notes" rows="2" placeholder="Keterangan termin atau pelunasan..." />
      </label>
    </form>

    <template #footer>
      <button type="button" class="secondary-button" @click="emit('close')">Batal</button>
      <button type="submit" form="payment-form" class="primary-button" :disabled="saving || !form.procurementId || maxPayable <= 0">
        {{ saving ? 'Menyimpan...' : (editingPayment ? 'Simpan Perubahan' : 'Simpan Pembayaran') }}
      </button>
    </template>
  </BaseModal>
</template>
