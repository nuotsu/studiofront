import type { LinkProps } from 'next/link'
import { getLatestMacosRelease } from '@/lib/get-latest-macos-release'
import DownloadMacosLinkClient from './download-macos-link-client'

export default async function (
	props: Omit<LinkProps, 'href'> & React.ComponentProps<'a'>,
) {
	const { version } = await getLatestMacosRelease()
	return <DownloadMacosLinkClient version={version} {...props} />
}
