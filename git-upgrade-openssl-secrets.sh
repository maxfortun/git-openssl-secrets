#!/bin/bash -e
# Switches a repo to the authenticated format (see README, Format and
# integrity) and re-encrypts its secrets. Stops without changing anything
# unless it is safe:
#   - tracked files have no uncommitted changes
#   - the repo's .secrets scripts are this version, and committed (so every
#     collaborator who gets the new blobs also has scripts that read them)
#   - every encrypted file decrypts
# After re-encrypting, each file must decrypt to exactly what it was before,
# otherwise everything is put back. The result is staged, not committed.
#
# Usage: git-upgrade-openssl-secrets.sh [dir]

SD=$(cd "$(dirname "$0")" && pwd)

stop() { echo "Not upgrading: $*" >&2; exit 1; }

repo=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || stop "not in a git repo"
cd "$repo"

git rev-parse -q --verify HEAD > /dev/null || stop "the repo has no commits yet"
git diff --quiet HEAD -- . || stop "tracked files have uncommitted changes; commit or stash them first"

# The repo's filter scripts must be this version and committed.
for f in filter/openssl/common.sh filter/openssl/clean.sh filter/openssl/smudge.sh diff/openssl/textconv.sh; do
	cmp -s "$SD/git/$f" ".secrets/$f" ||
		stop ".secrets/$f is not this version. Run git-init-openssl-secrets.sh --upgrade, commit and push it, then rerun."
done
case $(git config filter.openssl.clean) in *.secrets/filter/openssl/clean.sh*) false ;; esac &&
	stop "the openssl filter isn't set up here. Run git-init-openssl-secrets.sh first."

. "$SD/git/filter/openssl/common.sh"
openssl_secrets_setenv "$SD"
openssl_secrets_mktemp
tmp=$OPENSSL_SECRETS_TMP
[ -n "$GIT_FILTER_OPENSSL_SALT" ] && [ -n "$GIT_FILTER_OPENSSL_PASSWORD" ] || stop "salt and password not available"
openssl_secrets_format || stop "unknown format in .secrets/format"
unset GIT_FILTER_OPENSSL_REQUIRE_MAC

# Every file under the filter, and its plaintext now.
git ls-files -z | while IFS= read -r -d '' path; do
	[ "$(git check-attr filter -- "$path")" = "$path: filter: openssl" ] && printf '%s\0' "$path"
done > "$tmp/paths" || true
mkdir "$tmp/before"
broken=0
n=0
while IFS= read -r -d '' path; do
	n=$((n + 1))
	git cat-file blob ":$path" > "$tmp/blob"
	openssl_secrets_decrypt "$tmp/blob" "$tmp/before/$n" && rc=0 || rc=$?
	if [ $rc -eq 2 ] && openssl_secrets_is_encrypted "$tmp/blob"; then
		echo "can't decrypt: $path" >&2
		broken=$((broken + 1))
	elif [ $rc -ne 0 ]; then
		cp "$tmp/blob" "$tmp/before/$n" # stored in plaintext: it gets encrypted
	fi
done < "$tmp/paths"
[ $broken -eq 0 ] || stop "$broken file(s) can't be decrypted. Fix or remove them first; nothing was changed."
[ $n -gt 0 ] || stop "no files use the openssl filter"

hadFormat=false
[ -f .secrets/format ] && hadFormat=true && cp .secrets/format "$tmp/format.before"
printf 'authenticated\n' > .secrets/format

restore() {
	if $hadFormat; then cp "$tmp/format.before" .secrets/format; else rm -f .secrets/format; fi
	git reset -q -- .secrets/format
	xargs -0 git reset -q -- < "$tmp/paths"
	stop "$1; everything was put back"
}

git add .secrets/format
xargs -0 env GIT_FILTER_OPENSSL_REENCRYPT=true git add --renormalize -- < "$tmp/paths" || restore "re-encrypting failed"

# Each file must now be authenticated and decrypt to what it was.
OPENSSL_SECRETS_FORMAT=authenticated
n=0
while IFS= read -r -d '' path; do
	n=$((n + 1))
	git cat-file blob ":$path" > "$tmp/blob"
	[ "$(tr -d '\r\n' < "$tmp/blob" | base64 -d 2>/dev/null | head -c 8)" = "$OPENSSL_SECRETS_MAGIC" ] ||
		restore "$path was not re-encrypted"
	openssl_secrets_decrypt "$tmp/blob" "$tmp/after" || restore "$path doesn't decrypt after re-encrypting"
	cmp -s "$tmp/after" "$tmp/before/$n" || restore "$path decrypts to different content after re-encrypting"
done < "$tmp/paths"

echo "Re-encrypted $n file(s) in the authenticated format and checked each one. Review and commit:"
echo "  git diff --cached --stat"
echo "  git commit -m 'Encrypt secrets in the authenticated format'"
