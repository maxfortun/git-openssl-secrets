#!/bin/bash -e

SD=$(cd "$(dirname "$0")" && pwd)

usage() {
	echo "Usage: $0 [--upgrade] [--force] [dir]"
	echo "  --upgrade  replace installed filter scripts even if they were modified"
	echo "  --force    run even if tracked files have uncommitted changes, discarding them"
}

upgrade=
force=
while [ $# -gt 0 ]; do
	case $1 in
		--upgrade) upgrade=true ;;
		--force) force=true ;;
		-h|--help) usage; exit 0 ;;
		--) shift; break ;;
		-*) usage; exit 1 ;;
		*) break ;;
	esac
	shift
done

if ! repo=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null); then
	echo "Not in a git directory and no git directory passed in as a parameter."
	usage
	exit 1
fi

opensslVersion=$(openssl version)
if ! echo "$opensslVersion" | grep -Eq '^OpenSSL ([3-9]|[1-9][0-9])\.'; then
	echo "OpenSSL 3 or newer is required. Found: $opensslVersion"
	exit 1
fi

if [ ! -f "$SD/git-setenv-openssl-secrets.sh" ]; then
	echo "$SD/git-setenv-openssl-secrets.sh not found."
	echo "Link it to one of $SD/git-setenv-openssl-secrets-*.sh, see README.md."
	exit 1
fi

cd "$repo"

SECRETS=.secrets

# Checking out below overwrites tracked files, so don't lose uncommitted work.
if [ -z "$force" ] && git rev-parse -q --verify HEAD >/dev/null &&
	! git diff --quiet HEAD -- . ":(exclude).gitattributes" ":(exclude)$SECRETS"; then
	echo "Tracked files have uncommitted changes. Commit or stash them, or rerun with --force to discard them."
	exit 1
fi

# Older versions cached the salt and password inside the working tree.
legacyCache=$SECRETS/git-setenv-openssl-secrets.sh.cache
if [ -f "$legacyCache" ]; then
	if git ls-files --error-unmatch "$legacyCache" >/dev/null 2>&1; then
		echo "WARNING: $legacyCache is committed and contains your salt and password in plaintext."
		echo "WARNING: Remove it from history with git-rm-history.sh and rotate them."
	else
		mv "$legacyCache" "$(git rev-parse --git-path openssl-secrets.cache)"
	fi
fi

# True if $2 is identical to a committed version of $1 in this tool's repo,
# i.e. it was installed by an older version and never customized.
is_pristine() {
	local hash
	hash=$(git hash-object --no-filters "$2")
	git -C "$SD" log --all --format= --raw --no-abbrev -- "$1" 2>/dev/null | awk '{print $4}' | grep -qx "$hash"
}

install_file() {
	local src=$1 dst=$SECRETS/${1#git/}
	mkdir -p "$(dirname "$dst")"
	if [ ! -f "$dst" ] || [ -n "$upgrade" ] || is_pristine "$src" "$dst"; then
		cp "$SD/$src" "$dst"
	elif ! cmp -s "$SD/$src" "$dst"; then
		echo "Keeping modified $dst. Rerun with --upgrade to replace it."
	fi
}

mkdir -p $SECRETS
cp "$SD/git-setenv-openssl-secrets.sh" $SECRETS/

path=filter/openssl
install_file git/$path/common.sh
for filter in clean smudge; do
	install_file git/$path/$filter.sh
	git config --unset-all filter.openssl.$filter || true
	git config --add filter.openssl.$filter "$SECRETS/$path/$filter.sh %f"
done
git config filter.openssl.required true

path=diff/openssl
for diff in textconv; do
	install_file git/$path/$diff.sh
	git config --unset-all diff.openssl.$diff || true
	git config --add diff.openssl.$diff $SECRETS/$path/$diff.sh
done

# Append missing rules, keeping existing ones and their order.
if [ -f .gitattributes ]; then
	missing=$(grep -vxF -f .gitattributes "$SD/gitattributes" || true)
	if [ -n "$missing" ]; then
		[ -z "$(tail -c 1 .gitattributes)" ] || echo >> .gitattributes
		printf '%s\n' "$missing" >> .gitattributes
	fi
else
	cp "$SD/gitattributes" .gitattributes
fi

if git status --porcelain .gitattributes $SECRETS | grep -q '^[ ]*[^ ]'; then
	git add .gitattributes $SECRETS
	git commit -m init .gitattributes $SECRETS || true
fi

git ls-files -z --modified | while IFS= read -r -d '' f; do
	[ "$f" = .gitattributes ] || git checkout HEAD -- "$f"
done

# Rebuild the index so every file goes through the filters.
rm "$(git rev-parse --git-path index)"
git checkout HEAD -- .

if git status | grep modified; then
	if [ -z "$(git diff)" ]; then
		git commit -a -m "zero content changes"
		if git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
			git push
		else
			echo "No upstream branch, not pushing."
		fi
	else
		echo "Manually modified files present. Can't auto commit."
	fi
fi
