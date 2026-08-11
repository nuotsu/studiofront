import { defineField, defineType } from 'sanity'
import { RxInput } from 'react-icons/rx'

export default defineType({
	name: 'form',
	title: 'Form',
	type: 'document',
	icon: RxInput,
	fields: [
		defineField({
			name: 'identifier',
			title: 'Identifier',
			type: 'string',
			placeholder: 'e.g. "contact" or "demo-request"',
		}),
		defineField({
			name: 'endpoint',
			type: 'url',
		}),
	],
	preview: {
		select: {
			identifier: 'identifier',
			endpoint: 'endpoint',
		},
		prepare: ({ identifier, endpoint }) => ({
			title: identifier,
			subtitle: endpoint,
		}),
	},
})
