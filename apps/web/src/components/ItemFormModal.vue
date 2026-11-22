<script setup lang="ts">
import { reactive, ref, watch } from 'vue'
import { ImagePlus, Trash2 } from '@lucide/vue'
import BaseModal from './BaseModal.vue'
import ModernSelect from './ModernSelect.vue'
import { api, attachmentUrl, uploadAttachment } from '@/lib/api'
import { useToast } from '@/composables/useToast'
import { useMasterStore, type ItemMaster } from '@/stores/master'
import { units } from '@inventaris/contracts'

const unitOptions = units.map((u) => ({ value: u, label: u }))
const itemStatusOptions = [
  { value: true, label: 'Aktif', badge: 'Tersedia' },
  { value: false, label: 'Nonaktif', badge: 'Arsip' },
]

const props = defineProps<{
  open: boolean
  item?: ItemMaster | null
}>()

const emit = defineEmits<{ close: []; saved: [] }>()
const master = useMasterStore()
const toast = useToast()
const saving = ref(false)
const uploadingPhoto = ref(false)

const form = reactive({
  code: '',
  name: '',
  unit: 'pcs',
  minimumStock: 5,
  photoKey: '',
  specification: '',
  returnRequired: true,
  active: true,
})

watch(() => props.open, async (val) => {
  if (!val) return
  await master.refresh()
  if (props.item) {
    form.code = props.item.code
    form.name = props.item.name
    form.unit = props.item.unit
    form.minimumStock = Number(props.item.minimum_stock)
    form.photoKey = props.item.photo_key || ''
    form.specification = props.item.specification || ''
    form.returnRequired = props.item.return_required
    form.active = props.item.active
  } else {
    form.code = ''
    form.name = ''
    form.unit = 'pcs'
    form.minimumStock = 5
    form.photoKey = ''
    form.specification = ''
    form.returnRequired = true
    form.active = true
  }
})

async function handlePhotoUpload(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  if (!file.type.startsWith('image/')) {
    toast.error('Foto barang harus berformat gambar (JPG, PNG, atau WebP)')
    return
  }
  uploadingPhoto.value = true
  try {
    const uploaded = await uploadAttachment(file)
    form.photoKey = uploaded.key
    toast.success(`Foto barang "${uploaded.name}" berhasil diunggah`)
  } catch (err) {
    toast.error(err instanceof Error ? err.message : 'Gagal mengunggah foto barang')
  } finally {
    uploadingPhoto.value = false
    input.value = ''
  }
}

async function submit() {
  const existingSizes = props.item?.item_variants?.map((v) => v.size).filter(Boolean)
  const sizes = existingSizes?.length ? existingSizes : ['-']
  saving.value = true
  try {
    const path = props.item ? `/api/master/items/${props.item.id}` : '/api/master/items'
    const method = props.item ? 'PUT' : 'POST'
    await api(path, {
      method,
      body: JSON.stringify({
        code: form.code,
        name: form.name,
        categoryId: null,
        unit: form.unit,
        minimumStock: Number(form.minimumStock),
        photoKey: form.photoKey || null,
        specification: form.specification || null,
        returnRequired: form.returnRequired,
        active: form.active,
        sizes,
      }),
    })
    await master.refresh(true)
    toast.success(props.item ? 'Barang berhasil diperbarui' : 'Barang APD berhasil ditambahkan')
    emit('saved')
    emit('close')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Gagal menyimpan barang')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal
    :open="open"
    :title="item ? 'Edit Master Barang' : 'Tambah Master Barang APD'"
    eyebrow="Pengaturan Barang"
    subtitle="Atur kode, nama barang, foto, satuan, dan batas minimum stok."
    size="md"
    @close="emit('close')"
  >
    <form id="item-form" class="modal-form" @submit.prevent="submit">
      <div class="photo-upload-card">
        <div class="photo-preview-box">
          <img v-if="form.photoKey" :src="attachmentUrl(form.photoKey)" alt="Preview foto barang" />
          <ImagePlus v-else :size="24" />
        </div>
        <div class="photo-upload-meta">
          <strong>Foto Barang APD (Opsional)</strong>
          <small>Unggah gambar produk (mis. Full Body Harness, Helm Safety, Sepatu) berformat JPG/PNG/WebP agar tampil di tabel & form.</small>
          <div class="photo-upload-actions">
            <label class="secondary-button xs" style="cursor:pointer;">
              <ImagePlus :size="14" /> {{ uploadingPhoto ? 'Mengunggah...' : (form.photoKey ? 'Ganti Foto' : 'Unggah Foto') }}
              <input type="file" accept=".jpg,.jpeg,.png,.webp" hidden @change="handlePhotoUpload" />
            </label>
            <button v-if="form.photoKey" type="button" class="icon-button danger" title="Hapus foto" @click="form.photoKey = ''">
              <Trash2 :size="14" />
            </button>
          </div>
        </div>
      </div>

      <div class="form-grid-2">
        <label class="field">
          <span>Kode Barang *</span>
          <input v-model="form.code" required placeholder="Contoh: HLM-02" />
        </label>
        <label class="field">
          <span>Nama Barang *</span>
          <input v-model="form.name" required placeholder="Contoh: Full Body Harness Double Lanyard" />
        </label>
      </div>

      <div class="form-grid-3">
        <label class="field">
          <span>Satuan *</span>
          <ModernSelect v-model="form.unit" :options="unitOptions" required :searchable="false" />
        </label>
        <label class="field">
          <span>Minimum Stok</span>
          <input v-model.number="form.minimumStock" type="number" min="0" step="1" required />
        </label>
        <label class="field">
          <span>Status</span>
          <ModernSelect v-model="form.active" :options="itemStatusOptions" :searchable="false" />
        </label>
      </div>

      <label class="field">
        <span>Spesifikasi / Catatan Teknis</span>
        <textarea v-model="form.specification" rows="2" placeholder="Standar SNI/ANSI, material, warna, dll." />
      </label>

      <label class="checkbox-card">
        <input v-model="form.returnRequired" type="checkbox" />
        <div>
          <strong>Wajib Dikembalikan (APD Inventaris)</strong>
          <small>Jika dicentang, pengeluaran ke karyawan tercatat sebagai tanggungan yang harus dikembalikan.</small>
        </div>
      </label>
    </form>

    <template #footer>
      <button type="button" class="secondary-button" @click="emit('close')">Batal</button>
      <button type="submit" form="item-form" class="primary-button" :disabled="saving || uploadingPhoto">
        {{ saving ? 'Menyimpan...' : (item ? 'Simpan Perubahan' : 'Simpan Barang') }}
      </button>
    </template>
  </BaseModal>
</template>
