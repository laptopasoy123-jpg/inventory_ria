<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  label: string
  value: string | number
  hint: string
  tone?: 'teal' | 'blue' | 'amber' | 'red' | 'violet'
  icon: Component
  flaticonIcon?: string
}>()
</script>

<template>
  <article class="stat-card modern-hover-card">
    <div class="stat-top">
      <span class="stat-icon" :class="tone || 'teal'">
        <img v-if="flaticonIcon" :src="flaticonIcon" :alt="label" class="flaticon-badge-img" loading="lazy" />
        <component :is="icon" v-else :size="20" />
      </span>
      <span class="stat-dot" :class="tone || 'teal'" />
    </div>
    <p>{{ label }}</p>
    <strong>{{ value }}</strong>
    <small>{{ hint }}</small>
  </article>
</template>
