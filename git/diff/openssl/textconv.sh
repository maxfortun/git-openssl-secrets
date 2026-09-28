#!/bin/sh -e

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo "$0 $*" >&2
	set -x
fi

SD=$(dirname "$0")
. "$SD/../../filter/openssl/common.sh"
openssl_secrets_setenv "$SD/../.."
openssl_secrets_mktemp

if openssl_secrets_decrypt "$1" "$OPENSSL_SECRETS_TMP/out"; then
	cat "$OPENSSL_SECRETS_TMP/out"
else
	cat "$1"
fi
