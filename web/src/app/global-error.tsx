'use client'

import { useEffect } from 'react'
import posthog from 'posthog-js'

export default function GlobalError({
	error,
}: {
	error: Error & { digest?: string }
}) {
	useEffect(() => {
		posthog.captureException(error)
	}, [error])

	return (
		<html lang="en">
			<body>
				<h1>Something went wrong</h1>
				<p>Please try again later.</p>
			</body>
		</html>
	)
}
