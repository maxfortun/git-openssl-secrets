cache=${BASH_SOURCE[0]}.cache

if [ ! -f $cache ] || [ "$GIT_FILTER_OPENSSL_CACHE" = "false" ]; then
	AWS=aws
	AWS_SSM_PREFIX=/git-secrets/openssl

	cat <<_EOT_ > $cache
export GIT_FILTER_OPENSSL_SALT=${GIT_FILTER_OPENSSL_SALT:-$($AWS --region $AWS_REGION --output text ssm get-parameter --with-decryption --name "$AWS_SSM_PREFIX-salt" --query 'Parameter.Value')}
export GIT_FILTER_OPENSSL_PASSWORD=${GIT_FILTER_OPENSSL_PASSWORD:-$($AWS --region $AWS_REGION --output text ssm get-parameter --with-decryption --name "$AWS_SSM_PREFIX-password" --query 'Parameter.Value')}
_EOT_

fi

. $cache

