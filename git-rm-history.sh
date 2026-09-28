#!/bin/bash -e
pattern="$1"

if [ -z "$pattern" ]; then
	echo "Removes file(s) from git history"
	echo "Usage: $0 <pattern>"
	echo " e.g.: $0 ^secrets/"
	echo "     : $0 \\.tfstate\\\$"
	exit 1
fi

paths=$(git log --all --pretty=format: --name-only --no-renames | sort -u | grep -- "$pattern" || true)
if [ -z "$paths" ]; then
	echo "No paths in history match $pattern"
	exit 1
fi

read -p "$paths"$'\n'"---"$'\n'"These files will be completely removed from git history."$'\n'"There is no undoing this operation."$'\n'"Are you sure? (no/yes) " response
if [ "$response" != "yes" ]; then
	echo "Aborted."
	exit 1
fi

echo "Removing in 5 seconds. Stand by or break out with CTRL-C."
sleep "${GIT_RM_HISTORY_DELAY:-5}"

# filter-branch evals the filter with /bin/sh, so quote for POSIX sh.
sq="'"
esc="'\\''"
quoted=
while IFS= read -r path; do
	quoted+=" '${path//$sq/$esc}'"
done <<< "$paths"

FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --force --index-filter \
	"git rm -q --cached --ignore-unmatch --$quoted" \
	--prune-empty --tag-name-filter cat -- --all

echo "The old history is kept locally under refs/original/. To purge it:"
echo "  git for-each-ref --format='delete %(refname)' refs/original | git update-ref --stdin && git reflog expire --expire=now --all && git gc --prune=now"
echo "If any of these files held secrets that were ever pushed, rotate them: rewriting history does not revoke copies."

read -p "Push changes? (no/yes) " response
if [ "$response" != "yes" ]; then
	echo "Aborted."
	exit 1
fi

git push origin --force --all
git push origin --force --tags
