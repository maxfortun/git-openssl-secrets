#!/bin/bash -e
SD=$(dirname $0)

repo=${1:-.}
if [ ! -d $repo/.git ]; then 
    echo "Not in a git directory and no git directory passed in a parameters."
    echo "Usage: $0 [dir]"
    exit 1
fi

CONFIG_DIR="$HOME/.config/git"

[ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR" && chmod og-rwx "$CONFIG_DIR"

if [ ! -f $CONFIG_DIR/openssl-salt ]; then
    echo "Looks like you do not yet have salt for your secrets. Generating."
    openssl rand -hex 8 > $CONFIG_DIR/openssl-salt
    chmod og-rwx $CONFIG_DIR/openssl-salt
fi

if [ ! -f $CONFIG_DIR/openssl-password ]; then
    echo "Looks like you do not yet have a password for your secrets. Generating."
    openssl rand -base64 32 > $CONFIG_DIR/openssl-password
    chmod og-rwx $CONFIG_DIR/openssl-password
fi

filter_path=filters/openssl
[ -d "$repo/.git/$filter_path" ] || mkdir -p "$repo/.git/$filter_path"
for filter in clean smudge diff; do
    cp $SD/git/$filter_path/$filter.sh $repo/.git/$filter_path/$filter.sh
    git config --unset-all filter.openssl.$filter || true
    git config --add filter.openssl.$filter .git/$filter_path/$filter.sh
done
git config filter.openssl.required true

if [ -f "$repo/.gitattributes" ]; then
    backup="$repo/.gitattributes.$(date +%Y%m%d%H%M%S)"
    cp "$repo/.gitattributes" "$backup"
    cat $SD/gitattributes "$backup" | sort -fu > $repo/.gitattributes
else
    cp $SD/gitattributes "$repo/.gitattributes"
fi


