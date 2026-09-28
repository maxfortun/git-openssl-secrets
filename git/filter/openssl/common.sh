# Shared by clean.sh, smudge.sh and textconv.sh. Sourced, not executed.
# Keep this POSIX sh: /bin/sh is bash on macOS but dash on Debian/Ubuntu.

OPENSSL_SECRETS_CIPHER="-aes-256-cbc -md sha512 -pbkdf2"

# Loads GIT_FILTER_OPENSSL_SALT and GIT_FILTER_OPENSSL_PASSWORD.
# $1 is the .secrets dir the calling script is installed in.
openssl_secrets_setenv() {
	if [ -f .secrets/git-setenv-openssl-secrets.sh ]; then
		. ./.secrets/git-setenv-openssl-secrets.sh
	elif [ -f "$1/git-setenv-openssl-secrets.sh" ]; then
		. "$1/git-setenv-openssl-secrets.sh"
	fi
	# Exported so openssl reads the password with -pass env: rather than from argv.
	export GIT_FILTER_OPENSSL_SALT GIT_FILTER_OPENSSL_PASSWORD
}

# Creates a private scratch dir, removed on exit.
openssl_secrets_mktemp() {
	umask 077
	OPENSSL_SECRETS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/git-openssl-secrets.XXXXXX")
	trap 'rm -rf "$OPENSSL_SECRETS_TMP"' EXIT
	trap 'exit 1' HUP INT TERM
}

# Writes the hex salt as raw bytes.
openssl_secrets_salt_bytes() {
	_hex=$GIT_FILTER_OPENSSL_SALT
	while [ ${#_hex} -ge 2 ]; do
		_rest=${_hex#??}
		printf '%b' "\\0$(printf %o "0x${_hex%"$_rest"}")"
		_hex=$_rest
	done
	printf '%s' "$_hex"
}

# openssl_secrets_encrypt <in>
# Writes the base64 blob to stdout: "Salted__", salt, ciphertext. Deterministic,
# so unchanged files produce unchanged blobs.
openssl_secrets_encrypt() {
	_t=$OPENSSL_SECRETS_TMP
	openssl enc $OPENSSL_SECRETS_CIPHER -S "$GIT_FILTER_OPENSSL_SALT" \
		-pass env:GIT_FILTER_OPENSSL_PASSWORD -in "$1" -out "$_t/enc"
	printf 'Salted__' > "$_t/magic"
	# OpenSSL 1.x writes the header itself, 3.x does not when given -S.
	if head -c 8 "$_t/enc" | cmp -s - "$_t/magic"; then
		cat "$_t/enc"
	else
		cat "$_t/magic"
		openssl_secrets_salt_bytes
		cat "$_t/enc"
	fi | base64 | tr -d '\n'
}

# openssl_secrets_decrypt <in> <out>
# Returns 0 and writes the plaintext to <out> if <in> is an encrypted blob,
# 1 if <in> does not look encrypted, 2 if it does but cannot be decrypted.
openssl_secrets_decrypt() {
	_t=$OPENSSL_SECRETS_TMP
	_out=$2

	tr -d '\r\n' < "$1" > "$_t/b64"
	[ -s "$_t/b64" ] || return 1
	LC_ALL=C grep -Eq '^[A-Za-z0-9+/]+={0,2}$' "$_t/b64" || return 1
	[ $(($(wc -c < "$_t/b64") % 4)) -eq 0 ] || return 1
	base64 -d < "$_t/b64" > "$_t/raw" 2>/dev/null || return 1

	printf 'Salted__' > "$_t/h1"

	if [ -n "$GIT_FILTER_OPENSSL_SALT" ]; then
		# Headers written by every version of clean.sh. Older ones built the header
		# with `echo -n` and `echo -ne "\x.."`, which macOS sh and dash don't
		# support, so "-n", "-ne " and newlines, or escapes left as literal
		# text, ended up in the blob.
		printf '%s\n' '-n Salted__' > "$_t/h2"
		openssl_secrets_salt_bytes > "$_t/s1"
		{ printf '%s' '-ne '; cat "$_t/s1"; echo; } > "$_t/s2"
		printf '%s\n' "-ne $(printf '%s' "$GIT_FILTER_OPENSSL_SALT" | sed -e 's/../\\x&/g')" > "$_t/s3"

		for _h in h1 h2; do
			for _s in s1 s2 s3; do
				cat "$_t/$_h" "$_t/$_s" > "$_t/prefix"
				_n=$(($(wc -c < "$_t/prefix")))
				if head -c "$_n" "$_t/raw" | cmp -s - "$_t/prefix"; then
					tail -c +$((_n + 1)) "$_t/raw" > "$_t/ct"
					openssl_secrets_decrypt_ct -S "$GIT_FILTER_OPENSSL_SALT"
					return
				fi
			done
		done
	fi

	# Standard header carrying its own salt, e.g. from OpenSSL 1.x.
	if head -c 8 "$_t/raw" | cmp -s - "$_t/h1"; then
		cp "$_t/raw" "$_t/ct"
		openssl_secrets_decrypt_ct
		return
	fi

	# Legacy: bare ciphertext encrypted with the configured salt.
	[ -n "$GIT_FILTER_OPENSSL_SALT" ] || return 1
	cp "$_t/raw" "$_t/ct"
	openssl_secrets_decrypt_ct -S "$GIT_FILTER_OPENSSL_SALT" || return 1
}

# Decrypts $_t/ct into $_out. Extra args are passed to openssl.
openssl_secrets_decrypt_ct() {
	[ -n "$GIT_FILTER_OPENSSL_PASSWORD" ] || return 2
	_len=$(($(wc -c < "$_t/ct")))
	[ "$_len" -gt 0 ] && [ $((_len % 16)) -eq 0 ] || return 2
	openssl enc -d $OPENSSL_SECRETS_CIPHER "$@" \
		-pass env:GIT_FILTER_OPENSSL_PASSWORD -in "$_t/ct" -out "$_out" 2>/dev/null || return 2
}
