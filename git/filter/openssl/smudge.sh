#!/bin/bash -e
. .secrets/git-setenv-openssl-secrets.sh

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

TMP_FILE=/tmp/$(basename $0).$$
cat > $TMP_FILE
cat $TMP_FILE | openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -base64 -salt -S $GIT_FILTER_OPENSSL_SALT -k $GIT_FILTER_OPENSSL_PASSWORD 2> /dev/null || cat $TMP_FILE
rm $TMP_FILE
