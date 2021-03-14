#!/bin/bash -e

SALT=$(cat ~/.config/git/openssl-salt)
PASSWORD=$(cat ~/.config/git/openssl-password)

openssl enc -aes-256-cbc -base64 -pbkdf2 -S $SALT -k $PASSWORD

