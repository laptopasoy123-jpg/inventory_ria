# Inventaris APD

Monorepo sistem inventaris APD dan perlengkapan kerja.

## Menjalankan lokal

1. Salin `.env.example` menjadi `apps/web/.env` dan `apps/api/.dev.vars` sesuai bagiannya.
2. Jalankan migrasi pada `supabase/migrations` ke project Supabase.
3. Instal dependensi: `npm install`.
4. Jalankan frontend dan API: `npm run dev`.

- Web: http://localhost:8080
- API: http://localhost:8181

Wrangler otomatis menyimpan binding R2 secara lokal saat `wrangler dev`, sehingga
upload dapat diuji tanpa bucket production. Untuk production, buat bucket
`inventaris-apd` atau ubah nama bucket di `apps/api/wrangler.toml`.

## Struktur

- `apps/web` — Vue 3, Pinia, Vue Router, TypeScript, native CSS.
- `apps/api` — Cloudflare Worker berbasis Hono.
- `packages/contracts` — schema Zod dan tipe bersama.
- `supabase/migrations` — schema PostgreSQL, fungsi transaksi, dan RLS.

Mutasi stok hanya dilakukan melalui fungsi database agar penerimaan, pengeluaran,
pengembalian, reimbursement, dan opname tetap atomik serta dapat diaudit.

## Hak akses

- `officer` — pembelian/penerimaan, barang keluar, pengembalian, reimbursement.
- `inspector` — pemeriksaan pengembalian dan finalisasi stok opname.
- `admin` — seluruh akses dan pengelolaan master data/peran.

Pengguna baru mendapat peran `officer`. Administrator dapat mengubah kolom
`profiles.role` melalui Supabase SQL Editor atau panel admin yang dikembangkan
di atas API.

## Deployment

- Web: build `npm run build -w @inventaris/web`, lalu deploy `apps/web/dist` ke Cloudflare Pages.
- API: isi secret dengan `wrangler secret put`, lalu jalankan `npm run deploy -w @inventaris/api`.
- Supabase: jalankan migrasi sesuai urutan nama file sebelum Worker menerima trafik.

Secret `SUPABASE_SECRET_KEY` hanya berada di Worker dan tidak boleh memakai
prefix `VITE_`. Frontend hanya menerima URL Supabase dan publishable key.
"# inventory_ria" 
"# inventory_ria" 
