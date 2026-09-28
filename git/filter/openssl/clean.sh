#!/bin/sh -e
file=$1

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo "$0 $*" >&2
	set -x
fi

SD=$(dirname "$0")
. "$SD/common.sh"
openssl_secrets_setenv "$SD/../.."
openssl_secrets_mktemp
tmp=$OPENSSL_SECRETS_TMP

# git passes the content to stage on stdin. Read the file only when run by hand.
if [ -t 0 ] && [ -f "$file" ]; then cat "$file"; else cat; fi > "$tmp/in"

trackingFile="$(git rev-parse --git-path filter/openssl/tracking)/$file"

if git cat-file -e ":$file" 2>/dev/null; then
	git cat-file blob ":$file" > "$tmp/index"
	if openssl_secrets_decrypt "$tmp/index" "$tmp/index.plain"; then
		# Content unchanged: keep the staged blob, whichever format wrote it.
		if cmp -s "$tmp/in" "$tmp/index.plain"; then
			cat "$tmp/index"
			exit 0
		fi
	elif [ ! -f "$trackingFile" ]; then
		# Tracked in plaintext and not yet checked out through this filter.
		cat "$tmp/in"
		exit 0
	fi
fi

if [ -z "$GIT_FILTER_OPENSSL_SALT" ] || [ -z "$GIT_FILTER_OPENSSL_PASSWORD" ]; then
	echo "$0: GIT_FILTER_OPENSSL_SALT and GIT_FILTER_OPENSSL_PASSWORD are required to encrypt $file" >&2
	exit 1
fi

mkdir -p "$(dirname "$trackingFile")"
touch "$trackingFile"

openssl_secrets_encrypt "$tmp/in"
