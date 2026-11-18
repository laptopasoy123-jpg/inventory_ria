import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import type { AppEnv } from '../types'

const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
export const uploadRoutes = new Hono<AppEnv>()

uploadRoutes.post('/', async (c) => {
  const body = await c.req.parseBody()
  const file = body.file
  if (!(file instanceof File)) throw new HTTPException(400, { message: 'File wajib diisi' })
  if (!allowedTypes.has(file.type)) throw new HTTPException(400, { message: 'Format file harus JPG, PNG, WEBP, atau PDF' })
  if (file.size > 10 * 1024 * 1024) throw new HTTPException(400, { message: 'Ukuran file maksimal 10 MB' })
  const extension = file.name.split('.').pop()?.toLowerCase() || 'bin'
  const key = `${new Date().toISOString().slice(0, 10)}/${crypto.randomUUID()}.${extension}`
  await c.env.ATTACHMENTS.put(key, file.stream(), { httpMetadata: { contentType: file.type } })
  return c.json({ data: { key, name: file.name, contentType: file.type, size: file.size } }, 201)
})

uploadRoutes.get('/:key{.+}', async (c) => {
  const object = await c.env.ATTACHMENTS.get(c.req.param('key'))
  if (!object) throw new HTTPException(404, { message: 'Lampiran tidak ditemukan' })
  const headers = new Headers()
  object.writeHttpMetadata(headers)
  headers.set('etag', object.httpEtag)
  headers.set('Content-Disposition', 'inline')
  return new Response(object.body, { headers })
})
