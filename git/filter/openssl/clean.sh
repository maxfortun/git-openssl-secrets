#!/bin/bash -e

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

trackingDir=".git/filter/openssl/tracking"
trackingFile="$trackingDir/$file"

if [ -f "$trackingFile" ]; then
	cat
	exit 0
fi

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh

TMP_FILE="/tmp/$(basename $0).$LOGNAME.$$"
openssl enc -aes-256-cbc -md md5 -S $GIT_FILTER_OPENSSL_SALT -k $GIT_FILTER_OPENSSL_PASSWORD -out "$TMP_FILE"
if head -1 "$TMP_FILE" | cut -b1-8 | grep -q ^Salted__; then
	cat "$TMP_FILE" | base64 | tr -d '\n'
else
	(
		echo -n "Salted__"
		echo -ne "$(echo $GIT_FILTER_OPENSSL_SALT | sed -e 's/../\\x&/g')"
		cat "$TMP_FILE"
	) | base64 | tr -d '\n'
fi

rm "$TMP_FILE"


