export const apdIcons = {
  warehouse: '/icons/warehouse.webp',
  inventory: '/icons/inventory.webp',
  box: '/icons/box.webp',
  shield: '/icons/shield.webp',
  hardhat: '/icons/hardhat.webp',
  vest: '/icons/vest.webp',
  gloves: '/icons/gloves.webp',
  goggles: '/icons/goggles.webp',
  mask: '/icons/mask.webp',
  boots: '/icons/boots.webp',
  earplugs: '/icons/earplugs.webp',
  quarantine: '/icons/quarantine.webp',
  warning: '/icons/warning.webp',
} as const

export const flaticonAssets = apdIcons

const iconCache = new Map<string, string>()

/** Returns a matching local WebP icon path for an APD item name. */
export function itemFlaticonIcon(name?: string | null): string {
  const key = (name || '').toLowerCase()
  const cached = iconCache.get(key)
  if (cached) return cached
  let res: string = apdIcons.shield
  if (/helm|helmet|topi/.test(key)) res = apdIcons.hardhat
  else if (/rompi|vest|wearpack|baju|jaket/.test(key)) res = apdIcons.vest
  else if (/sarung|glove|hand/.test(key)) res = apdIcons.gloves
  else if (/sepatu|boot|safety toe/.test(key)) res = apdIcons.boots
  else if (/kacamata|goggle|face shield|visor/.test(key)) res = apdIcons.goggles
  else if (/mask|respirator|n95|cartridge/.test(key)) res = apdIcons.mask
  else if (/ear|telinga|sumbat/.test(key)) res = apdIcons.earplugs
  if (iconCache.size > 400) iconCache.clear()
  iconCache.set(key, res)
  return res
}
