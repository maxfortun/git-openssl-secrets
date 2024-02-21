cache=${BASH_SOURCE[0]}.cache

if [ ! -f $cache ]; then
	VAULT_NAMESPACE=parentns/childns
	VAULT_ROLE=user
	VAULT_PREFIX=git-secrets/openssl

	( [ -z "$GIT_FILTER_OPENSSL_PASSWORD" ] || [ -z "$GIT_FILTER_OPENSSL_SALT" ] ) && IS_VAULT_REQUIRED=true
	if [ -n "$IS_VAULT_REQUIRED" ]; then
		export VAULT_TOKEN=$(vault login -namespace=$VAULT_NAMESPACE -token-only -method=aws region=${AWS_STS_REGION:-$AWS_REGION} -format=table header_value=$VAULT_HOST role=$VAULT_ROLE)
	fi


	cat <<_EOT_ > $cache
export GIT_FILTER_OPENSSL_PASSWORD=${GIT_FILTER_OPENSSL_PASSWORD:-$(vault read -ns=$VAULT_NAMESPACE -field=value -format=table secret/$VAULT_PREFIX-password)}
export GIT_FILTER_OPENSSL_SALT=${GIT_FILTER_OPENSSL_SALT:-$(vault read -ns=$VAULT_NAMESPACE -field=value -format=table secret/$VAULT_PREFIX-salt)}
_EOT_

fi

. $cache
