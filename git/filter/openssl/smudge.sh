#!/bin/bash -e

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh

TMP_FILE="/tmp/$(basename $0).$LOGNAME.$$"
cat > "$TMP_FILE"

if cat "$TMP_FILE" | base64 -d > "$TMP_FILE.decoded" 2>/dev/null; then

	# Legacy support.
	if ! grep -q ^Salted__ "$TMP_FILE.decoded"; then
    	SALT_PARAMS="-S $GIT_FILTER_OPENSSL_SALT"
	fi

	openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 $SALT_PARAMS -k $GIT_FILTER_OPENSSL_PASSWORD -in "$TMP_FILE.decoded" 2> /dev/null || cat "$TMP_FILE"
else
	cat "$TMP_FILE"
fi
rm "$TMP_FILE"*

trackingDir=".git/filter/openssl/tracking"
trackingFile="$trackingDir/$file"
trackingFileDir="$(dirname $trackingFile)"
[ -d "$trackingFileDir" ] || mkdir -p "$trackingFileDir"
touch "$trackingFile"

