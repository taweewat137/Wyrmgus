#!/bin/sh
# Apply the local patches in patches/<submodule>/ to the matching git submodule.
# Idempotent: a patch that is already applied is skipped, anything else aborts.
# Run after `git submodule update --init --recursive` and before cmake.
set -eu
cd "$(dirname "$0")"
for dir in patches/*/; do
	sub=$(basename "$dir")
	[ -d "$sub" ] || { echo "apply-patches: submodule directory '$sub' not found (run git submodule update --init --recursive)" >&2; exit 1; }
	for p in "$dir"*.patch; do
		[ -e "$p" ] || continue
		if git -C "$sub" apply --reverse --check "../$p" 2>/dev/null; then
			echo "apply-patches: $p already applied to $sub"
		elif git -C "$sub" apply --check "../$p"; then
			git -C "$sub" apply "../$p"
			echo "apply-patches: applied $p to $sub"
		else
			echo "apply-patches: $p does not apply cleanly to $sub" >&2
			exit 1
		fi
	done
done
