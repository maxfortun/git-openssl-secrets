#!/bin/bash -e
. .secrets/git-setenv-openssl-secrets.sh

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

TMP_FILE="/tmp/$(basename $0).$$"
cat > "$TMP_FILE"
cat "$TMP_FILE" | base64 -d > "$TMP_FILE.decoded"

# Legacy support.
if ! grep -q ^Salted__ "$TMP_FILE.decoded"; then
    SALT_PARAMS="-S $GIT_FILTER_OPENSSL_SALT"
fi

openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 $SALT_PARAMS -k $GIT_FILTER_OPENSSL_PASSWORD -in "$TMP_FILE.decoded" 2> /dev/null || cat "$TMP_FILE"

rm "$TMP_FILE"*
