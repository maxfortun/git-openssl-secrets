# Sourced by the filters under /bin/sh, so keep this POSIX.
# Values are cached in the git dir, outside the working tree.
# Set GIT_FILTER_OPENSSL_CACHE=false to refresh them.

cache=$(git rev-parse --git-path openssl-secrets.cache 2>/dev/null) ||
	cache="${XDG_CACHE_HOME:-$HOME/.cache}/git-openssl-secrets.cache"

# Older versions cached next to this script, inside the working tree.
legacyCache=.secrets/git-setenv-openssl-secrets.sh.cache
if [ ! -f "$cache" ] && [ -f "$legacyCache" ] && ! git ls-files --error-unmatch "$legacyCache" >/dev/null 2>&1; then
	mv "$legacyCache" "$cache"
fi

if [ ! -f "$cache" ] || [ "$GIT_FILTER_OPENSSL_CACHE" = "false" ]; then
	VAULT_NAMESPACE=parentns/childns
	VAULT_ROLE=user
	VAULT_PREFIX=git-secrets/openssl

	if [ -z "$GIT_FILTER_OPENSSL_PASSWORD" ] || [ -z "$GIT_FILTER_OPENSSL_SALT" ]; then
		export VAULT_TOKEN="$(vault login -namespace=$VAULT_NAMESPACE -token-only -method=aws region=${AWS_STS_REGION:-$AWS_REGION} -format=table header_value=$VAULT_HOST role=$VAULT_ROLE || true)"
	fi

	password=${GIT_FILTER_OPENSSL_PASSWORD:-$(vault read -ns=$VAULT_NAMESPACE -field=value -format=table secret/$VAULT_PREFIX-password || true)}
	salt=${GIT_FILTER_OPENSSL_SALT:-$(vault read -ns=$VAULT_NAMESPACE -field=value -format=table secret/$VAULT_PREFIX-salt || true)}

	if [ -n "$salt" ] && [ -n "$password" ]; then
		mkdir -p "$(dirname "$cache")"
		(
			umask 077
			quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
			{
				echo "export GIT_FILTER_OPENSSL_PASSWORD=$(quote "$password")"
				echo "export GIT_FILTER_OPENSSL_SALT=$(quote "$salt")"
			} > "$cache"
		)
	fi
	unset salt password
fi

[ ! -f "$cache" ] || . "$cache"
