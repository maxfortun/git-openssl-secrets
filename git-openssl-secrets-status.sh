#!/bin/sh -e
# Lists files that should be encrypted (filter=openssl) but are stored in
# plaintext, or in an older format without an integrity check. Needs no
# password: it only looks at what is stored.
#
# Usage: git-openssl-secrets-status.sh [--all] [--strict]
#   --all     check every blob in the history, not just the index
#   --strict  also fail on the older, unauthenticated format
# Exit status: 0 if all is well, 1 otherwise.
#
# A plaintext blob anywhere in the history is readable by anyone with the
# repo: rewrite it (git-rm-history.sh) and change the secret itself.
# Older formats and plaintext are rewritten by git-upgrade-openssl-secrets.sh.

all=false
strict=false
for arg in "$@"; do
	case $arg in
		--all) all=true ;;
		--strict) strict=true ;;
		*) sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 2 ;;
	esac
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-openssl-secrets-status.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# "<blob> <path>" for the index, or for every blob in the history
if $all; then
	git rev-list --all --objects | awk 'NF >= 2' | while read -r sha path; do
		if [ "$(git cat-file -t "$sha")" = blob ]; then printf '%s %s\n' "$sha" "$path"; fi
	done
else
	git ls-files -s | awk '{ sha = $2; sub(/^[^\t]*\t/, ""); print sha " " $0 }'
fi > "$tmp/blobs"

# Keep those whose path has filter=openssl
cut -d' ' -f2- "$tmp/blobs" | git check-attr filter --stdin | awk -F': ' '$3 == "openssl" { print $1 }' > "$tmp/paths"

plaintext=0
legacy=0
ok=0
while read -r sha path; do
	grep -Fxq -- "$path" "$tmp/paths" || continue
	git cat-file blob "$sha" | tr -d '\r\n' > "$tmp/b64"
	kind=plaintext
	if [ ! -s "$tmp/b64" ]; then
		kind=empty
	elif LC_ALL=C grep -Eq '^[A-Za-z0-9+/]+={0,2}$' "$tmp/b64" && [ $(($(wc -c < "$tmp/b64") % 4)) -eq 0 ] \
		&& base64 -d < "$tmp/b64" > "$tmp/raw" 2>/dev/null && [ -s "$tmp/raw" ]; then
		if [ "$(head -c 8 "$tmp/raw")" = GOS2HMAC ]; then kind=ok; else kind=legacy; fi
	fi
	case $kind in
		ok|empty) ok=$((ok + 1)) ;;
		legacy) legacy=$((legacy + 1)); echo "legacy     $path ($sha): encrypted without an integrity check" ;;
		plaintext) plaintext=$((plaintext + 1)); echo "PLAINTEXT  $path ($sha)" ;;
	esac
done < "$tmp/blobs"

echo "$ok authenticated, $legacy legacy, $plaintext plaintext"
[ "$plaintext" -eq 0 ] || exit 1
! $strict || [ "$legacy" -eq 0 ] || exit 1
