<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { ArrowUpRight, History, Search } from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import PaginationBar from '@/components/PaginationBar.vue'

export type HistoryCell =
  | string
  | number
  | null
  | undefined
  | {
      text: string
      sub?: string
      pill?: 'safe' | 'low' | 'out' | 'amber' | 'neutral' | 'plus' | 'minus'
      strong?: boolean
    }

export interface HistoryColumn {
  key: string
  label: string
  align?: 'left' | 'right'
}

const props = defineProps<{
  open: boolean
  title: string
  subtitle?: string
  loading?: boolean
  columns: HistoryColumn[]
  rows: Array<Record<string, HistoryCell>>
  emptyText?: string
  actionLabel?: string
}>()

defineEmits<{
  close: []
  action: []
}>()

const search = ref('')
const page = ref(1)
const pageSize = 15

watch(() => [props.open, props.title], () => {
  search.value = ''
  page.value = 1
})

function cellText(val: HistoryCell): string {
  if (val === null || val === undefined) return '—'
  if (typeof val === 'object') return `${val.text} ${val.sub || ''}`.trim()
  return String(val)
}

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return props.rows
  return props.rows.filter((row) =>
    props.columns.some((col) => cellText(row[col.key]).toLowerCase().includes(q)),
  )
})

const pagedRows = computed(() =>
  filteredRows.value.slice((page.value - 1) * pageSize, page.value * pageSize),
)

watch(search, () => { page.value = 1 })
</script>

<template>
  <BaseModal :open="open" :title="title" :subtitle="subtitle" size="xl" @close="$emit('close')">
    <div class="history-modal-toolbar">
      <label class="search-field">
        <Search :size="15" />
        <input v-model="search" placeholder="Cari data di dalam riwayat ini..." />
      </label>
      <div class="history-modal-meta">
        <span class="tag-pill">{{ filteredRows.length }} data</span>
        <button v-if="actionLabel" type="button" class="secondary-button small" @click="$emit('action')">
          {{ actionLabel }} <ArrowUpRight :size="14" />
        </button>
      </div>
    </div>

    <div v-if="loading" class="loading-row">Memuat riwayat data...</div>

    <div v-else-if="!filteredRows.length" class="empty-state compact">
      <History :size="26" />
      <strong>{{ emptyText || 'Belum ada data untuk kategori ini.' }}</strong>
    </div>

    <template v-else>
      <div class="table-wrap" style="max-height: 56vh; overflow-y: auto;">
        <table>
          <thead>
            <tr>
              <th v-for="col in columns" :key="col.key" :style="col.align === 'right' ? 'text-align:right' : undefined">
                {{ col.label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, idx) in pagedRows" :key="idx">
              <td v-for="col in columns" :key="col.key" :style="col.align === 'right' ? 'text-align:right' : undefined">
                <template v-if="row[col.key] && typeof row[col.key] === 'object'">
                  <template v-if="(row[col.key] as any).pill === 'plus' || (row[col.key] as any).pill === 'minus'">
                    <span class="delta-pill" :class="(row[col.key] as any).pill">{{ (row[col.key] as any).text }}</span>
                  </template>
                  <template v-else-if="(row[col.key] as any).pill">
                    <span class="status-pill" :class="(row[col.key] as any).pill">{{ (row[col.key] as any).text }}</span>
                  </template>
                  <strong v-else-if="(row[col.key] as any).strong">{{ (row[col.key] as any).text }}</strong>
                  <span v-else>{{ (row[col.key] as any).text }}</span>
                  <small v-if="(row[col.key] as any).sub" class="table-sub">{{ (row[col.key] as any).sub }}</small>
                </template>
                <template v-else>
                  {{ row[col.key] ?? '—' }}
                </template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationBar v-model:page="page" :total-items="filteredRows.length" :page-size="pageSize" />
    </template>
  </BaseModal>
</template>
