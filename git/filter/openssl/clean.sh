#!/bin/bash -e

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh

TMP_FILE="/tmp/$(basename $0).$LOGNAME.$$"
openssl enc -aes-256-cbc -md md5 -S $GIT_FILTER_OPENSSL_SALT -k $GIT_FILTER_OPENSSL_PASSWORD -out "$TMP_FILE"
if grep -q ^Salted__ "$TMP_FILE"; then
	cat "$TMP_FILE" | base64
else
	(
		echo -n "Salted__"
		echo -ne "$(echo $GIT_FILTER_OPENSSL_SALT | sed -e 's/../\\x&/g')"
		cat "$TMP_FILE"
	) | base64
fi

rm "$TMP_FILE"


