# git-openssl-secrets

## Description
Adds on-the-fly openssl encryption to a git repo.  
All files stored under `secrets` folder will be automatically encrypted on `stage` and decrypted on `checkout` using git [filters](https://git-scm.com/book/en/v2/Customizing-Git-Git-Attributes).    

## Setup
### Install
Clone this repo and set up salt and password locations.  
Add the location of this cloned repo to shell's `PATH`.  


### Salt and Password
The `salt` and `password` used for encrypting and decrypting the secrets need to be stored in a location accessible to the trusted user, but not to others.  
There are many mechanisms to achieve that. You can use a file system with restricted permissions, a secrets manager, etc...  

> Do not EVER expose these to anyone you do not want to have access to your secrets.  

On the other hand if you are collaborating with someone, they will need these to be able to decrypt your secrets.  

#### File system
Store salt and password in `${GIT_FILTER_OPENSSL_PREFIX}salt` and `${GIT_FILTER_OPENSSL_PREFIX}password` respectively.  
If this is the first time you are generating them, you may use something like:  
`GIT_FILTER_OPENSSL_PREFIX` defaults to `$HOME/.config/git/openssl-`  

```
openssl rand -hex 8 > $HOME/.config/git/openssl-salt
openssl rand -hex 32 > $HOME/.config/git/openssl-password
```

Secure these files from prying eyes:  
```
chmod 0600 $HOME/.config/git/openssl-salt $HOME/.config/git/openssl-password
```  

Set the file system as your salt and password store:  
```
ln -s git-setenv-openssl-secrets-fs.sh git-setenv-openssl-secrets.sh
```  

#### AWS SSM and Vault
[git-setenv-openssl-secrets-aws.sh](git-setenv-openssl-secrets-aws.sh) and [git-setenv-openssl-secrets-vault.sh](git-setenv-openssl-secrets-vault.sh) fetch the salt and password from AWS SSM Parameter Store and HashiCorp Vault. Edit the parameter names at the top, then link one as `git-setenv-openssl-secrets.sh`.  
The fetched values are cached, readable only by you, in `.git/openssl-secrets.cache`. Set `GIT_FILTER_OPENSSL_CACHE=false` to refresh them.  
Older versions cached them in `.secrets/git-setenv-openssl-secrets.sh.cache`, inside the working tree. That file is moved into `.git` automatically. If it was ever committed, remove it with `git-rm-history.sh` and rotate the salt and password.  

### Usage:
cd into a git repo with secrets and run [git-init-openssl-secrets.sh](git-init-openssl-secrets.sh).  
The filter scripts are copied into the repo's `.secrets` folder, which is committed so collaborators get them too. The encrypted files themselves go in `secrets`.  
If you want other files encrypted as well, add them to `.gitattributes`.   

```
git-init-openssl-secrets.sh [--upgrade] [--force] [dir]
```
Init refuses to run when tracked files have uncommitted changes, since it re-checks out the whole tree. `--force` runs anyway and discards them.  
If `.secrets/git-setenv-openssl-secrets.sh.cache` from an older version is committed, init warns you.  

### Upgrading
Pull this repo and rerun `git-init-openssl-secrets.sh` in each repo that uses it.  
Scripts in `.secrets` that match a version from this repo's history are replaced. Scripts you customized are kept, with a notice; `--upgrade` replaces them too.  
Everything already committed still decrypts, and unchanged files keep their existing blobs, so upgrading causes no spurious diffs. Collaborators still on older versions can decrypt files written by the new one.  

Set `GIT_FILTER_OPENSSL_DEBUG=true` to trace the filters.  

### Compatibility note
When mixing older and newer openssl versions, like 1.x and 3.x, the defaults in these versions are different, and should not be relied on.  
Specify parameters like md and salt explicitly.  
To find each versions default md, run on different systems:
```
touch testfile
openssl dgst testfile
```
The output's first token will be the default md used. On my systems it is MD5 for 1.0.2k, and SHA256 for 3.0.8.  

Another thing to keep in mind is that openssl 1.x will write a `Salted__` header in the encrypted content, while openssl 3.x will not.  
To keep git happy and have both versions of ssl compatible with one another the [clean filter](git/filter/openssl/common.sh) backfills the `Salted__` header.  

Earlier versions of the clean filter wrote a corrupted header when `/bin/sh` was macOS's sh or dash, whose `echo` doesn't support `-n`/`-e`. Those files could not be decrypted. They now decrypt, and are rewritten in the correct format the next time they change.  

The password is passed to openssl through the environment rather than the command line, so other local users can't see it in `ps`.  

### Removing accidentally committed unencrypted files
```
git-rm-history.sh <pattern>
```
Removes every path in history that matches the grep pattern, then offers to force-push. Rewriting history does not revoke copies others already have, so rotate any secret that was pushed.  

### Tests
```
test/run.sh [test-name...]
```
Requires git and OpenSSL 3 or newer first on `PATH`. The filter tests run with `/bin/sh`, `dash` and `bash`, whichever are installed. `test/fixtures` holds blobs written by the original scripts under each shell, and `test/legacy` holds the original scripts themselves, to check compatibility in both directions.  


