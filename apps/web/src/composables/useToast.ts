import { ref } from 'vue'

export interface ToastItem {
  id: number
  type: 'success' | 'error' | 'info'
  title: string
  message: string
  duration: number
}

const toasts = ref<ToastItem[]>([])
let nextId = 1

function deriveTitle(message: string, type: ToastItem['type'], explicit?: string) {
  if (explicit) return explicit
  if (type === 'error') return 'Terjadi Kendala'
  if (type === 'info') return 'Informasi Sistem'
  const lower = message.toLowerCase()
  if (/dihapus|hapus/.test(lower)) return 'Data Berhasil Dihapus'
  if (/diperbarui|ubah|perubahan/.test(lower)) return 'Perubahan Tersimpan'
  if (/diunggah|unggah|foto|logo|bukti/.test(lower)) return 'Berkas Berhasil Diunggah'
  if (/unduh|pdf|csv/.test(lower)) return 'Ekspor Dokumen Selesai'
  if (/dipindahkan|kondisi/.test(lower)) return 'Status Kondisi Diperbarui'
  return 'Data Berhasil Disimpan'
}

export function useToast() {
  function push(message: string, type: ToastItem['type'] = 'info', duration = 4500, title?: string) {
    const id = nextId++
    if (toasts.value.length >= 4) {
      toasts.value.shift()
    }
    toasts.value.push({
      id,
      type,
      title: deriveTitle(message, type, title),
      message,
      duration,
    })
    window.setTimeout(() => {
      dismiss(id)
    }, duration)
  }

  function dismiss(id: number) {
    toasts.value = toasts.value.filter((t) => t.id !== id)
  }

  return {
    toasts,
    dismiss,
    success: (msg: string, title?: string) => push(msg, 'success', 4600, title),
    error: (msg: string, title?: string) => push(msg, 'error', 5600, title),
    info: (msg: string, title?: string) => push(msg, 'info', 4200, title),
  }
}
