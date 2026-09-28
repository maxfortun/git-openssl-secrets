#!/bin/bash
# Runs the test suite. Each test gets a fresh HOME, tool install and repos.
#
# Usage: test/run.sh [test-name...]
#   TEST_SHELLS  shells to run the filters with, "default" meaning their
#                #!/bin/sh shebang (default: "default dash bash", where available)
#   TEST_VERBOSE set to show the output of passing tests too

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=$ROOT/test/fixtures

# Must match the values test/fixtures were generated with.
SALT=00110a25deadbeef
PW=fixture-password

# ---------------------------------------------------------------- helpers

fail() { echo "FAIL: $*" >&2; exit 1; }

assert_eq() { # expected actual [message]
	[ "$1" = "$2" ] || fail "${3:-values differ}"$'\n'"  expected: $1"$'\n'"  actual:   $2"
}

assert_file_eq() { # expected-file actual-file
	cmp -s "$1" "$2" || fail "$2 differs from $1"
}

setup_env() {
	export HOME=$T/home
	export XDG_CONFIG_HOME=$HOME/.config
	export GIT_CONFIG_NOSYSTEM=1
	export TMPDIR=$T/tmp
	unset GIT_FILTER_OPENSSL_SALT GIT_FILTER_OPENSSL_PASSWORD GIT_FILTER_OPENSSL_PREFIX \
		GIT_FILTER_OPENSSL_CACHE GIT_FILTER_OPENSSL_DEBUG GIT_DIR GIT_WORK_TREE
	mkdir -p "$HOME/.config/git" "$TMPDIR"

	git config --global user.name test
	git config --global user.email test@example.com
	git config --global init.defaultBranch main
	git config --global commit.gpgsign false
	git config --global advice.detachedHead false
	git config --global protocol.file.allow always

	echo "$SALT" > "$HOME/.config/git/openssl-salt"
	echo "$PW" > "$HOME/.config/git/openssl-password"
	chmod 600 "$HOME/.config/git/openssl-"*

	TOOL=$T/tool
	mkdir -p "$TOOL"
	cp -R "$ROOT/git" "$ROOT/gitattributes" "$TOOL/"
	for f in "$ROOT"/git-*.sh; do
		[ -L "$f" ] || cp "$f" "$TOOL/"
	done
	ln -s git-setenv-openssl-secrets-fs.sh "$TOOL/git-setenv-openssl-secrets.sh"
}

# Points the filters at $FILTER_SH instead of their shebang.
use_shell() {
	[ "$FILTER_SH" = default ] && return
	git config filter.openssl.clean "$FILTER_SH .secrets/filter/openssl/clean.sh %f"
	git config filter.openssl.smudge "$FILTER_SH .secrets/filter/openssl/smudge.sh %f"
	git config diff.openssl.textconv "$FILTER_SH .secrets/diff/openssl/textconv.sh"
}

# new_repo <dir>: a repo with one commit, not yet initialized for secrets.
new_repo() {
	git init -q "$1"
	cd "$1"
	echo readme > README
	git add README
	git commit -qm readme
}

# init_repo <dir>: new_repo + git-init-openssl-secrets.sh.
init_repo() {
	new_repo "$1"
	"$TOOL/git-init-openssl-secrets.sh" > "$T/init.log" 2>&1 || { cat "$T/init.log"; fail "init failed"; }
	use_shell
}

# Decrypts a blob in the canonical format with nothing but openssl.
openssl_decrypt() {
	base64 -d | openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -pass pass:"$PW"
}

# Commits <blob-file> verbatim as <path>, then checks it out through the filters.
commit_raw_blob() {
	local sha
	sha=$(git hash-object -w --no-filters "$1")
	git update-index --add --cacheinfo "100644,$sha,$2"
	git commit -qm "raw $2"
	rm -f "$2"
	git checkout -- "$2"
}

