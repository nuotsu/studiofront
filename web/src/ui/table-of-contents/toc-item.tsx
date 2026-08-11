'use client'

import { stegaClean } from 'next-sanity'
import { useEffect, useRef, useState, type ComponentProps } from 'react'
import { cn, slug } from '@/lib/utils'
import css from './toc.module.css'

export default function ({
	heading,
	...props
}: {
	heading: {
		style: string | null
		text: string | null
	}
} & ComponentProps<'li'>) {
	if (!heading.text) return null

	const ref = useRef<HTMLLIElement>(null)
	const [thresholdHeight, setThresholdHeight] = useState(0)

	// threshold height = 1/2 of viewport
	useEffect(() => {
		const updateThresholdHeight = () =>
			setThresholdHeight(window.innerHeight / 2)
		updateThresholdHeight()

		window.addEventListener('resize', updateThresholdHeight)
		return () => window.removeEventListener('resize', updateThresholdHeight)
	}, [])

	// add className when heading is in view
	useEffect(() => {
		if (typeof document === 'undefined' || !ref.current || !heading.text) return

		const target = ref.current
			.closest('[data-module]')
			?.querySelector(
				`#${slug(heading.text, { removeLeadingNumberAndHyphen: true })}`,
			)!

		const observer = new IntersectionObserver(
			(entries) => {
				entries.forEach((entry) => {
					if (entry.isIntersecting) {
						ref.current?.classList.add(css.inView)
					} else {
						ref.current?.classList.remove(css.inView)
					}
				})
			},
			{
				threshold: 1,
				rootMargin: `${document.documentElement.scrollHeight}px 0px -${thresholdHeight}px 0px`,
			},
		)

		if (target) observer.observe(target)
		return () => observer.disconnect()
	}, [heading, thresholdHeight])

	return (
		<li ref={ref} {...props}>
			<a
				href={`#${slug(heading.text, { removeLeadingNumberAndHyphen: true })}`}
				className={cn('text-foreground block py-1 hover:underline', {
					'pl-ch': stegaClean(heading.style) === 'h2',
					'pl-[2ch]': stegaClean(heading.style) === 'h3',
					'pl-[3ch]': stegaClean(heading.style) === 'h4',
					'pl-[4ch]': stegaClean(heading.style) === 'h5',
					'pl-[5ch]': stegaClean(heading.style) === 'h6',
				})}
			>
				{heading.text}
			</a>
		</li>
	)
}
