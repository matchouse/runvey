import type { RouteSectionProps } from "@solidjs/router";

export default function DefaultLayout(props: RouteSectionProps<unknown>) {
	return <div>{props.children}</div>;
}
