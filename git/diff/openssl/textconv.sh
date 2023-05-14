#!/bin/bash -e
. .git/git-setenv-openssl-secrets.sh

openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -base64 -k $GIT_FILTER_OPENSSL_PASSWORD -in "$1" 2> /dev/null || cat "$1"
