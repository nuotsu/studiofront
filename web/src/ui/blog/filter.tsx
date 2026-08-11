'use client'

import posthog from 'posthog-js'
import { cn } from '@/lib/utils'
import type { BlogCategory } from '@/sanity/types'
import { useBlogIndexStore } from '@/modules/blog-index/store'

export default function ({
	category,
	children,
}: {
	category?: BlogCategory
} & React.ComponentProps<'button'>) {
	const { categoryParam, setCategoryParam } = useBlogIndexStore()
	const slug = category?.slug?.current

	return (
		<button
			className={cn(
				categoryParam === slug || (!categoryParam && !category)
					? 'action'
					: 'ghost',
			)}
			onClick={() => {
				const isSelected = categoryParam !== slug
				setCategoryParam(isSelected ? (slug ?? null) : null)
				posthog.capture('blog_category_selected', {
					category_slug: isSelected ? (slug ?? null) : null,
				})
			}}
		>
			{children || category?.title}
		</button>
	)
}
