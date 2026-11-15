# Shared by clean.sh, smudge.sh and textconv.sh. Sourced, not executed.
# Keep this POSIX sh: /bin/sh is bash on macOS but dash on Debian/Ubuntu.

OPENSSL_SECRETS_CIPHER="-aes-256-cbc -md sha512 -pbkdf2"

# The authenticated format (written once a repo is upgraded, see
# openssl_secrets_format) starts with this marker:
#   "GOS2HMAC" | nonce (8) | ciphertext | tag (32)
# nonce = HMAC-SHA256(nonce key, plaintext), first 8 bytes: deterministic, but
#         different for every content, and used as the PBKDF2 salt, so every
#         file and version gets its own key and IV.
# tag   = HMAC-SHA256(mac key, marker | nonce | ciphertext): checked before
#         decrypting, so a modified blob is refused.
# Both keys are SHA-256 of a label, the password and the salt.
OPENSSL_SECRETS_MAGIC=GOS2HMAC

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
	openssl_secrets_hex_bytes "$GIT_FILTER_OPENSSL_SALT"
}

# openssl_secrets_hex_bytes <hex>: writes the hex string as raw bytes.
openssl_secrets_hex_bytes() {
	_hex=$1
	while [ ${#_hex} -ge 2 ]; do
		_rest=${_hex#??}
		printf '%b' "\\0$(printf %o "0x${_hex%"$_rest"}")"
		_hex=$_rest
	done
	printf '%s' "$_hex"
}

# Lower-case hex of stdin.
openssl_secrets_hex() {
	od -An -v -tx1 | tr -d ' \n'
}

# SHA-256 of stdin, as hex. Secrets only ever go through stdin, never argv.
openssl_secrets_sha256() {
	openssl dgst -sha256 -binary | openssl_secrets_hex
}

# openssl_secrets_key <label>: hex key for <label>, from the password and salt.
openssl_secrets_key() {
	{
		printf 'git-openssl-secrets %s' "$1"
		printf '\000'
		printf '%s' "$GIT_FILTER_OPENSSL_PASSWORD"
		printf '\000'
		printf '%s' "$GIT_FILTER_OPENSSL_SALT"
	} | openssl_secrets_sha256
}

# openssl_secrets_pad <keyhex> <padbyte>: the 64 byte HMAC block of the key
# XORed with <padbyte> (decimal), as raw bytes.
openssl_secrets_pad() {
	_k=$1
	_i=0
	while [ $_i -lt 64 ]; do
		if [ ${#_k} -ge 2 ]; then
			_rest=${_k#??}
			_b=$((0x${_k%"$_rest"}))
			_k=$_rest
		else
			_b=0
		fi
		printf '%b' "\\0$(printf %o $((_b ^ $2)))"
		_i=$((_i + 1))
	done
}

# openssl_secrets_hmac <keyhex> <file>: HMAC-SHA256 of <file>, as hex.
openssl_secrets_hmac() {
	{ openssl_secrets_pad "$1" 54; cat "$2"; } | openssl dgst -sha256 -binary > "$OPENSSL_SECRETS_TMP/hmac.inner"
	{ openssl_secrets_pad "$1" 92; cat "$OPENSSL_SECRETS_TMP/hmac.inner"; } | openssl_secrets_sha256
}

# Which format clean.sh writes, from the committed .secrets/format: absent or
# "legacy" (readable by every version), or "authenticated" (since
# git-upgrade-openssl-secrets.sh). Anything else stops: these scripts are
# too old for this repo.
openssl_secrets_format() {
	OPENSSL_SECRETS_FORMAT=legacy
	if [ -f .secrets/format ]; then
		OPENSSL_SECRETS_FORMAT=$(tr -d ' \t\r\n' < .secrets/format)
	fi
	case $OPENSSL_SECRETS_FORMAT in
		legacy|authenticated) ;;
		*) echo "This repo's secrets use format \"$OPENSSL_SECRETS_FORMAT\", which these filter scripts don't know. Upgrade them: git-init-openssl-secrets.sh --upgrade" >&2
			return 1 ;;
	esac
}

# openssl_secrets_encrypt <in>
# Writes the base64 blob to stdout in $OPENSSL_SECRETS_FORMAT (default legacy).
# Deterministic, so unchanged files produce unchanged blobs.
openssl_secrets_encrypt() {
	if [ "${OPENSSL_SECRETS_FORMAT:-legacy}" = authenticated ]; then
		openssl_secrets_encrypt_authenticated "$1"
	else
		openssl_secrets_encrypt_legacy "$1"
	fi
}

# Legacy format: "Salted__", salt, ciphertext, with the configured salt for every file.
openssl_secrets_encrypt_legacy() {
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

# Authenticated format (see OPENSSL_SECRETS_MAGIC).
openssl_secrets_encrypt_authenticated() {
	_t=$OPENSSL_SECRETS_TMP
	_nonce=$(openssl_secrets_hmac "$(openssl_secrets_key nonce)" "$1" | cut -c1-16)
	openssl enc $OPENSSL_SECRETS_CIPHER -S "$_nonce" \
		-pass env:GIT_FILTER_OPENSSL_PASSWORD -in "$1" -out "$_t/enc"
	printf 'Salted__' > "$_t/magic"
	# OpenSSL 1.x writes the "Salted__" header itself, 3.x does not when given -S.
	if head -c 8 "$_t/enc" | cmp -s - "$_t/magic"; then
		tail -c +17 "$_t/enc" > "$_t/ct"
	else
		mv "$_t/enc" "$_t/ct"
	fi
	{ printf '%s' "$OPENSSL_SECRETS_MAGIC"; openssl_secrets_hex_bytes "$_nonce"; cat "$_t/ct"; } > "$_t/body"
	openssl_secrets_hex_bytes "$(openssl_secrets_hmac "$(openssl_secrets_key mac)" "$_t/body")" > "$_t/tag"
	cat "$_t/body" "$_t/tag" | base64 | tr -d '\n'
}

# openssl_secrets_decrypt_v2: decrypts the authenticated blob $_t/raw into
# $_out. Returns 2 if the tag doesn't match (wrong password or modified).
openssl_secrets_decrypt_v2() {
	[ -n "$GIT_FILTER_OPENSSL_PASSWORD" ] || return 2
	_len=$(($(wc -c < "$_t/raw")))
	[ "$_len" -ge $((8 + 8 + 16 + 32)) ] || return 2
	head -c $((_len - 32)) "$_t/raw" > "$_t/body"
	tail -c 32 "$_t/raw" | openssl_secrets_hex > "$_t/tag"
	openssl_secrets_hmac "$(openssl_secrets_key mac)" "$_t/body" > "$_t/tag.expected"
	cmp -s "$_t/tag" "$_t/tag.expected" || return 2
	# OpenSSL 1.x and LibreSSL ignore -S when decrypting, so give the nonce as a header.
	{ printf 'Salted__'; tail -c +9 "$_t/body"; } > "$_t/ct"
	openssl_secrets_decrypt_ct
}

# openssl_secrets_is_encrypted <in>: true if <in> is recognizably an encrypted
# blob (authenticated marker or a "Salted__" header), so that failing to
# decrypt it means it's broken rather than plaintext that looks like base64.
openssl_secrets_is_encrypted() {
	tr -d '\r\n' < "$1" | base64 -d 2>/dev/null | head -c 11 > "$OPENSSL_SECRETS_TMP/head" || return 1
	case $(cat "$OPENSSL_SECRETS_TMP/head") in
		"$OPENSSL_SECRETS_MAGIC"*|Salted__*|"-n Salted__") return 0 ;;
	esac
	return 1
}

# openssl_secrets_decrypt <in> <out>
# Returns 0 and writes the plaintext to <out> if <in> is an encrypted blob,
# 1 if <in> does not look encrypted, 2 if it does but cannot be decrypted
# (wrong password, modified, or an unauthenticated format while
# GIT_FILTER_OPENSSL_REQUIRE_MAC=true).
openssl_secrets_decrypt() {
	_t=$OPENSSL_SECRETS_TMP
	_out=$2

	tr -d '\r\n' < "$1" > "$_t/b64"
	[ -s "$_t/b64" ] || return 1
	LC_ALL=C grep -Eq '^[A-Za-z0-9+/]+={0,2}$' "$_t/b64" || return 1
	[ $(($(wc -c < "$_t/b64") % 4)) -eq 0 ] || return 1
	base64 -d < "$_t/b64" > "$_t/raw" 2>/dev/null || return 1

	printf '%s' "$OPENSSL_SECRETS_MAGIC" > "$_t/h0"
	if head -c 8 "$_t/raw" | cmp -s - "$_t/h0"; then
		openssl_secrets_decrypt_v2
		return
	fi
	# After migrating (GIT_FILTER_OPENSSL_REENCRYPT), refuse the older formats:
	# they have no integrity check.
	[ "${GIT_FILTER_OPENSSL_REQUIRE_MAC:-}" != "true" ] || return 2

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
					openssl_secrets_decrypt_salted
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
	openssl_secrets_decrypt_salted || return 1
}

# Decrypts bare ciphertext $_t/ct encrypted with the configured salt.
openssl_secrets_decrypt_salted() {
	# OpenSSL 1.x and LibreSSL ignore -S when decrypting and always expect a
	# header, so rebuild the standard one. It only fits an 8 byte salt.
	if [ $(($(wc -c < "$_t/s1"))) -eq 8 ]; then
		cat "$_t/h1" "$_t/s1" "$_t/ct" > "$_t/ct.salted"
		mv "$_t/ct.salted" "$_t/ct"
		openssl_secrets_decrypt_ct
	else
		openssl_secrets_decrypt_ct -S "$GIT_FILTER_OPENSSL_SALT"
	fi
}

# Decrypts $_t/ct into $_out. Extra args are passed to openssl.
openssl_secrets_decrypt_ct() {
	[ -n "$GIT_FILTER_OPENSSL_PASSWORD" ] || return 2
	_len=$(($(wc -c < "$_t/ct")))
	[ "$_len" -gt 0 ] && [ $((_len % 16)) -eq 0 ] || return 2
	openssl enc -d $OPENSSL_SECRETS_CIPHER "$@" \
		-pass env:GIT_FILTER_OPENSSL_PASSWORD -in "$_t/ct" -out "$_out" 2>/dev/null || return 2
}
