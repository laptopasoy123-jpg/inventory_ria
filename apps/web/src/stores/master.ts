import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { api } from '@/lib/api'

export interface Category { id: string; code: string; name: string }
export interface Department { id: string; code: string; name: string; active: boolean }
export interface Supplier { id: string; code: string; name: string; vendor_type?: 'supplier' | 'online_shop'; contact_name: string | null; phone: string | null; address: string | null; active: boolean }
export interface Funder { id: string; name: string; phone: string | null; notes: string | null; active: boolean }
export interface Officer { id: string; name: string; role_label: string; active: boolean }
export interface Employee { id: string; nik: string; name: string; position: string; department_id: string; contract_status: string; departments?: { name: string; code?: string } | null }
export interface CompanySettings {
  name: string
  tagline: string
  logoKey: string | null
}
export interface ItemMaster {
  id: string; code: string; name: string; category_id?: string | null; specification: string | null; unit: string;
  minimum_stock: number; photo_key?: string | null; return_required: boolean; active: boolean;
  categories?: { name: string; code: string } | null;
  item_variants?: Array<{ id: string; size: string; active: boolean }>
}
export interface VariantStock {
  variant_id: string; item_id: string; code: string; name: string; category_id?: string; category_name: string;
  specification: string | null; size: string; unit: string; minimum_stock: number; photo_key?: string | null; return_required: boolean;
  stock_new: number; stock_used_good: number; stock_quarantine: number; stock_damaged: number;
  total_available: number; stock_status: 'safe' | 'low' | 'out'
}

const CACHE_TTL_MS = 20_000

export const useMasterStore = defineStore('master', () => {
  const loaded = ref(false)
  const loading = ref(false)
  const mode = ref<'supabase' | 'local'>('local')
  const lastFetchedAt = ref(0)
  const company = ref<CompanySettings>({
    name: 'PT Ria Industri',
    tagline: 'Divisi K3 & Gudang APD',
    logoKey: null,
  })
  const categories = ref<Category[]>([])
  const departments = ref<Department[]>([])
  const items = ref<ItemMaster[]>([])
  const variants = ref<VariantStock[]>([])
  const employees = ref<Employee[]>([])
  const suppliers = ref<Supplier[]>([])
  const funders = ref<Funder[]>([])
  const officers = ref<Officer[]>([])

  let inFlight: Promise<void> | null = null

  const companyInitials = computed(() => {
    const clean = company.value.name
      .replace(/^(pt|cv|ud|yayasan)\s+/i, '')
      .trim()
    const words = clean.split(/\s+/).filter(Boolean)
    if (words.length >= 2) {
      return `${words[0]?.[0] || ''}${words[1]?.[0] || ''}`.toUpperCase()
    }
    return (clean.slice(0, 3) || 'INV').toUpperCase()
  })

  function applyCompany(next?: Partial<CompanySettings> | null) {
    if (!next) return
    company.value = {
      name: next.name?.trim() || 'PT Ria Industri',
      tagline: next.tagline?.trim() || 'Divisi K3 & Gudang APD',
      logoKey: next.logoKey ?? null,
    }
    if (typeof document !== 'undefined') {
      document.title = `INVENTRA — ${company.value.name}`
    }
  }

  async function refresh(force = false) {
    const fresh = loaded.value && Date.now() - lastFetchedAt.value < CACHE_TTL_MS
    if (fresh && !force) return
    if (inFlight && !force) return inFlight

    const run = async () => {
      loading.value = true
      try {
        const res = await api<{
          mode?: 'supabase' | 'local'
          data: {
            company?: CompanySettings
            categories: Category[]
            departments: Department[]
            items: ItemMaster[]
            variants: VariantStock[]
            employees: Employee[]
            suppliers: Supplier[]
            funders: Funder[]
            officers?: Officer[]
          }
        }>('/api/master/summary')
        if (res.mode) mode.value = res.mode
        if (res.data.company) applyCompany(res.data.company)
        categories.value = res.data.categories
        departments.value = res.data.departments
        items.value = res.data.items
        variants.value = res.data.variants
        employees.value = res.data.employees
        suppliers.value = res.data.suppliers
        funders.value = res.data.funders
        officers.value = res.data.officers ?? []
        loaded.value = true
        lastFetchedAt.value = Date.now()
      } finally {
        loading.value = false
        inFlight = null
      }
    }

    inFlight = run()
    return inFlight
  }

  async function saveCompany(input: { name: string; tagline?: string | null; logoKey?: string | null }) {
    const res = await api<{ data: CompanySettings; message?: string }>('/api/master/company', {
      method: 'PUT',
      body: JSON.stringify(input),
    })
    applyCompany(res.data)
    return res.data
  }

  return {
    loaded,
    loading,
    mode,
    company,
    companyInitials,
    categories,
    departments,
    items,
    variants,
    employees,
    suppliers,
    funders,
    officers,
    refresh,
    saveCompany,
  }
})
