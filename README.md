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
Everything already committed still decrypts, and unchanged files keep their existing blobs, so upgrading causes no spurious diffs. Collaborators still on older versions can decrypt files written by the new one, as long as the repo stays in the legacy format; see Format and integrity.  

Set `GIT_FILTER_OPENSSL_DEBUG=true` to trace the filters.  

### Format and integrity
Repos start in the **legacy** format, which every version of these scripts reads. `git-upgrade-openssl-secrets.sh` switches a repo to the **authenticated** format, recorded in the committed `.secrets/format`. Until it is run, nothing changes: the filters never switch formats on their own.  

The authenticated format: `GOS2HMAC` | nonce (8 bytes) | AES-256-CBC ciphertext | HMAC-SHA256 tag (32 bytes), base64 encoded.  
- The nonce is an HMAC of the file's content, used as the PBKDF2 salt. Output stays deterministic (unchanged files give unchanged blobs), but every file and every version gets its own key and IV. The legacy format uses the configured salt for everything, so all files share one key and IV, and files with the same beginning have the same first ciphertext blocks.  
- The tag covers everything before it and is checked before decrypting, so a modified blob is refused (left encrypted, with a warning) instead of decrypting to altered content.  
- The HMAC keys are SHA-256 of a label, the password and the salt. Secrets only go through stdin and environment variables, never command-line arguments.  
- Recovery without these scripts: drop the first 8 and last 32 bytes, prefix `Salted__`, and decrypt with `openssl enc -d -aes-256-cbc -md sha512 -pbkdf2` (no integrity check that way).  

#### Upgrading a repo
1. `git-init-openssl-secrets.sh --upgrade`, then commit and push the new `.secrets` scripts, so everyone has scripts that read the new format before any blob uses it. The original scripts (before `common.sh`) can't read it and would write garbage into the working tree.  
2. `git-openssl-secrets-status.sh` lists files stored in plaintext or the legacy format.  
3. `git-upgrade-openssl-secrets.sh` - stops without changing anything unless tracked files are committed, the `.secrets` scripts are this version and committed, and **every encrypted file decrypts**. It then writes `.secrets/format`, re-encrypts every file (plaintext ones included) and checks that each decrypts to exactly what it was; otherwise it puts everything back. The result is staged for you to review and commit.  
4. Plaintext found by `git-openssl-secrets-status.sh --all` in the history stays readable to anyone with the repo: remove it with `git-rm-history.sh` and change the secret.  
5. Optionally, `GIT_FILTER_OPENSSL_REQUIRE_MAC=true` refuses the legacy format from then on.  

Hard stops, in every format:  
- A file whose stored version can't be decrypted (wrong password, modified, newer format) is never overwritten: staging an edit to it fails instead.  
- A `.secrets/format` these scripts don't know (written by a newer version) stops staging until the scripts are upgraded.  

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

The filters work with OpenSSL 1.1.1, OpenSSL 3 and LibreSSL 3, and all of them read and write identical files; `test/run.sh` checks every openssl it finds. OpenSSL 1.0.2 and older lack `-pbkdf2` and can't be used. Only `git-init-openssl-secrets.sh` insists on OpenSSL 3.  

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


