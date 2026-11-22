const baseUrl = import.meta.env.VITE_API_URL || (import.meta.env.DEV ? '' : 'http://localhost:8190')

/** Generates an RFC 4122 v4 UUID safely even outside HTTPS/localhost secure contexts. */
export function generateUuid(): string {
  const c = globalThis.crypto
  if (c && typeof c.randomUUID === 'function') return c.randomUUID()
  const bytes = new Uint8Array(16)
  if (c && typeof c.getRandomValues === 'function') {
    c.getRandomValues(bytes)
  } else {
    for (let i = 0; i < 16; i += 1) bytes[i] = Math.floor(Math.random() * 256)
  }
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0'))
  return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10, 16).join('')}`
}

export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message) }
}

const getCache = new Map<string, { ts: number; data: unknown }>()
const inFlightGets = new Map<string, Promise<unknown>>()
const GET_CACHE_TTL_MS = 30_000

const numberFmt = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 2 })
const currencyFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 })
const dateFmt = new Intl.DateTimeFormat('id-ID', { day: '2-digit', month: 'short', year: 'numeric' })

export function invalidateApiCache(prefix?: string) {
  if (!prefix) {
    getCache.clear()
    return
  }
  for (const key of getCache.keys()) {
    if (key.startsWith(prefix)) getCache.delete(key)
  }
}

export function prefetchApi(path: string) {
  void api(path).catch(() => {})
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method || 'GET').toUpperCase()
  const isGet = method === 'GET'

  if (isGet) {
    const cached = getCache.get(path)
    if (cached && Date.now() - cached.ts < GET_CACHE_TTL_MS) {
      return cached.data as T
    }
    const existing = inFlightGets.get(path)
    if (existing) return existing as Promise<T>
  } else {
    getCache.clear()
  }

  const run = async (): Promise<T> => {
    const headers = new Headers(init.headers)
    if (!(init.body instanceof FormData) && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json')
    }
    const response = await fetch(`${baseUrl}${path}`, { ...init, headers })
    const body = await response.json().catch(() => ({ message: 'Respons server tidak valid' }))
    if (!response.ok) throw new ApiError(body.message || 'Permintaan gagal', response.status)
    if (isGet) {
      getCache.set(path, { ts: Date.now(), data: body })
    }
    return body
  }

  if (isGet) {
    const p = run().finally(() => inFlightGets.delete(path))
    inFlightGets.set(path, p)
    return p
  }
  return run()
}

export async function uploadAttachment(file: File): Promise<{ key: string; name: string }> {
  const form = new FormData()
  form.append('file', file)
  const res = await api<{ data: { key: string; name: string } }>('/api/uploads', {
    method: 'POST',
    body: form,
  })
  return res.data
}

export const attachmentUrl = (key?: string | null) =>
  key ? `${baseUrl}/api/uploads/${encodeURIComponent(key).replace(/%2F/g, '/')}` : ''

export async function imageUrlToDataUrl(url: string): Promise<string | null> {
  if (!url) return null
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    const blob = await res.blob()
    return await new Promise((resolve) => {
      const reader = new FileReader()
      reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : null)
      reader.onerror = () => resolve(null)
      reader.readAsDataURL(blob)
    })
  } catch {
    return null
  }
}

export const formatNumber = (value: number | string) =>
  numberFmt.format(Number(value || 0))

/** Displays clean item name, appending size only when a meaningful size variant exists. */
export const variantLabel = (item: { name?: string | null; size?: string | null }) => {
  const name = (item.name || '').trim()
  const size = (item.size || '').trim()
  return size && size !== '-' && size.toLowerCase() !== 'all size' ? `${name} (${size})` : name
}

export const formatCurrency = (value: number | string) =>
  currencyFmt.format(Number(value || 0))

export const formatDate = (value?: string | null) => {
  if (!value) return '—'
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return value
  return dateFmt.format(d)
}

export const conditionLabel = (condition: string) => {
  const map: Record<string, string> = {
    new: 'Baru',
    used_good: 'Bekas Layak',
    quarantine: 'Karantina',
    damaged: 'Rusak',
    maintenance: 'Karantina / Perawatan',
    lost: 'Hilang',
  }
  return map[condition] || condition
}

export function downloadCsv(filename: string, headers: string[], rows: Array<Array<string | number | null | undefined>>) {
  const csv = [headers, ...rows]
    .map((line) => line.map((val) => `"${String(val ?? '').replaceAll('"', '""')}"`).join(','))
    .join('\n')
  const url = URL.createObjectURL(new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}
