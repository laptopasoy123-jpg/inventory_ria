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

/** Returns a matching local WebP icon path for an APD item name. */
export function itemFlaticonIcon(name?: string | null): string {
  const n = (name || '').toLowerCase()
  if (/helm|helmet|topi/.test(n)) return apdIcons.hardhat
  if (/rompi|vest|wearpack|baju|jaket/.test(n)) return apdIcons.vest
  if (/sarung|glove|hand/.test(n)) return apdIcons.gloves
  if (/sepatu|boot|safety toe/.test(n)) return apdIcons.boots
  if (/kacamata|goggle|face shield|visor/.test(n)) return apdIcons.goggles
  if (/mask|respirator|n95|cartridge/.test(n)) return apdIcons.mask
  if (/ear|telinga|sumbat/.test(n)) return apdIcons.earplugs
  return apdIcons.shield
}
