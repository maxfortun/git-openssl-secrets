#!/bin/bash -e

PASSWORD=$(cat ~/.config/git/openssl-password)

openssl enc -d -aes-256-cbc -base64 -pbkdf2 -k $PASSWORD 2> /dev/null || cat
