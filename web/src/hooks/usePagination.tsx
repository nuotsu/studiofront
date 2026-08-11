'use client'

import { parseAsInteger, useQueryState } from 'nuqs'
import { useCallback, useEffect } from 'react'

type PaginationProps = React.ComponentProps<'nav'> &
	Partial<{
		buttonClassName: string
		prevClassName: string
		nextClassName: string
		prev: React.ReactNode
		next: React.ReactNode
		hidePage: boolean
		onClick: () => void
	}>

export function usePagination<T>({
	items = [],
	itemsPerPage = 3,
}: {
	items: T[]
	itemsPerPage?: number
}) {
	const { page, setPage } = usePageState()

	const totalPages = Math.max(1, Math.ceil(items.length / itemsPerPage))

	// Reset to last valid page if current page exceeds total
	useEffect(() => {
		if (page > totalPages) {
			setPage(totalPages)
		}
	}, [page, totalPages, setPage])

	const atStart = page === 1
	const atEnd = page >= totalPages

	const onPrev = useCallback(
		() => setPage(Math.max(1, page - 1)),
		[page, setPage],
	)
	const onNext = useCallback(
		() => setPage(Math.min(totalPages, page + 1)),
		[totalPages, page, setPage],
	)

	const paginatedItems = items.slice(
		itemsPerPage * (page - 1),
		itemsPerPage * page,
	)

	const Pagination = ({
		buttonClassName,
		prevClassName,
		nextClassName,
		prev = 'Prev',
		next = 'Next',
		hidePage,
		onClick = () => {},
		...props
	}: PaginationProps) => {
		if (atStart && atEnd) return null

		return (
			<nav aria-label="Pagination" {...props}>
				<button
					className={prevClassName || buttonClassName}
					onClick={() => {
						onPrev()
						onClick()
					}}
					disabled={atStart}
					aria-label="Previous page"
				>
					{prev}
				</button>

				{!hidePage && (
					<span>
						{page} of {totalPages}
					</span>
				)}

				<button
					className={nextClassName || buttonClassName}
					onClick={() => {
						onNext()
						onClick()
					}}
					disabled={atEnd}
					aria-label="Next page"
				>
					{next}
				</button>
			</nav>
		)
	}

	return {
		atStart,
		atEnd,
		onPrev,
		onNext,
		paginatedItems,
		Pagination,
		currentPage: page,
		totalPages,
	}
}

export function usePageState() {
	const [page, setPage] = useQueryState('page', parseAsInteger.withDefault(1))
	return { page, setPage }
}
