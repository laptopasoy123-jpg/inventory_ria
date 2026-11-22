<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { CheckCircle2, Edit3, HandCoins, Plus, ReceiptText, Search, Wallet } from '@lucide/vue'
import ModernSelect from '@/components/ModernSelect.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import PaymentModal, { type EditablePayment, type ProcurementPayItem } from '@/components/PaymentModal.vue'
import { api, formatCurrency, formatDate } from '@/lib/api'

interface ProcurementPayRow extends ProcurementPayItem {
  procurement_date: string
  progress_percent: number
  status: string
}

interface PaymentHistoryRow extends EditablePayment {
  procurements?: { procurement_no: string; po_number: string | null; suppliers?: { name: string } | null } | null
}

const procurements = ref<ProcurementPayRow[]>([])
const payments = ref<PaymentHistoryRow[]>([])
const loading = ref(true)
const viewTab = ref<'bills' | 'history'>('bills')
const statusFilter = ref('all')
const statusFilterOptions = [
  { value: 'all', label: 'Semua status bayar' },
  { value: 'unpaid', label: 'Belum Dibayar' },
  { value: 'partial', label: 'DP / Sebagian' },
  { value: 'paid', label: 'Lunas' },
  { value: 'advanced', label: 'Dana Talangan' },
]
const search = ref('')
const billsPage = ref(1)
const historyPage = ref(1)

const showModal = ref(false)
const selectedProcId = ref<string | null>(null)
const editingPay = ref<EditablePayment | null>(null)

const totalValue = computed(() => procurements.value.filter(p => p.status !== 'cancelled').reduce((s, p) => s + Number(p.total_amount), 0))
const totalPaid = computed(() => procurements.value.filter(p => p.status !== 'cancelled').reduce((s, p) => s + Number(p.paid_amount), 0))
const totalRemaining = computed(() => procurements.value.filter(p => p.status !== 'cancelled').reduce((s, p) => s + Number(p.remaining_amount), 0))

const filteredBills = computed(() => {
  return procurements.value.filter((p) => {
    if (p.status === 'cancelled') return false
    if (statusFilter.value === 'advanced' && p.funding_source !== 'advanced') return false
    else if (statusFilter.value !== 'all' && statusFilter.value !== 'advanced' && p.payment_status !== statusFilter.value) return false
    if (!search.value.trim()) return true
    const q = search.value.toLowerCase()
    return p.procurement_no.toLowerCase().includes(q) || (p.po_number || '').toLowerCase().includes(q) || p.supplier_name.toLowerCase().includes(q)
  })
})

const pagedBills = computed(() => filteredBills.value.slice((billsPage.value - 1) * 10, billsPage.value * 10))
const pagedPayments = computed(() => payments.value.slice((historyPage.value - 1) * 10, historyPage.value * 10))
watch([statusFilter, search, viewTab], () => { billsPage.value = 1; historyPage.value = 1 })

async function load() {
  loading.value = true
  try {
    const [pRes, hRes] = await Promise.all([
      api<{ data: ProcurementPayRow[] }>('/api/procurements'),
      api<{ data: PaymentHistoryRow[] }>('/api/procurements/payments/all'),
    ])
    procurements.value = pRes.data
    payments.value = hRes.data
  } finally {
    loading.value = false
  }
}

function openPayModal(procId?: string) {
  editingPay.value = null
  selectedProcId.value = procId || null
  showModal.value = true
}

function openEditPay(pay: PaymentHistoryRow) {
  editingPay.value = pay
  selectedProcId.value = pay.procurement_id
  showModal.value = true
}

function payLabel(type: string) {
  const map: Record<string, string> = { dp: 'Uang Muka (DP)', installment: 'Termin / Cicilan', full: 'Pelunasan', reimbursement: 'Reimbursement' }
  return map[type] || type
}

onMounted(load)
</script>

