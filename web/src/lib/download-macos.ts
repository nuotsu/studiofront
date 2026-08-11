// Isomorphic on purpose: `src/sanity/schemaTypes/objects/link.ts` imports these
// into the Studio bundle. The release lookup lives in `@/ui/download-macos-link`
// so `next/cache` stays out of the browser.

/** Always resolves to the latest GitHub release DMG via redirect. */
export const MACOS_DMG_URL =
	'https://github.com/nuotsu/studiofront/releases/latest/download/Studiofront.dmg'

export const MACOS_DMG_FILENAME = 'Studiofront.dmg'

export const MACOS_RELEASES_API =
	'https://api.github.com/repos/nuotsu/studiofront/releases/latest'
