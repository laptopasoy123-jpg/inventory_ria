<script setup lang="ts">
import { ArrowUpRight } from '@lucide/vue'

defineProps<{
  label: string
  value: string | number
  hint: string
  tone?: 'teal' | 'blue' | 'amber' | 'red' | 'violet'
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  icon: any
  flaticonIcon?: string
  clickable?: boolean
}>()

defineEmits<{ click: [] }>()
</script>

<template>
  <article
    class="stat-card modern-hover-card"
    :class="{ clickable }"
    :role="clickable ? 'button' : undefined"
    :tabindex="clickable ? 0 : undefined"
    @click="clickable && $emit('click')"
    @keydown.enter.prevent="clickable && $emit('click')"
  >
    <div class="stat-top">
      <span class="stat-icon unified">
        <img v-if="flaticonIcon" :src="flaticonIcon" :alt="label" class="flaticon-badge-img" loading="lazy" />
        <component :is="icon" v-else :size="20" />
      </span>
      <span v-if="clickable" class="stat-link-arrow"><ArrowUpRight :size="14" /></span>
      <span v-else class="stat-dot unified" />
    </div>
    <p>{{ label }}</p>
    <strong>{{ value }}</strong>
    <small>{{ hint }}</small>
  </article>
</template>
