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

# git passes the blob on stdin. Read the file only when run by hand.
if [ -t 0 ] && [ -f "$file" ]; then cat "$file"; else cat; fi > "$tmp/in"

openssl_secrets_decrypt "$tmp/in" "$tmp/out" && rc=0 || rc=$?
case $rc in
	0) cat "$tmp/out" ;;
	2) echo "$0: cannot decrypt $file, leaving it encrypted" >&2; cat "$tmp/in" ;;
	*) cat "$tmp/in" ;;
esac

trackingFile="$(git rev-parse --git-path filter/openssl/tracking)/$file"
mkdir -p "$(dirname "$trackingFile")"
touch "$trackingFile"
