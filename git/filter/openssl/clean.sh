#!/bin/bash -e
file=$1

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

trackingDir=".git/filter/openssl/tracking"
trackingFile="$trackingDir/$file"

if [ ! -f "$trackingFile" ] && git ls-files --error-unmatch $file 1>/dev/null 2>/dev/null; then
	cat $file
	exit 0
fi

trackingFileDir="$(dirname $trackingFile)"
[ -d "$trackingFileDir" ] || mkdir -p "$trackingFileDir"
touch $trackingFile

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh

TMP_FILE="/tmp/$(basename $0).$LOGNAME.$$"
openssl enc -aes-256-cbc -md sha512 -pbkdf2 -S $GIT_FILTER_OPENSSL_SALT -k $GIT_FILTER_OPENSSL_PASSWORD -out "$TMP_FILE"
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


