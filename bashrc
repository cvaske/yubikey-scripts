alias insert-ssh-card='ssh-add -s /Library/OpenSC/lib/opensc-pkcs11.so'
alias remove-ssh-card='ssh-add -e /Library/OpenSC/lib/opensc-pkcs11.so; gpg-connect-agent "SCD KILLSCD" "SCD BYE" /bye'
