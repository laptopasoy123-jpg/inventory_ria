<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, ChevronRight } from '@lucide/vue'

const props = withDefaults(defineProps<{
  page: number
  totalItems: number
  pageSize?: number
}>(), {
  pageSize: 10,
})

const emit = defineEmits<{ 'update:page': [value: number] }>()

const totalPages = computed(() => Math.max(1, Math.ceil(props.totalItems / props.pageSize)))
const startIdx = computed(() => (props.totalItems === 0 ? 0 : (props.page - 1) * props.pageSize + 1))
const endIdx = computed(() => Math.min(props.totalItems, props.page * props.pageSize))

const visiblePages = computed(() => {
  const total = totalPages.value
  const cur = props.page
  const pages: number[] = []
  const start = Math.max(1, cur - 2)
  const end = Math.min(total, start + 4)
  for (let p = Math.max(1, end - 4); p <= end; p++) pages.push(p)
  return pages
})
</script>

<template>
  <div v-if="totalItems > 0" class="pagination-bar">
    <small class="pagination-info">
      Menampilkan <strong>{{ startIdx }}–{{ endIdx }}</strong> dari <strong>{{ totalItems }}</strong> data ({{ pageSize }} per halaman)
    </small>
    <div v-if="totalPages > 1" class="pagination-controls">
      <button type="button" class="secondary-button xs" :disabled="page <= 1" @click="emit('update:page', page - 1)">
        <ChevronLeft :size="14" /> Sebelumnya
      </button>
      <button
        v-for="p in visiblePages"
        :key="p"
        type="button"
        class="page-num-btn"
        :class="{ active: p === page }"
        @click="emit('update:page', p)"
      >
        {{ p }}
      </button>
      <button type="button" class="secondary-button xs" :disabled="page >= totalPages" @click="emit('update:page', page + 1)">
        Lanjut <ChevronRight :size="14" />
      </button>
    </div>
  </div>
</template>
