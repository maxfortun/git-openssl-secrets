#!/bin/bash -e
file=$1

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh

if cat "$file" | base64 -d > "$file.decoded" 2>/dev/null; then

	# Legacy support.
	if ! head -1 "$file.decoded" | cut -b1-8 | grep -q ^Salted__; then
    	SALT_PARAMS="-S $GIT_FILTER_OPENSSL_SALT"
	fi

	openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 $SALT_PARAMS -k $GIT_FILTER_OPENSSL_PASSWORD -in "$file.decoded" 2> /dev/null || cat "$file"
else
	cat "$file"
fi

trackingDir=".git/filter/openssl/tracking"
trackingFile="$trackingDir/$file"
trackingFileDir="$(dirname $trackingFile)"
[ -d "$trackingFileDir" ] || mkdir -p "$trackingFileDir"
touch "$trackingFile"

