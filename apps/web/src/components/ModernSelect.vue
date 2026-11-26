<script setup lang="ts">
import { computed, nextTick, onDeactivated, onUnmounted, ref, watch } from 'vue'
import { Check, ChevronDown, Search } from '@lucide/vue'

export interface SelectOption {
  value: string | number | boolean
  label: string
  sublabel?: string
  badge?: string
  icon?: string
  disabled?: boolean
}

const props = withDefaults(
  defineProps<{
    modelValue: string | number | boolean | null | undefined
    options: SelectOption[]
    placeholder?: string
    searchable?: boolean
    disabled?: boolean
    required?: boolean
    compact?: boolean
    searchPlaceholder?: string
  }>(),
  {
    placeholder: '-- Pilih opsi --',
    searchable: undefined,
    disabled: false,
    required: false,
    compact: false,
    searchPlaceholder: 'Cari opsi...',
  },
)

const emit = defineEmits<{
  'update:modelValue': [value: any]
  change: [value: any]
}>()

const triggerRef = ref<HTMLButtonElement | null>(null)
const panelRef = ref<HTMLDivElement | null>(null)
const searchInputRef = ref<HTMLInputElement | null>(null)
const isOpen = ref(false)
const query = ref('')
const menuStyle = ref<Record<string, string>>({})

const selectedOption = computed(() =>
  props.options.find((o) => o.value === props.modelValue) || null,
)

const showSearch = computed(() =>
  props.searchable !== undefined ? props.searchable : props.options.length >= 6,
)

const filteredOptions = computed(() => {
  if (!isOpen.value) return []
  const q = query.value.trim().toLowerCase()
  if (!q) return props.options
  return props.options.filter(
    (o) =>
      o.label.toLowerCase().includes(q) ||
      (o.sublabel && o.sublabel.toLowerCase().includes(q)) ||
      (o.badge && o.badge.toLowerCase().includes(q)),
  )
})

function updatePosition() {
  const trigger = triggerRef.value
  if (!trigger) return
  const rect = trigger.getBoundingClientRect()
  const vw = window.innerWidth
  const vh = window.innerHeight
  const spaceBelow = vh - rect.bottom - 12
  const spaceAbove = rect.top - 12
  const estHeight = Math.min(310, Math.max(120, filteredOptions.value.length * 42 + (showSearch.value ? 52 : 16)))
  const openUp = spaceBelow < estHeight && spaceAbove > spaceBelow
  const maxHeight = Math.max(140, Math.min(320, openUp ? spaceAbove : spaceBelow))
  const width = Math.min(vw - 20, Math.max(rect.width, 285))
  const left = Math.max(10, Math.min(rect.left, vw - width - 10))

  menuStyle.value = openUp
    ? {
        position: 'fixed',
        left: `${left}px`,
        bottom: `${vh - rect.top + 6}px`,
        width: `${width}px`,
        maxHeight: `${maxHeight}px`,
      }
    : {
        position: 'fixed',
        left: `${left}px`,
        top: `${rect.bottom + 6}px`,
        width: `${width}px`,
        maxHeight: `${maxHeight}px`,
      }
}

async function openMenu() {
  if (props.disabled) return
  query.value = ''
  isOpen.value = true
  await nextTick()
  updatePosition()
  if (showSearch.value) {
    searchInputRef.value?.focus()
  }
}

function closeMenu() {
  isOpen.value = false
}

function toggleMenu() {
  if (isOpen.value) closeMenu()
  else void openMenu()
}

function pickOption(opt: SelectOption) {
  if (opt.disabled) return
  emit('update:modelValue', opt.value)
  emit('change', opt.value)
  closeMenu()
}

function onDocClick(e: MouseEvent) {
  if (!isOpen.value) return
  const target = e.target as Node
  if (triggerRef.value?.contains(target) || panelRef.value?.contains(target)) return
  closeMenu()
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && isOpen.value) {
    closeMenu()
    triggerRef.value?.focus()
  }
}

