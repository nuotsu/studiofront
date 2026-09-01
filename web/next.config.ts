import type { NextConfig } from 'next'
import { groq } from 'next-sanity'
import { sanity } from 'next-sanity/live/cache-life'
import { ROUTES } from './src/lib/env'
import { client } from './src/sanity/lib/client'

const nextConfig: NextConfig = {
	reactCompiler: true,

	cacheComponents: true,
	cacheLife: { default: sanity },

	transpilePackages: [
		'sanity',
		'next-sanity',
		'@sanity/vision',
		'@sanity/assist',
		'@sanity/code-input',
		'@sanity/dashboard',
		'@sanity/block-insert-picker',
	],

	turbopack: {
		// @sanity/sdk-react pins an older workbench whose "development" export
		// points at TypeScript source, which Turbopack can't load from node_modules.
		resolveAlias: {
			'@sanity/workbench': './node_modules/@sanity/workbench/dist/index.js',
			'@sanity/workbench/_internal':
				'./node_modules/@sanity/workbench/dist/_internal.js',
			'@sanity/workbench/core': './node_modules/@sanity/workbench/dist/core.js',
			'@sanity/workbench/system':
				'./node_modules/@sanity/workbench/dist/system.js',
		},
	},

	images: {
		localPatterns: [{ pathname: '/api/og' }],
		remotePatterns: [{ protocol: 'https', hostname: 'cdn.sanity.io' }],
	},

	async rewrites() {
		return [
			{ source: '/:slug.md', destination: '/api/md/:slug' },
			{ source: '/:path*/:slug.md', destination: '/api/md/:path*/:slug' },
		]
	},

	async redirects() {
		const sanityRedirects = await client.fetch(
			groq`*[_type == 'redirect']{
				source,
				'destination': select(
					destination.type == 'internal' =>
						select(
							destination.internal->._type == 'blog.post' => $blogDir,
							''
						) + select(
							destination.internal->.metadata.slug.current == 'index' => '/',
							'/' + destination.internal->.metadata.slug.current
						),
					destination.external
				),
				'permanent': true
			}`,
			{ blogDir: `/${ROUTES.blog}/` },
		)

		return [
			{ source: '/index', destination: '/', permanent: true },
			...sanityRedirects,
		]
	},
}

export default nextConfig
