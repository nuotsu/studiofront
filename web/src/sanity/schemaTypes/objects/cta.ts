import { defineField, defineType } from 'sanity'
import { VscInspect } from 'react-icons/vsc'

export default defineType({
	name: 'cta',
	title: 'Call-to-action',
	icon: VscInspect,
	type: 'object',
	fields: [
		defineField({
			name: 'link',
			type: 'link',
		}),
		defineField({
			name: 'theme',
			type: 'string',
			options: {
				list: [
					'action',
					{ title: 'Action (outline)', value: 'action-outline' },
					'ghost',
					'link',
				],
			},
		}),
	],
	preview: {
		select: {
			link: 'link',
			pageTitle: 'link.internal.title',
			pageSlug: 'link.internal.metadata.slug.current',
		},
		prepare: ({ link, pageTitle, pageSlug }) => {
			const slug =
				link.type === 'internal'
					? pageSlug === 'index'
						? '/'
						: [pageSlug && `/${pageSlug}`, link.params].filter(Boolean).join('')
					: link.type === 'external'
						? link.external
						: link.type === 'download_macos'
							? 'Download (macOS)'
							: null

			return {
				title: link.label || pageTitle,
				subtitle: slug,
			}
		},
	},
})