# Runs the original clean.sh with shell $1 on stdin.
legacy_clean() {
	local d
	d=$(mktemp -d)
	cat > "$d/f"
	(cd "$d" && GIT_FILTER_OPENSSL_SALT=$SALT GIT_FILTER_OPENSSL_PASSWORD=$PW $1 "$ROOT/test/legacy/clean.sh" f)
	rm -rf "$d"
}

# ---------------------------------------------------------------- tests
# test_* run once per filter shell, once_* run once.

test_roundtrip() {
	init_repo "$T/repo"
	mkdir secrets
	printf 'top secret\nsecond line\n' > secrets/a
	git add secrets/a
	git commit -qm secret

	git cat-file blob HEAD:secrets/a > "$T/blob"
	grep -q 'top secret' "$T/blob" && fail "blob is plaintext"
	assert_eq "$(printf 'top secret\nsecond line')" "$(openssl_decrypt < "$T/blob")" "openssl can't decrypt blob"
	assert_eq "" "$(git status --porcelain)" "tree dirty after commit"

	git clone -q "$T/repo" "$T/clone"
	cd "$T/clone"
	"$TOOL/git-init-openssl-secrets.sh" > /dev/null 2>&1 || fail "init of clone failed"
	assert_file_eq "$T/repo/secrets/a" secrets/a
	assert_eq "" "$(git status --porcelain)" "clone dirty after init"
}

test_blob_is_deterministic_and_matches_legacy() {
	init_repo "$T/repo"
	mkdir secrets
	cp "$FIXTURES/plain" secrets/a
	git add secrets/a
	git cat-file blob :secrets/a > "$T/blob"
	# The original clean.sh got the header right under bash.
	assert_file_eq "$FIXTURES/legacy-bash.b64" "$T/blob"
}

