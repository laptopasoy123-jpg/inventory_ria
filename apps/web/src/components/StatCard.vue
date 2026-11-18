<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  label: string
  value: string | number
  hint: string
  tone?: 'teal' | 'blue' | 'amber' | 'red' | 'violet'
  icon: Component
}>()
</script>

<template>
  <article class="stat-card">
    <div class="stat-top"><span class="stat-icon" :class="tone || 'teal'"><component :is="icon" :size="20" /></span><span class="stat-more">•••</span></div>
    <p>{{ label }}</p><strong>{{ value }}</strong><small>{{ hint }}</small>
  </article>
</template>
