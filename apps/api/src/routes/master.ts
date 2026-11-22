import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import {
  categorySchema,
  companySettingsSchema,
  departmentSchema,
  employeeSchema,
  funderSchema,
  itemSchema,
  officerSchema,
  supplierSchema,
} from '@inventaris/contracts'
import type { AppEnv } from '../types'

const COMPANY_SETTINGS_KEY = '_system/company-settings.json'
const defaultCompany = {
  name: 'PT Ria Industri',
  tagline: 'Divisi K3 & Gudang APD',
  logoKey: null as string | null,
}

async function readCompanySettings(bucket: R2Bucket) {
  try {
    const obj = await bucket.get(COMPANY_SETTINGS_KEY)
    if (!obj) return { ...defaultCompany }
    const parsed = JSON.parse(await obj.text())
    return {
      name: typeof parsed.name === 'string' && parsed.name.trim() ? parsed.name.trim() : defaultCompany.name,
      tagline: typeof parsed.tagline === 'string' && parsed.tagline.trim() ? parsed.tagline.trim() : defaultCompany.tagline,
      logoKey: typeof parsed.logoKey === 'string' && parsed.logoKey.trim() ? parsed.logoKey : null,
    }
  } catch {
    return { ...defaultCompany }
  }
}

export const masterRoutes = new Hono<AppEnv>()

masterRoutes.get('/summary', async (c) => {
  const [summary, company] = await Promise.all([
    c.get('service').getMasterSummary(),
    readCompanySettings(c.env.ATTACHMENTS),
  ])
  return c.json({ data: { ...summary, company }, mode: c.get('mode') })
})

masterRoutes.get('/company', async (c) => {
  const data = await readCompanySettings(c.env.ATTACHMENTS)
  return c.json({ data })
})

masterRoutes.put('/company', zValidator('json', companySettingsSchema), async (c) => {
  const input = c.req.valid('json')
  const payload = {
    name: input.name.trim(),
    tagline: input.tagline?.trim() || defaultCompany.tagline,
    logoKey: input.logoKey || null,
  }
  await c.env.ATTACHMENTS.put(COMPANY_SETTINGS_KEY, JSON.stringify(payload), {
    httpMetadata: { contentType: 'application/json' },
  })
  return c.json({ data: payload, message: 'Identitas & logo perusahaan berhasil disimpan' })
})

masterRoutes.post('/categories', zValidator('json', categorySchema), async (c) => {
  const data = await c.get('service').saveCategory(null, c.req.valid('json'))
  return c.json({ data, message: 'Kategori berhasil ditambahkan' }, 201)
})

masterRoutes.put('/categories/:id', zValidator('json', categorySchema), async (c) => {
  const data = await c.get('service').saveCategory(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Kategori berhasil diperbarui' })
})

masterRoutes.delete('/categories/:id', async (c) => {
  await c.get('service').deleteCategory(c.req.param('id'))
  return c.json({ message: 'Kategori berhasil dihapus' })
})

masterRoutes.post('/departments', zValidator('json', departmentSchema), async (c) => {
  const data = await c.get('service').saveDepartment(null, c.req.valid('json'))
  return c.json({ data, message: 'Departemen berhasil ditambahkan' }, 201)
})

masterRoutes.put('/departments/:id', zValidator('json', departmentSchema), async (c) => {
  const data = await c.get('service').saveDepartment(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Departemen berhasil diperbarui' })
})

masterRoutes.delete('/departments/:id', async (c) => {
  await c.get('service').deleteDepartment(c.req.param('id'))
  return c.json({ message: 'Departemen berhasil dihapus' })
})

masterRoutes.post('/suppliers', zValidator('json', supplierSchema), async (c) => {
  const data = await c.get('service').saveSupplier(null, c.req.valid('json'))
  return c.json({ data, message: 'Vendor berhasil ditambahkan' }, 201)
})

masterRoutes.put('/suppliers/:id', zValidator('json', supplierSchema), async (c) => {
  const data = await c.get('service').saveSupplier(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Vendor berhasil diperbarui' })
})

masterRoutes.delete('/suppliers/:id', async (c) => {
  await c.get('service').deleteSupplier(c.req.param('id'))
  return c.json({ message: 'Vendor berhasil dihapus' })
})

masterRoutes.post('/funders', zValidator('json', funderSchema), async (c) => {
  const data = await c.get('service').saveFunder(null, c.req.valid('json'))
  return c.json({ data, message: 'Pihak penalang berhasil ditambahkan' }, 201)
})

masterRoutes.put('/funders/:id', zValidator('json', funderSchema), async (c) => {
  const data = await c.get('service').saveFunder(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Pihak penalang berhasil diperbarui' })
})

masterRoutes.delete('/funders/:id', async (c) => {
  await c.get('service').deleteFunder(c.req.param('id'))
  return c.json({ message: 'Pihak penalang berhasil dihapus' })
})

masterRoutes.post('/officers', zValidator('json', officerSchema), async (c) => {
  const data = await c.get('service').saveOfficer(null, c.req.valid('json'))
  return c.json({ data, message: 'Petugas sistem berhasil ditambahkan' }, 201)
})

masterRoutes.put('/officers/:id', zValidator('json', officerSchema), async (c) => {
  const data = await c.get('service').saveOfficer(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Petugas sistem berhasil diperbarui' })
})

masterRoutes.delete('/officers/:id', async (c) => {
  await c.get('service').deleteOfficer(c.req.param('id'))
  return c.json({ message: 'Petugas sistem berhasil dihapus' })
})

masterRoutes.post('/employees', zValidator('json', employeeSchema), async (c) => {
  const data = await c.get('service').saveEmployee(null, c.req.valid('json'))
  return c.json({ data, message: 'Karyawan berhasil ditambahkan' }, 201)
})

masterRoutes.put('/employees/:id', zValidator('json', employeeSchema), async (c) => {
  const data = await c.get('service').saveEmployee(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Karyawan berhasil diperbarui' })
})

masterRoutes.delete('/employees/:id', async (c) => {
  await c.get('service').deleteEmployee(c.req.param('id'))
  return c.json({ message: 'Karyawan berhasil dihapus' })
})

masterRoutes.post('/items', zValidator('json', itemSchema), async (c) => {
  const data = await c.get('service').saveItem(null, c.req.valid('json'))
  return c.json({ data, message: 'Barang dan varian berhasil ditambahkan' }, 201)
})

masterRoutes.put('/items/:id', zValidator('json', itemSchema), async (c) => {
  const data = await c.get('service').saveItem(c.req.param('id'), c.req.valid('json'))
  return c.json({ data, message: 'Barang berhasil diperbarui' })
})

masterRoutes.delete('/items/:id', async (c) => {
  await c.get('service').deleteItem(c.req.param('id'))
  return c.json({ message: 'Barang berhasil dihapus' })
})
