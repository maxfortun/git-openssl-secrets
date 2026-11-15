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
# Explicit exit: git may run this as "dash clean.sh", without the -e of the shebang
openssl_secrets_format || exit 1
tmp=$OPENSSL_SECRETS_TMP

# git passes the content to stage on stdin. Read the file only when run by hand.
if [ -t 0 ] && [ -f "$file" ]; then cat "$file"; else cat; fi > "$tmp/in"

trackingFile="$(git rev-parse --git-path filter/openssl/tracking)/$file"

# GIT_FILTER_OPENSSL_REENCRYPT=true (set by git-upgrade-openssl-secrets.sh)
# rewrites unchanged blobs and plaintext in the current format.
if git cat-file -e ":$file" 2>/dev/null; then
	git cat-file blob ":$file" > "$tmp/index"
	openssl_secrets_decrypt "$tmp/index" "$tmp/index.plain" && rc=0 || rc=$?
	if [ $rc -eq 2 ] && openssl_secrets_is_encrypted "$tmp/index"; then
		# The stored secret can't be read (wrong password, modified, too new):
		# never overwrite it with something we couldn't check.
		if cmp -s "$tmp/in" "$tmp/index"; then
			cat "$tmp/index"
			exit 0
		fi
		echo "$0: the stored version of $file can't be decrypted, refusing to overwrite it" >&2
		exit 1
	fi
	if [ "${GIT_FILTER_OPENSSL_REENCRYPT:-}" = "true" ]; then
		:
	elif [ $rc -eq 0 ]; then
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
