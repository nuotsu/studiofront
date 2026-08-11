// File-level `use cache` so this stays a server reference. `@/ui/sanity-link` is
// rendered from both server and client trees, so its `download_macos` branch —
// and this module with it — lands in the client graph.
'use cache'

import { cacheLife } from 'next/cache'
import { MACOS_RELEASES_API } from './download-macos'

export async function getLatestMacosRelease(): Promise<{ version: string }> {
	cacheLife('hours')

	try {
		const res = await fetch(MACOS_RELEASES_API, {
			headers: { Accept: 'application/vnd.github+json' },
		})
		if (!res.ok) return { version: 'unknown' }

		const data = (await res.json()) as { tag_name?: string }
		return { version: data.tag_name || 'unknown' }
	} catch {
		return { version: 'unknown' }
	}
}
