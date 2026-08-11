import { VscChromeClose, VscMenu } from 'react-icons/vsc'

export default function () {
	return (
		<label className="text-xl md:hidden">
			<input id="header-open" type="checkbox" hidden />

			<VscMenu className="header-open:hidden" title="Open" />
			<VscChromeClose className="header-not-open:hidden" title="Close" />
		</label>
	)
}
