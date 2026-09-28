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
	AWS=aws
	AWS_SSM_PREFIX=/git-secrets/openssl

	salt=${GIT_FILTER_OPENSSL_SALT:-$($AWS ${AWS_REGION:+--region "$AWS_REGION"} --output text ssm get-parameter --with-decryption --name "$AWS_SSM_PREFIX-salt" --query 'Parameter.Value' || true)}
	password=${GIT_FILTER_OPENSSL_PASSWORD:-$($AWS ${AWS_REGION:+--region "$AWS_REGION"} --output text ssm get-parameter --with-decryption --name "$AWS_SSM_PREFIX-password" --query 'Parameter.Value' || true)}

	if [ -n "$salt" ] && [ -n "$password" ]; then
		mkdir -p "$(dirname "$cache")"
		(
			umask 077
			quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
			{
				echo "export GIT_FILTER_OPENSSL_SALT=$(quote "$salt")"
				echo "export GIT_FILTER_OPENSSL_PASSWORD=$(quote "$password")"
			} > "$cache"
		)
	fi
	unset salt password
fi

[ ! -f "$cache" ] || . "$cache"
