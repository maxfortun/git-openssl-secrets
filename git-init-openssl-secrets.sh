#!/bin/bash -e

SD=$(dirname $0)

repo=${1:-.}
if [ ! -d $repo/.git ]; then 
    echo "Not in a git directory and no git directory passed in a parameters."
    echo "Usage: $0 [dir]"
    exit 1
fi

#git reset --hard

. $SD/git-setenv-openssl-secrets.sh

cp $SD/git-setenv-openssl-secrets.sh $repo/.git/

path=filter/openssl
[ -d "$repo/.git/$path" ] || mkdir -p "$repo/.git/$path"
for filter in clean smudge; do
    cp $SD/git/$path/$filter.sh $repo/.git/$path/$filter.sh
    git config --unset-all filter.openssl.$filter || true
    git config --add filter.openssl.$filter ".git/$path/$filter.sh %f"
done
git config filter.openssl.required true

path=diff/openssl
[ -d "$repo/.git/$path" ] || mkdir -p "$repo/.git/$path"
for diff in textconv; do
    cp $SD/git/$path/$diff.sh $repo/.git/$path/$diff.sh
    git config --unset-all diff.openssl.$diff || true
    git config --add diff.openssl.$diff .git/$path/$diff.sh
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
git ls-files --modified | grep -v .gitattributes | xargs -L1 git checkout HEAD -- 
cd -

