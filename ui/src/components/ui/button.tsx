import { cn } from "@/lib/utils";
import { type JSX, splitProps } from "solid-js";

const variant = {
	default: "bg-primary-500 hover:bg-primary",
	success: "bg-green-500",
	warning: "bg-yellow-500",
};

export default function Button(
	props: {
		variant?: keyof typeof variant;
	} & JSX.ButtonHTMLAttributes<HTMLButtonElement>,
) {
	const [localProps, restProps] = splitProps(props, ["variant", "class"]);
	return (
		<button
			class={cn(
				variant[localProps.variant ?? "default"],
				"transition-all p-2 px-4 border rounded-lg cursor-pointer ",
				localProps.class,
			)}
			{...restProps}
		/>
	);
}
