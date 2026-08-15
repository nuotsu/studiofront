import posthog from 'posthog-js'
import { ROUTES } from '@/lib/env'

const projectToken = process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN
const host = process.env.NEXT_PUBLIC_POSTHOG_HOST
const isStudioRoute = window.location.pathname.startsWith(`/${ROUTES.studio}`)

if (!projectToken || !host) {
	if (process.env.NODE_ENV === 'development') {
		const missingVariable = !projectToken
			? 'NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN'
			: 'NEXT_PUBLIC_POSTHOG_HOST'

		throw new Error(
			`${missingVariable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once ${missingVariable} is configured`,
		)
	}
} else if (!isStudioRoute) {
	posthog.init(projectToken, {
		api_host: host,
		defaults: '2026-01-30',
		capture_exceptions: true,
		debug: process.env.NODE_ENV === 'development',
	})
}
