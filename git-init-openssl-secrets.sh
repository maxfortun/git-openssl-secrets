#!/bin/bash -e

SD=$(dirname $0)

repo=${1:-.}
if [ ! -d $repo/.git ]; then 
    echo "Not in a git directory and no git directory passed in a parameters."
    echo "Usage: $0 [dir]"
    exit 1
fi

opensslVersion=$(openssl version)
if ! echo "$opensslVersion" | grep -q 'OpenSSL 3'; then
	echo "OpenSSL 3 is required. Found: $opensslVersion"
	exit 1
fi

cd $repo

. $SD/git-setenv-openssl-secrets.sh

SECRETS=.secrets

[ -d $SECRETS ] || mkdir $SECRETS

cp $SD/git-setenv-openssl-secrets.sh $SECRETS/

path=filter/openssl
[ -d "$SECRETS/$path" ] || mkdir -p "$SECRETS/$path"
for filter in clean smudge; do
    [ -f $SECRETS/$path/$filter.sh ] || cp $SD/git/$path/$filter.sh $SECRETS/$path/$filter.sh
    git config --unset-all filter.openssl.$filter || true
    git config --add filter.openssl.$filter "$SECRETS/$path/$filter.sh %f"
done
git config filter.openssl.required true

path=diff/openssl
[ -d "$SECRETS/$path" ] || mkdir -p "$SECRETS/$path"
for diff in textconv; do
    [ -f $SECRETS/$path/$diff.sh ] || cp $SD/git/$path/$diff.sh $SECRETS/$path/$diff.sh
    git config --unset-all diff.openssl.$diff || true
    git config --add diff.openssl.$diff $SECRETS/$path/$diff.sh
done

if [ -f "$repo/.gitattributes" ]; then
    backup="$repo/.gitattributes.$(date +%Y%m%d%H%M%S)"
    mv "$repo/.gitattributes" "$backup"
    cat "$backup" | sort -fu > "$backup.sorted"
    cat $SD/gitattributes "$backup" | sort -fu > $repo/.gitattributes
	diff -q $SD/gitattributes "$backup.sorted" 2>/dev/null || mv "$backup" "$repo/.gitattributes"
	rm "$backup.sorted"
else
    cp $SD/gitattributes "$repo/.gitattributes"
fi

cd $repo

git add .gitattributes
git add $SECRETS

git ls-files --modified | grep -v .gitattributes | xargs -L1 git checkout HEAD -- 

rm .git/index
git checkout HEAD -- .

cd -

