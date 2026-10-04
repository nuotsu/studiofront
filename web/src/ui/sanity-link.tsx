import { stegaClean } from 'next-sanity'
import NextLink, { type LinkProps } from 'next/link'
import { FaApple } from 'react-icons/fa6'
import { cn } from '@/lib/utils'
import type { Link, Page } from '@/sanity/types'
import DownloadMacosLink from './download-macos-link'

export type SanityLinkType = Omit<Link, 'internal'> & {
	_type?: 'link'
	_key?: string
	internal?: Omit<Page, 'metadata'> & { slug: string }
}

export default function ({
	link,
	children,
	showIcon,
	hideFreeTrial,
	...props
}: {
	link?: SanityLinkType
	showIcon?: boolean
	hideFreeTrial?: boolean
} & Omit<React.ComponentProps<typeof NextLink>, 'href'>) {
	const { label, type, internal, external, params } = link ?? {}

	const linkProps: Omit<LinkProps, 'href'> | React.ComponentProps<'a'> = {
		...props,
		children:
			children ||
			stegaClean(label) ||
			stegaClean(internal?.title) ||
			stegaClean(external),
	}

	if (type === 'internal' && internal?.slug)
		return (
			<NextLink
				href={[internal.slug, stegaClean(params)].filter(Boolean).join('')}
				{...linkProps}
			/>
		)

	if (type === 'external' && external)
		return <NextLink href={stegaClean(external)} {...linkProps} />

	if (type === 'download_macos')
		return (
			<DownloadMacosLink
				{...linkProps}
				className={cn('relative', linkProps.className)}
				children={
					<>
						{showIcon && <FaApple aria-hidden />}
						{linkProps.children}
						{/* v0.2.0: Studiofront is now fully free with unlimited usage */}
						{/* {!hideFreeTrial && (
							<small className="text-foreground/80 absolute top-full left-1/2 min-w-max -translate-x-1/2 translate-y-[.5lh] leading-none">
								Try free for 7 days
							</small>
						)} */}
					</>
				}
			/>
		)

	return <span {...linkProps} />
}
