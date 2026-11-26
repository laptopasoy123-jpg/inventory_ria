<script setup lang="ts">
import { computed, watch } from 'vue'
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
const safePage = computed(() => Math.min(Math.max(1, props.page), totalPages.value))
const startIdx = computed(() => (props.totalItems === 0 ? 0 : (safePage.value - 1) * props.pageSize + 1))
const endIdx = computed(() => Math.min(props.totalItems, safePage.value * props.pageSize))

watch(
  [() => props.totalItems, () => props.pageSize, () => props.page],
  () => {
    const maxPage = Math.max(1, Math.ceil(props.totalItems / props.pageSize))
    if (props.page > maxPage) {
      emit('update:page', maxPage)
    } else if (props.page < 1) {
      emit('update:page', 1)
    }
  },
  { immediate: true },
)

const visiblePages = computed(() => {
  const total = totalPages.value
  const cur = safePage.value
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
      <button type="button" class="secondary-button xs" :disabled="safePage <= 1" @click="emit('update:page', safePage - 1)">
        <ChevronLeft :size="14" /> Sebelumnya
      </button>
      <button
        v-for="p in visiblePages"
        :key="p"
        type="button"
        class="page-num-btn"
        :class="{ active: p === safePage }"
        @click="emit('update:page', p)"
      >
        {{ p }}
      </button>
      <button type="button" class="secondary-button xs" :disabled="safePage >= totalPages" @click="emit('update:page', safePage + 1)">
        Lanjut <ChevronRight :size="14" />
      </button>
    </div>
  </div>
</template>
