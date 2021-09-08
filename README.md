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
Store salt and password in `$HOME/.config/git/openssl-salt` and `$HOME/.config/git/openssl-password` respectively.  
If this is the first time you are generating them, you may use something like:
```
openssl rand -hex 8 > $HOME/.config/git/openssl-salt
openssl rand -hex 32 $HOME/.config/git/openssl-password

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