<template>
  <div>
    <section class="page-intro">
      <div>
        <p class="eyebrow">Kontrol Pembayaran Pengadaan</p>
        <h2>Pembayaran & Reimbursement</h2>
        <p>Setiap tagihan, DP, termin, pelunasan, dan reimbursement dana talangan tercatat langsung berdasarkan Pengadaan Barang.</p>
      </div>
      <div class="intro-actions">
        <button class="primary-button" :disabled="!procurements.length" @click="openPayModal()"><Plus :size="17" /> Catat Pembayaran</button>
      </div>
    </section>

    <section class="mini-stats">
      <div><span class="mini-icon teal"><ReceiptText :size="19" /></span><p>Total Nilai Pengadaan<strong>{{ formatCurrency(totalValue) }}</strong></p></div>
      <div><span class="mini-icon teal"><CheckCircle2 :size="19" /></span><p>Sudah Dibayar<strong>{{ formatCurrency(totalPaid) }}</strong></p></div>
      <div><span class="mini-icon red"><Wallet :size="19" /></span><p>Sisa Tagihan<strong>{{ formatCurrency(totalRemaining) }}</strong></p></div>
    </section>

    <section class="panel data-panel">
      <div class="record-tabs">
        <button :class="{ active: viewTab === 'bills' }" @click="viewTab = 'bills'">Tagihan per Pengadaan</button>
        <button :class="{ active: viewTab === 'history' }" @click="viewTab = 'history'">Riwayat Pembayaran ({{ payments.length }})</button>
      </div>

      <template v-if="viewTab === 'bills'">
        <div class="table-toolbar">
          <label class="search-field"><Search :size="16" /><input v-model="search" placeholder="Cari No. Pengadaan, No. PO, atau supplier..." /></label>
          <ModernSelect v-model="statusFilter" :options="statusFilterOptions" compact :searchable="false" />
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Pengadaan & Supplier</th><th>Progress Barang</th><th>Total Tagihan</th><th>Sudah Dibayar</th><th>Sisa Tagihan</th><th>Status</th><th>Aksi</th></tr></thead>
            <tbody>
              <tr v-for="row in pagedBills" :key="row.id">
                <td>
                  <strong>{{ row.procurement_no }}</strong> <span v-if="row.po_number" class="tag-pill">PO: {{ row.po_number }}</span>
                  <small class="table-sub">{{ row.supplier_name }} · {{ formatDate(row.procurement_date) }}</small>
                </td>
                <td>
                  <div class="progress-cell sm">
                    <div class="progress-track"><div class="progress-fill" :style="{ width: `${row.progress_percent}%` }" /></div>
                    <small>{{ row.progress_percent }}% diterima</small>
                  </div>
                </td>
                <td><strong>{{ formatCurrency(row.total_amount) }}</strong></td>
                <td>{{ formatCurrency(row.paid_amount) }}</td>
                <td><strong :class="row.remaining_amount > 0 ? 'text-red' : 'text-primary'">{{ formatCurrency(row.remaining_amount) }}</strong></td>
                <td>
                  <span class="status-pill" :class="row.payment_status === 'paid' ? 'safe' : row.payment_status === 'partial' ? 'amber' : 'out'">
                    {{ row.payment_status === 'paid' ? 'Lunas' : row.payment_status === 'partial' ? 'Sebagian' : 'Belum Dibayar' }}
                  </span>
                  <small v-if="row.funding_source === 'advanced'" class="table-sub">Talangan: {{ row.funder_name }}</small>
                </td>
                <td>
                  <button
                    v-if="row.payment_status !== 'paid' || (row.funding_source === 'advanced' && row.reimbursement_status !== 'paid')"
                    class="primary-button xs"
                    @click="openPayModal(row.id)"
                  >
                    <HandCoins :size="13" /> Bayar
                  </button>
                  <span v-else class="muted-text">Selesai</span>
                </td>
              </tr>
              <tr v-if="!loading && !filteredBills.length">
                <td colspan="7"><div class="empty-state"><Wallet :size="32" /><strong>Belum ada tagihan pengadaan</strong><span>Buat Pengadaan Barang terlebih dahulu agar pembayaran terlacak.</span></div></td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationBar v-model:page="billsPage" :total-items="filteredBills.length" />
      </template>

      <template v-else>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Tanggal</th><th>Pengadaan</th><th>Supplier</th><th>Jenis</th><th>Metode</th><th>Nominal</th><th>Referensi</th><th>Aksi</th></tr></thead>
            <tbody>
              <tr v-for="pay in pagedPayments" :key="pay.id">
                <td>{{ formatDate(pay.paid_at) }}</td>
                <td><strong>{{ pay.procurements?.procurement_no || '-' }}</strong></td>
                <td>{{ pay.procurements?.suppliers?.name || '-' }}</td>
                <td><span class="tag-pill">{{ payLabel(pay.payment_type) }}</span></td>
                <td>{{ pay.payment_method === 'transfer' ? 'Transfer' : 'Tunai' }}</td>
                <td><strong>{{ formatCurrency(pay.amount) }}</strong></td>
                <td>{{ pay.reference_no || pay.notes || '-' }}</td>
                <td><button class="icon-button" title="Edit pembayaran" @click="openEditPay(pay)"><Edit3 :size="15" /></button></td>
              </tr>
              <tr v-if="!payments.length"><td colspan="8"><div class="empty-state compact">Belum ada riwayat pembayaran.</div></td></tr>
            </tbody>
          </table>
        </div>
        <PaginationBar v-model:page="historyPage" :total-items="payments.length" />
      </template>
    </section>

    <PaymentModal :open="showModal" :procurements="procurements" :initial-procurement-id="selectedProcId" :editing-payment="editingPay" @close="showModal = false" @saved="load" />
  </div>
</template>
