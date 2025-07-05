#!/bin/bash -e
pattern="$1"

if [ -z "$pattern" ]; then
	echo "Removes file(s) from git history"
	echo "Usage: $0 <pattern>"
	echo " e.g.: $0 \\.tfstate\\\$"
	exit 1
fi

paths=$(git log --pretty=format: --name-status | cut -f2- | sort -u|grep "$pattern")
read -p "$paths"$'\n'"These files will be completely removed from git history. Are you sure? (no/yes) " response
if [ "$response" != "yes" ]; then
	echo "Aborted."
	exit 1
fi

echo "Removing in 5 seconds. Stand by or break out with CTRL-C."
sleep 5

for path in $paths; do
	git filter-branch --force --index-filter \
		"git rm --cached --ignore-unmatch $path" \
		--prune-empty --tag-name-filter cat -- --all
done 

read -p "Push changes? (no/yes) " response
if [ "$response" != "yes" ]; then
	echo "Aborted."
	exit 1
fi

git push origin --force --all
git push origin --force --tags

