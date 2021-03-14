# git-openssl-secrets

Adds on-the-fly openssl encryption to a git repo.  
All files stored under `secrets` folder will be automatically encrypted on `stage` and decrypted on `checkout` using git [filters](https://git-scm.com/book/en/v2/Customizing-Git-Git-Attributes).    

To enable this feature, clone this repo and run [init-openssl-secrets.sh](init-openssl-secrets.sh) from within repo directory where you want the secrets preserved.  
You may need to do a `git checkout secrets/` if you just cloned a repo that already has secrets.  
If you want other files encrypted as well, add them to `.gitattributes`.   

The `salt` and `password` used for encrypting and decrypting the secrets are stored in `~/.config/git/openssl-salt` and `~/.config/git/openssl-password` respectively.  

Do not EVER expose these files to anyone you do not want to have access to your secrets.  

On the other hand if you are collaborating with someone, they will need these to be able to decrypt your secrets.  
