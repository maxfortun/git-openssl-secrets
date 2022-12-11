. vault-functions.sh

VAULT_NAMESPACE=parentns/childns

( [ -z "$GIT_FILTER_OPENSSL_PASSWORD" ] || [ -z "$GIT_FILTER_OPENSSL_SALT" ] ) && IS_VAULT_REQUIRED=true
[ -z "$IS_VAULT_REQUIRED" ] || vault-login-aws $VAULT_NAMESPACE user

VAULT_PREFIX=git-secrets/openssl

export GIT_FILTER_OPENSSL_PASSWORD=${GIT_FILTER_OPENSSL_PASSWORD:-$(vault-read $VAULT_PREFIX-password)}
export GIT_FILTER_OPENSSL_SALT=${GIT_FILTER_OPENSSL_SALT:-$(vault-read $VAULT_PREFIX-salt)}

