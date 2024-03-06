# git-openssl-secrets

## Description
Adds on-the-fly openssl encryption to a git repo.  
All files stored under `secrets` folder will be automatically encrypted on `stage` and decrypted on `checkout` using git [filters](https://git-scm.com/book/en/v2/Customizing-Git-Git-Attributes).    

## Setup
### Install
Clone this repo and setup salt and passwoird locations.  
Add the location of this cloned repo to shell's `PATH`.  


### Salt and Password
The `salt` and `password` used for encrypting and decrypting the secrets need to be stored in accessible to the trusted user, but not to others location.  
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

### Usage:
cd into a git repo with secrets and run [git-init-openssl-secrets.sh](git-init-openssl-secrets.sh).  
If you want other files encrypted as well, add them to `.gitattributes`.   

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
To keep git happy and have both versions of ssl compatible with one another we can backfill the `Salted__` header in the [clean filter](https://github.com/maxfortun/git-openssl-secrets/blob/bb4cc3a0bd12ecb9f30c438a57f5ce19057e3195/git/filter/openssl/clean.sh#L15-L19). 