test_reads_all_legacy_formats() {
	init_repo "$T/repo"
	mkdir secrets
	for f in "$FIXTURES"/*.b64; do
		name=$(basename "$f" .b64)
		commit_raw_blob "$f" "secrets/$name"
		assert_file_eq "$FIXTURES/plain" "secrets/$name"
		git cat-file --textconv "HEAD:secrets/$name" > "$T/textconv"
		assert_file_eq "$FIXTURES/plain" "$T/textconv"
	done
}

test_reads_blobs_from_legacy_clean_on_this_system() {
	init_repo "$T/repo"
	mkdir secrets
	for sh in sh dash bash; do
		command -v $sh > /dev/null || continue
		legacy_clean $sh < "$FIXTURES/plain" > "$T/$sh.b64"
		commit_raw_blob "$T/$sh.b64" "secrets/$sh"
		assert_file_eq "$FIXTURES/plain" "secrets/$sh"
	done
}

test_legacy_blobs_are_not_rewritten() {
	init_repo "$T/repo"
	mkdir secrets
	for f in "$FIXTURES"/*.b64; do
		name=$(basename "$f" .b64)
		commit_raw_blob "$f" "secrets/$name"
		before=$(git rev-parse ":secrets/$name")
		touch "secrets/$name"
		assert_eq "" "$(git status --porcelain)" "$name shows as modified"
		git add "secrets/$name"
		assert_eq "$before" "$(git rev-parse ":secrets/$name")" "$name blob rewritten"
	done
}

test_legacy_scripts_read_new_blobs() {
	init_repo "$T/repo"
	mkdir secrets
	cp "$FIXTURES/plain" secrets/a
	git add secrets/a
	git cat-file blob :secrets/a > "$T/blob"
	for sh in sh dash bash; do
		command -v $sh > /dev/null || continue
		GIT_FILTER_OPENSSL_SALT=$SALT GIT_FILTER_OPENSSL_PASSWORD=$PW $sh "$ROOT/test/legacy/smudge.sh" none < "$T/blob" > "$T/out"
		assert_file_eq "$FIXTURES/plain" "$T/out"
		GIT_FILTER_OPENSSL_SALT=$SALT GIT_FILTER_OPENSSL_PASSWORD=$PW $sh "$ROOT/test/legacy/textconv.sh" "$T/blob" > "$T/out"
		assert_file_eq "$FIXTURES/plain" "$T/out"
	done
}

test_branch_switch_updates_secrets() {
	init_repo "$T/repo"
	mkdir secrets
	echo v1 > secrets/a
	git add secrets/a
	git commit -qm v1
	git checkout -qb other
	echo v2 > secrets/a
	git commit -qam v2
	git checkout -q main
	assert_eq v1 "$(cat secrets/a)"
	git checkout -q other
	assert_eq v2 "$(cat secrets/a)"
}

test_encrypts_staged_content_not_worktree() {
	init_repo "$T/repo"
	mkdir secrets
	echo worktree > secrets/a
	sha=$(echo staged | git hash-object -w --path secrets/a --stdin)
	assert_eq staged "$(git cat-file blob "$sha" | openssl_decrypt)"
}

test_file_names_with_spaces() {
	init_repo "$T/repo"
	mkdir -p "secrets/sub dir"
	echo spaced > "secrets/sub dir/a b"
	git add secrets
	git commit -qm spaced
	git cat-file blob "HEAD:secrets/sub dir/a b" | grep -q spaced && fail "blob is plaintext"
	rm "secrets/sub dir/a b"
	git checkout -- "secrets/sub dir/a b"
	assert_eq spaced "$(cat "secrets/sub dir/a b")"
}

test_binary_and_large_files() {
	init_repo "$T/repo"
	mkdir secrets
	openssl rand 1048576 > secrets/big
	: > secrets/empty
	git add secrets
	git commit -qm big
	cp secrets/big "$T/big"
	rm secrets/big secrets/empty
	git checkout -- secrets
	assert_file_eq "$T/big" secrets/big
	[ -f secrets/empty ] && [ ! -s secrets/empty ] || fail "empty file not restored"
}

test_password_not_on_command_line() {
	mkdir "$T/bin"
	real=$(command -v openssl)
	printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$T/openssl.log" "$real" > "$T/bin/openssl"
	chmod +x "$T/bin/openssl"
	PATH=$T/bin:$PATH

	init_repo "$T/repo"
	mkdir secrets
	echo s > secrets/a
	git add secrets/a
	git commit -qm s
	rm secrets/a
	git checkout -- secrets/a
	grep -q ' enc ' "$T/openssl.log" 2>/dev/null || grep -q '^enc' "$T/openssl.log" || fail "openssl shim not used"
	grep -qF "$PW" "$T/openssl.log" && fail "password passed on the command line"
	true
}

test_no_temp_files_left() {
	init_repo "$T/repo"
	mkdir secrets
	echo s > secrets/a
	git add secrets/a
	git commit -qm s
	git diff HEAD~ > /dev/null
	rm secrets/a
	git checkout -- secrets/a
	assert_eq "" "$(ls -A "$TMPDIR")" "temp files left behind"
}

test_encrypts_when_tracking_lost() {
	init_repo "$T/repo"
	mkdir secrets
	echo one > secrets/a
	git add secrets/a
	git commit -qm one
	rm -rf .git/filter/openssl/tracking
	echo two > secrets/a
	git add secrets/a
	assert_eq two "$(git cat-file blob :secrets/a | openssl_decrypt)" "staged in plaintext"
}

test_missing_password() {
	init_repo "$T/repo"
	mkdir secrets
	echo s > secrets/a
	git add secrets/a
	git commit -qm s
	mv "$HOME/.config/git/openssl-password" "$T/"

	echo new > secrets/new
	git add secrets/new 2> "$T/err" && fail "staged without a password"
	grep -q 'GIT_FILTER_OPENSSL_PASSWORD' "$T/err" || fail "no helpful error: $(cat "$T/err")"

	rm secrets/a
	git checkout -- secrets/a 2> "$T/err"
	grep -q 'cannot decrypt' "$T/err" || fail "no warning: $(cat "$T/err")"
	assert_eq "$(git cat-file blob HEAD:secrets/a)" "$(cat secrets/a)" "encrypted content not checked out as is"
}

test_diff_shows_plaintext() {
	init_repo "$T/repo"
	mkdir secrets
	echo before > secrets/a
	git add secrets/a
	git commit -qm before
	echo after > secrets/a
	git diff > "$T/diff"
	grep -q '^-before' "$T/diff" && grep -q '^+after' "$T/diff" || fail "diff: $(cat "$T/diff")"
}

test_worktree() {
	init_repo "$T/repo"
	mkdir secrets
	echo wt > secrets/a
	git add secrets/a
	git commit -qm wt
	git worktree add -q "$T/wt" -b wt
	assert_eq wt "$(cat "$T/wt/secrets/a")"
	cd "$T/wt"
	echo changed > secrets/a
	git commit -qam changed
	assert_eq changed "$(git cat-file blob HEAD:secrets/a | openssl_decrypt)"
}

test_aws_setenv_caches_outside_worktree() {
	mkdir "$T/bin"
	cat > "$T/bin/aws" <<-_EOT_
		#!/bin/sh
		echo aws >> "$T/aws.log"
		case "\$*" in
			*openssl-salt*) echo $SALT ;;
			*openssl-password*) echo $PW ;;
		esac
	_EOT_
	chmod +x "$T/bin/aws"
	PATH=$T/bin:$PATH
	ln -sf git-setenv-openssl-secrets-aws.sh "$TOOL/git-setenv-openssl-secrets.sh"

	init_repo "$T/repo"
	mkdir secrets
	echo aws > secrets/a
	git add secrets/a
	git commit -qm aws
	assert_eq aws "$(git cat-file blob HEAD:secrets/a | openssl_decrypt)"

	[ -f .git/openssl-secrets.cache ] || fail "no cache in git dir"
	case $(ls -l .git/openssl-secrets.cache) in -rw-------*) ;; *) fail "cache is not private" ;; esac
	assert_eq "" "$(git status --porcelain --ignored)" "files left in worktree"
	calls=$(wc -l < "$T/aws.log")
	rm secrets/a
	git checkout -- secrets/a
	assert_eq "$calls" "$(wc -l < "$T/aws.log")" "cache not used"
}

test_aws_setenv_migrates_legacy_cache() {
	ln -sf git-setenv-openssl-secrets-aws.sh "$TOOL/git-setenv-openssl-secrets.sh"
	init_repo "$T/repo"
	printf 'export GIT_FILTER_OPENSSL_SALT=%s\nexport GIT_FILTER_OPENSSL_PASSWORD=%s\n' "$SALT" "$PW" \
		> .secrets/git-setenv-openssl-secrets.sh.cache
	mkdir secrets
	echo cached > secrets/a
	# No aws on PATH: only the migrated cache can supply the password.
	git add secrets/a
	assert_eq cached "$(git cat-file blob :secrets/a | openssl_decrypt)"
	[ ! -e .secrets/git-setenv-openssl-secrets.sh.cache ] || fail "legacy cache still in worktree"
	[ -f .git/openssl-secrets.cache ] || fail "cache not migrated"
}

once_init_encrypts_existing_plaintext_and_pushes() {
	git init -q --bare "$T/remote.git"
	new_repo "$T/repo"
	mkdir secrets
	echo plain > secrets/a
	git add secrets/a
	git commit -qm plaintext
	git remote add origin "$T/remote.git"
	git push -qu origin main

	"$TOOL/git-init-openssl-secrets.sh" > "$T/init.log" 2>&1 || { cat "$T/init.log"; fail "init failed"; }
	assert_eq plain "$(cat secrets/a)"
	assert_eq plain "$(git cat-file blob HEAD:secrets/a | openssl_decrypt)" "not encrypted"
	assert_eq "zero content changes" "$(git log -1 --format=%s)"
	assert_eq "$(git rev-parse HEAD)" "$(git -C "$T/remote.git" rev-parse main)" "not pushed"
}

once_init_without_upstream_does_not_fail() {
	new_repo "$T/repo"
	mkdir secrets
	echo plain > secrets/a
	git add secrets/a
	git commit -qm plaintext
	"$TOOL/git-init-openssl-secrets.sh" > "$T/init.log" 2>&1 || { cat "$T/init.log"; fail "init failed"; }
	assert_eq "zero content changes" "$(git log -1 --format=%s)"
}

once_init_merges_gitattributes() {
	new_repo "$T/repo"
	printf '*.bin binary\n*.txt text' > .gitattributes
	git add .gitattributes
	git commit -qm attrs
	"$TOOL/git-init-openssl-secrets.sh" > /dev/null 2>&1 || fail "init failed"
	assert_eq "$(printf '*.bin binary\n*.txt text\n'; cat "$TOOL/gitattributes")" "$(cat .gitattributes)"
	"$TOOL/git-init-openssl-secrets.sh" > /dev/null 2>&1 || fail "second init failed"
	assert_eq "$(printf '*.bin binary\n*.txt text\n'; cat "$TOOL/gitattributes")" "$(cat .gitattributes)" "rules duplicated"
	assert_eq "" "$(git status --porcelain)" "backup files left behind"
}

once_init_refuses_to_discard_changes() {
	init_repo "$T/repo"
	echo edited > README
	"$TOOL/git-init-openssl-secrets.sh" > /dev/null 2>&1 && fail "init ran with uncommitted changes"
	assert_eq edited "$(cat README)"
	"$TOOL/git-init-openssl-secrets.sh" --force > /dev/null 2>&1 || fail "init --force failed"
	assert_eq readme "$(cat README)"
}

once_init_rejects_non_repo() {
	mkdir "$T/plain"
	"$TOOL/git-init-openssl-secrets.sh" "$T/plain" > "$T/out" 2>&1 && fail "init accepted a non-repo"
	grep -q 'Not in a git directory' "$T/out" || fail "unexpected message: $(cat "$T/out")"
}

once_init_upgrades_pristine_scripts() {
	# A tool clone whose history has the original scripts, then the current ones.
	mkdir -p "$T/new"
	cp -R "$TOOL/." "$T/new/"
	cp "$ROOT/test/legacy/clean.sh" "$ROOT/test/legacy/smudge.sh" "$TOOL/git/filter/openssl/"
	cp "$ROOT/test/legacy/textconv.sh" "$TOOL/git/diff/openssl/"
	git -C "$TOOL" init -q
	git -C "$TOOL" add -A
	git -C "$TOOL" commit -qm old
	cp -R "$T/new/." "$TOOL/"
	git -C "$TOOL" add -A
	git -C "$TOOL" commit -qm new

	# A repo set up by the old version, with one script customized.
	new_repo "$T/repo"
	mkdir -p .secrets/filter/openssl .secrets/diff/openssl
	cp "$ROOT/test/legacy/clean.sh" "$ROOT/test/legacy/smudge.sh" .secrets/filter/openssl/
	cp "$ROOT/test/legacy/textconv.sh" .secrets/diff/openssl/
	echo "# custom" >> .secrets/diff/openssl/textconv.sh
	git add .secrets
	git commit -qm old

	"$TOOL/git-init-openssl-secrets.sh" > "$T/init.log" 2>&1 || { cat "$T/init.log"; fail "init failed"; }
	assert_file_eq "$TOOL/git/filter/openssl/clean.sh" .secrets/filter/openssl/clean.sh
	assert_file_eq "$TOOL/git/filter/openssl/smudge.sh" .secrets/filter/openssl/smudge.sh
	assert_file_eq "$TOOL/git/filter/openssl/common.sh" .secrets/filter/openssl/common.sh
	grep -q '# custom' .secrets/diff/openssl/textconv.sh || fail "customized script replaced"
	grep -q 'Keeping modified .secrets/diff/openssl/textconv.sh' "$T/init.log" || fail "no notice about kept script"

	"$TOOL/git-init-openssl-secrets.sh" --upgrade > /dev/null 2>&1 || fail "init --upgrade failed"
	assert_file_eq "$TOOL/git/diff/openssl/textconv.sh" .secrets/diff/openssl/textconv.sh
}

once_rm_history() {
	new_repo "$T/repo"
	mkdir leak
	echo x > "leak/pass word.txt"
	echo y > "leak/it's.txt"
	git add leak
	git commit -qm leak
	git mv "leak/pass word.txt" "leak/renamed.txt"
	git commit -qm rename
	echo keep > keep
	git add keep
	git commit -qm keep

	# Declining the push makes it exit 1.
	printf 'yes\nno\n' | GIT_RM_HISTORY_DELAY=0 "$TOOL/git-rm-history.sh" '^leak/' > "$T/out" 2>&1 && fail "push not declined"
	grep -q 'Aborted' "$T/out" || fail "$(cat "$T/out")"
	assert_eq "" "$(git log --branches --tags --format= --name-only | grep leak)" "leak still in history: $(cat "$T/out")"
	assert_eq keep "$(cat keep)"
	grep -q rotate "$T/out" || fail "no rotation advice"
}

# The filters with every openssl found, e.g. LibreSSL as macOS's /usr/bin/openssl,
# or those listed in TEST_OPENSSL_BINARIES. Only init insists on OpenSSL 3.
once_filters_work_with_other_openssl_versions() {
	binaries=${TEST_OPENSSL_BINARIES:-$( (type -ap openssl; echo /usr/bin/openssl) | awk '!seen[$0]++')}
	export GIT_FILTER_OPENSSL_SALT=$SALT GIT_FILTER_OPENSSL_PASSWORD=$PW
	for bin in $binaries; do
		[ -x "$bin" ] || continue
		version=$("$bin" version)
		mkdir -p "$T/bin"
		ln -sf "$bin" "$T/bin/openssl"
		(
			PATH=$T/bin:$PATH
			. "$ROOT/git/filter/openssl/common.sh"
			OPENSSL_SECRETS_TMP=$(mktemp -d)
			for f in "$FIXTURES"/*.b64; do
				openssl_secrets_decrypt "$f" "$T/out" || fail "$version: cannot decrypt $(basename "$f")"
				assert_file_eq "$FIXTURES/plain" "$T/out"
			done
			openssl_secrets_encrypt "$FIXTURES/plain" > "$T/enc"
			assert_file_eq "$FIXTURES/legacy-bash.b64" "$T/enc"
		)
		echo "ok with $version"
	done
}

# ---------------------------------------------------------------- runner

command -v openssl > /dev/null || { echo "openssl not found"; exit 1; }

shells=
for sh in ${TEST_SHELLS:-default dash bash}; do
	[ "$sh" = default ] || command -v "$sh" > /dev/null && shells+=" $sh"
done

all=$(declare -F | awk '{print $3}' | grep -E '^(test|once)_')
selected=${*:-$all}

# Init requires OpenSSL 3, so with an older one only the filters can be tested.
if ! openssl version | grep -Eq '^OpenSSL ([3-9]|[1-9][0-9])\.'; then
	echo "$(openssl version) is first on PATH, testing the filters only. Put OpenSSL 3 first to run everything."
	selected=once_filters_work_with_other_openssl_versions
fi

pass=0
failed=()
run() { # name shell
	T=$(mktemp -d "${TMPDIR:-/tmp}/openssl-secrets-test.XXXXXX")
	(
		set -e
		FILTER_SH=$2
		setup_env
		cd "$T"
		"$1"
	) > "$T.log" 2>&1
	if [ $? -eq 0 ]; then
		pass=$((pass + 1))
		echo "ok   $1 [$2]"
		[ -z "${TEST_VERBOSE:-}" ] || sed 's/^/     /' "$T.log"
	else
		failed+=("$1 [$2]")
		echo "FAIL $1 [$2]"
		sed 's/^/     /' "$T.log"
	fi
	rm -rf "$T" "$T.log"
}

for name in $selected; do
	case $name in
		once_*) run "$name" default ;;
		*) for sh in $shells; do run "$name" "$sh"; done ;;
	esac
done

echo
echo "$pass passed, ${#failed[@]} failed"
[ ${#failed[@]} -eq 0 ]
