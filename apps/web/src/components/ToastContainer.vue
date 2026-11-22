<script setup lang="ts">
import { AlertCircle, ArrowUpRight, CheckCircle2, Info, Sparkles, X } from '@lucide/vue'
import { useToast } from '@/composables/useToast'

const { toasts, dismiss } = useToast()
const currentYear = new Date().getFullYear()
</script>

<template>
  <Teleport to="body">
    <div class="toast-stack" aria-live="polite">
      <TransitionGroup name="toast-pop">
        <div v-for="t in toasts" :key="t.id" class="toast-card" :class="t.type">
          <div class="toast-main">
            <div class="toast-icon-badge" :class="t.type">
              <CheckCircle2 v-if="t.type === 'success'" :size="20" />
              <AlertCircle v-else-if="t.type === 'error'" :size="20" />
              <Info v-else :size="20" />
            </div>
            <div class="toast-body">
              <div class="toast-head-row">
                <strong>{{ t.title }}</strong>
                <Sparkles v-if="t.type === 'success'" :size="13" class="toast-spark" />
              </div>
              <p>{{ t.message }}</p>
            </div>
            <button type="button" class="toast-close-btn" aria-label="Tutup notifikasi" @click="dismiss(t.id)">
              <X :size="15" />
            </button>
          </div>

          <div class="toast-brand-bar">
            <a
              href="https://daysheet.id"
              target="_blank"
              rel="noopener noreferrer"
              class="toast-daysheet-link"
              title="Kunjungi situs resmi DaySheet.id"
            >
              <img src="/daysheet-logo.png" alt="DaySheet.id" />
              <span>Copyright &copy; {{ currentYear }} by <strong>DaySheet.id</strong></span>
              <ArrowUpRight :size="12" />
            </a>
            <span class="toast-status-tag">{{ t.type === 'success' ? 'Tercatat' : t.type === 'error' ? 'Gagal' : 'Info' }}</span>
          </div>

          <div class="toast-progress-track">
            <div class="toast-progress-fill" :class="t.type" :style="{ animationDuration: `${t.duration}ms` }" />
          </div>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>
