<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { CalendarDays, Clock } from '@lucide/vue'

const clockDateFmt = new Intl.DateTimeFormat('id-ID', {
  weekday: 'long',
  day: '2-digit',
  month: 'long',
  year: 'numeric',
})
const clockTimeFmt = new Intl.DateTimeFormat('id-ID', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
})

const now = ref(new Date())
let timer: number | undefined

const formattedDate = computed(() => clockDateFmt.format(now.value))
const formattedTime = computed(() => clockTimeFmt.format(now.value).replace(/\./g, ':'))

onMounted(() => {
  timer = window.setInterval(() => {
    now.value = new Date()
  }, 15_000)
})

onUnmounted(() => {
  if (timer) window.clearInterval(timer)
})
</script>

<template>
  <div class="live-clock-pill" title="Waktu lokal sistem">
    <span class="clock-date"><CalendarDays :size="14" /> {{ formattedDate }}</span>
    <span class="clock-sep" />
    <span class="clock-time"><Clock :size="14" /> {{ formattedTime }} WIB</span>
  </div>
</template>
