#!/bin/bash -e

if [ "$GIT_FILTER_OPENSSL_DEBUG" = "true" ]; then
	echo $0 $* >&2
	set -x
fi

[ ! -f .secrets/git-setenv-openssl-secrets.sh ] || . .secrets/git-setenv-openssl-secrets.sh
openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -base64 -S $GIT_FILTER_OPENSSL_SALT -k $GIT_FILTER_OPENSSL_PASSWORD

