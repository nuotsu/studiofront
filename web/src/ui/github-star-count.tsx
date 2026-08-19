import type { ComponentProps } from 'react'
import { VscGithubInverted, VscStarFull } from 'react-icons/vsc'
import { getGithubStarCount } from '@/lib/get-github-star-count'
import { cn } from '@/lib/utils'

const REPO = 'nuotsu/studiofront'

export default async function ({ className }: ComponentProps<'div'>) {
	const count = await getGithubStarCount(REPO)

	if (count == null) return null

	return (
		<a
			href={`https://github.com/${REPO}`}
			className={cn('anim-fade-to-r flex items-center gap-1', className)}
		>
			<VscGithubInverted />
			<VscStarFull />
			{count.toLocaleString()}
		</a>
	)
}
