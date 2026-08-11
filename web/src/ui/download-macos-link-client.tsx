'use client'

import NextLink, { type LinkProps } from 'next/link'
import posthog from 'posthog-js'
import { MACOS_DMG_FILENAME, MACOS_DMG_URL } from '@/lib/download-macos'

export default function ({
	version,
	onClick,
	...props
}: {
	version: string
} & Omit<LinkProps, 'href'> &
	React.ComponentProps<'a'>) {
	return (
		<NextLink
			href={MACOS_DMG_URL}
			download={MACOS_DMG_FILENAME}
			{...props}
			onClick={(e) => {
				onClick?.(e)
				posthog.capture('download_macos_clicked', {
					version,
					filename: MACOS_DMG_FILENAME,
					url: MACOS_DMG_URL,
				})
			}}
		/>
	)
}
