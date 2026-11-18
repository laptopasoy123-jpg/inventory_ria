const baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:8181'

export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message) }
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  if (!(init.body instanceof FormData)) headers.set('Content-Type', 'application/json')
  const response = await fetch(`${baseUrl}${path}`, { ...init, headers })
  const body = await response.json().catch(() => ({ message: 'Respons server tidak valid' }))
  if (!response.ok) throw new ApiError(body.message || 'Permintaan gagal', response.status)
  return body
}

export const formatNumber = (value: number | string) => new Intl.NumberFormat('id-ID', { maximumFractionDigits: 2 }).format(Number(value))
export const formatCurrency = (value: number | string) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value))