let rafId = 0
let listenersBound = false

function onWindowReposition() {
  if (!isOpen.value || rafId) return
  rafId = window.requestAnimationFrame(() => {
    rafId = 0
    if (isOpen.value) updatePosition()
  })
}

function bindListeners() {
  if (listenersBound) return
  listenersBound = true
  document.addEventListener('mousedown', onDocClick)
  window.addEventListener('keydown', onKeydown)
  window.addEventListener('scroll', onWindowReposition, { capture: true, passive: true })
  window.addEventListener('resize', onWindowReposition, { passive: true })
}

function unbindListeners() {
  if (rafId) {
    window.cancelAnimationFrame(rafId)
    rafId = 0
  }
  if (!listenersBound) return
  listenersBound = false
  document.removeEventListener('mousedown', onDocClick)
  window.removeEventListener('keydown', onKeydown)
  window.removeEventListener('scroll', onWindowReposition, true)
  window.removeEventListener('resize', onWindowReposition)
}

watch(isOpen, (open) => {
  if (open) bindListeners()
  else unbindListeners()
})

watch(filteredOptions, () => {
  if (isOpen.value) void nextTick(updatePosition)
})

onDeactivated(() => {
  if (isOpen.value) closeMenu()
  unbindListeners()
})

onUnmounted(() => {
  unbindListeners()
})
</script>

<template>
  <div class="modern-select-root" :class="{ compact, disabled, open: isOpen }">
    <input
      v-if="required"
      class="modern-select-native-req"
      tabindex="-1"
      aria-hidden="true"
      required
      :value="modelValue === undefined || modelValue === null || modelValue === '' ? '' : String(modelValue)"
      @focus="triggerRef?.focus()"
    />
    <button
      ref="triggerRef"
      type="button"
      class="modern-select-trigger"
      :class="{ compact, open: isOpen, placeholder: !selectedOption }"
      :disabled="disabled"
      :aria-expanded="isOpen"
      @click="toggleMenu"
    >
      <img v-if="selectedOption?.icon" :src="selectedOption.icon" class="ms-trigger-icon" alt="" decoding="async" />
      <span class="ms-trigger-text">
        <span class="ms-label">{{ selectedOption ? selectedOption.label : placeholder }}</span>
        <span v-if="selectedOption?.badge" class="ms-trigger-badge">{{ selectedOption.badge }}</span>
      </span>
      <ChevronDown :size="15" class="ms-chevron" :class="{ rotated: isOpen }" />
    </button>

    <Teleport to="body">
      <Transition name="dropdown-pop">
        <div v-if="isOpen" ref="panelRef" class="modern-select-menu" :style="menuStyle">
          <div v-if="showSearch" class="ms-search-wrap">
            <Search :size="14" />
            <input
              ref="searchInputRef"
              v-model="query"
              type="text"
              :placeholder="searchPlaceholder"
              @keydown.stop
            />
          </div>
          <div class="ms-options-scroll">
            <button
              v-for="opt in filteredOptions"
              :key="String(opt.value)"
              type="button"
              class="ms-option"
              :class="{ active: opt.value === modelValue, disabled: opt.disabled }"
              :disabled="opt.disabled"
              @click="pickOption(opt)"
            >
              <img v-if="opt.icon" :src="opt.icon" class="ms-opt-icon" alt="" loading="lazy" decoding="async" />
              <div class="ms-opt-body">
                <div class="ms-opt-main">
                  <span>{{ opt.label }}</span>
                  <span v-if="opt.badge" class="ms-opt-badge">{{ opt.badge }}</span>
                </div>
                <small v-if="opt.sublabel">{{ opt.sublabel }}</small>
              </div>
              <Check v-if="opt.value === modelValue" :size="15" class="ms-opt-check" />
            </button>
            <div v-if="!filteredOptions.length" class="ms-empty">Tidak ada pilihan yang cocok.</div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
