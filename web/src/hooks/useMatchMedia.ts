import { useEffect, useState } from 'react'

export default function useMatchMedia(query: string) {
	const [isMatch, setIsMatch] = useState(false)

	useEffect(() => {
		if (typeof window === 'undefined') return
		function handleMatchMedia() {
			setIsMatch(window.matchMedia(query).matches)
		}
		handleMatchMedia()
		window.addEventListener('resize', handleMatchMedia)
		return () => window.removeEventListener('resize', handleMatchMedia)
	}, [isMatch])

	return isMatch
}

export function useIsDesktop() {
	return useMatchMedia('(pointer: fine), (width >= 48rem)')
}
