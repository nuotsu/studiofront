'use cache'

import { cacheLife } from 'next/cache'

export async function getGithubStarCount(repo: string): Promise<number | null> {
	cacheLife('hours')

	try {
		const res = await fetch(`https://api.github.com/repos/${repo}`, {
			headers: { Accept: 'application/vnd.github+json' },
		})
		if (!res.ok) return null

		const data = (await res.json()) as { stargazers_count?: number }

		return typeof data.stargazers_count === 'number'
			? data.stargazers_count
			: null
	} catch {
		return null
	}
}
