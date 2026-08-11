'use client'

import posthog from 'posthog-js'
import { SORT_BY_OPTIONS, useBlogIndexStore } from './store'

export default function () {
	const { setSortBy } = useBlogIndexStore()

	return (
		<label className="flex items-center gap-[.5ch]">
			<span>Sort by:</span>

			<select
				className="ghost cursor-pointer text-left"
				onChange={(e) => {
					const sortBy = e.target.value as any
					setSortBy(sortBy)
					posthog.capture('blog_sort_changed', { sort_by: sortBy })
				}}
			>
				{SORT_BY_OPTIONS.map((option) => (
					<option value={option.value} key={option.value}>
						{option.label}
					</option>
				))}
			</select>
		</label>
	)
}
