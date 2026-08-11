import { groq } from 'next-sanity'
import { ImageResponse } from 'next/og'
import { ROUTES } from '@/lib/env'
import { cn } from '@/lib/utils'
import {
	getDynamicFetchOptions,
	sanityFetch,
	type DynamicFetchOptions,
} from '@/sanity/lib/live'
import { getSite } from '@/sanity/lib/queries'
import type { OG_QUERY_RESULT } from '@/sanity/types'

const { hostname } = new URL(process.env.NEXT_PUBLIC_BASE_URL!)
const blogDir = `${ROUTES.blog}/`

const OG_QUERY = groq`*[_type == $type && metadata.slug.current == $slug][0]{
	'title': coalesce(metadata.title, title),
}`

export async function GET(request: Request) {
	const { searchParams } = new URL(request.url)
	const slug = searchParams.get('slug') ?? 'index'
	const invert = ['1', 'true'].includes(searchParams.get('invert')!)

	const type = slug.startsWith(blogDir) ? 'blog.post' : 'page'

	const { perspective } = await getDynamicFetchOptions({
		allowDevPreview: false,
	})

	const [page, site] = await Promise.all([
		getPage({
			type,
			slug: type === 'blog.post' ? slug.replace(blogDir, '') : slug,
			perspective,
		}),
		getSite({ perspective, stega: false }),
	])

	const [h1 = '', h2 = ''] =
		(page?.title || site?.title)?.split(/(?:\s*[|-—]\s*)/) ?? []
	const text = [...new Set([...h1, ...h2, ...hostname])].join('')

	return new ImageResponse(
		<div
			tw={cn(
				'flex h-full w-full flex-col justify-between px-24 py-20',
				invert ? 'bg-white text-black' : 'bg-black text-white',
			)}
		>
			<div tw="flex h-2 w-16 rounded-full bg-[#ff4100]" />
			<hgroup tw="flex flex-col">
				<h1 tw="text-7xl leading-[1.1] font-bold">{h1}</h1>
				{h2 && (
					<h2
						tw={cn(
							'mt-4 text-4xl',
							invert ? 'text-neutral-600' : 'text-neutral-400',
						)}
					>
						{h2}
					</h2>
				)}
			</hgroup>
			<p tw="text-4xl font-bold text-[#ff4100]">{hostname}</p>
		</div>,
		{
			width: 1200,
			height: 630,
			fonts: [
				{
					name: 'Inter',
					data: await loadGoogleFont('Inter:wght@400', text),
					weight: 400,
					style: 'normal',
				},
				{
					name: 'Inter',
					data: await loadGoogleFont('Inter:wght@700', text),
					weight: 700,
					style: 'normal',
				},
			],
		},
	)
}

async function getPage({
	type,
	slug,
	perspective,
}: {
	type: string
	slug: string
} & Pick<DynamicFetchOptions, 'perspective'>) {
	'use cache'
	const { data } = await sanityFetch({
		query: OG_QUERY,
		params: { type, slug },
		perspective,
		stega: false,
	})
	return data as OG_QUERY_RESULT
}

async function loadGoogleFont(font: string, text: string) {
	const url = `https://fonts.googleapis.com/css2?family=${font}&text=${encodeURIComponent(text)}`
	const css = await (await fetch(url)).text()
	const regex = /src: url\((?<resource>.+)\) format\('(opentype|truetype)'\)/g
	const { resource } = regex.exec(css)?.groups ?? {}

	if (resource) {
		const response = await fetch(resource)
		if (response.status === 200) {
			return await response.arrayBuffer()
		}
	}

	throw new Error('Failed to load font data')
}
