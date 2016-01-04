#!/bin/bash
set -e
set -u

if [[ $# != 2 ]]; then
    cat <<EOF
Usage:
  init-yubikey.sh outdirectory /SUBJECT/LINE/HERE/

Example subject line:

/C=US/ST=CA/L=Santa Cruz/O=SeaVaske/OU=Genomics/CN=Charles Vaske/emailAddress=charlie@example.com/

WARNING: this stores a private key, and unless the environment
variable ENCRYPT_PASSPHRASE is set, it will be written in clear text!

This generates auth, sign, and encrypt keys in slots 9a, 9c, and 9d
respectively.

The following files are placed in the output directory:

auth.pubkey
auth.selfsign.crt
auth.ssh.pub -- OpenSSH format public key
auth.csr

sign.pubkey
sign.selfsign.crt
sign.csr

encrypt.private.key -- passphrase protected by env. var ENCRYPT_PASSPHRASE
encrypt.selfsign.crt -- contains public key as well
encrypt.csr

The certificates in *.selfsign.crt are onto the key. If you wish to
get your certs signed, you can use the *.csr files, and then reimport
them to the corresponding key slots.

For key escrow, save encrypt.private.key securely.

EOF
    exit 2
fi

O=$1
SUBJECT=$2
PIN='-P 123456'

umask 077

mkdir -p $O

if ls -ld $O | cut -c 5-10 | grep -qe '[^-]'; then
    echo Directory $O has group and other permissions set
    exit 3
fi

echo
echo GENERATING authentication key
yubico-piv-tool -a verify-pin $PIN -a generate -s 9a -o $O/auth.pubkey
yubico-piv-tool -a verify-pin $PIN -a request-certificate -s 9a -o $O/auth.csr -i $O/auth.pubkey -S "$SUBJECT"
yubico-piv-tool -a verify-pin $PIN -a selfsign-certificate -s 9a -o $O/auth.selfsign.crt -i $O/auth.pubkey -S "$SUBJECT"
yubico-piv-tool -a verify-pin $PIN -a import-certificate -s 9a -i $O/auth.selfsign.crt
ssh-keygen -D /Library/OpenSC/lib/opensc-pkcs11.so -e | head -1 > $O/auth.ssh.pub

echo
echo GENERATING signing key
yubico-piv-tool -a verify-pin $PIN -a generate -s 9c -o $O/sign.pubkey
yubico-piv-tool -a verify-pin $PIN -a request-certificate -s 9c -o $O/sign.csr -i $O/sign.pubkey -S "$SUBJECT"
yubico-piv-tool -a verify-pin $PIN -a selfsign-certificate -s 9c -S "$SUBJECT" -i $O/sign.pubkey  -o $O/sign.selfsign.crt
yubico-piv-tool -a verify-pin $PIN -a import-certificate -s 9c -i $O/sign.selfsign.crt

echo
echo GENERATING encryption key
openssl req -out $O/encrypt.csr -passout env:ENCRYPT_PASSPHRASE -keyout $O/encrypt.key \
    -new -newkey rsa:2048 -sha256 -subj "$SUBJECT" -keyform pem \
    -pubkey

yubico-piv-tool -a verify-pin $PIN -a import-key -s 9d -i $O/encrypt.key -p "$ENCRYPT_PASSPHRASE"
yubico-piv-tool -a verify-pin $PIN -a selfsign-certificate -s 9d -S "$SUBJECT" -i $O/encrypt.csr -o $O/encrypt.selfsign.crt
yubico-piv-tool -a verify-pin $PIN -a import-certificate -s 9d -i $O/encrypt.selfsign.crt

### To sign these with a CA that has the key on the yubikey, do:
# brew install engine_pkcs11
# then in openssl interactive:
#  engine dynamic -pre SO_PATH:/Users/cvaske/homebrew/lib/engines/engine_pkcs11.so -pre ID:pkcs11 -pre NO_VCHECK:1 -pre LIST_ADD:1 -pre LOAD -pre MODULE_PATH:/Library/OpenSC/lib/opensc-pkcs11.so -pre VERBOSE
#  x509 -engine pkcs11 -CAkeyform engine -CAkey slot_1-id_2 -sha256 -CA sign.crt -req -passin pass:123456 -in encrypt.csr -out encrypt.crt -set_serial 1

# This is a weird bit here
# openssl pkcs12 -export  -out encrypt.pfx -inkey encrypt.key -in encrypt.crt -certfile sign.crt


# LEARN THE GPG KEYS:
# echo providers opensc > ~/.gnupg/gnupg-pkcs11-scd.conf
# echo provider-opensc-library /Library/OpenSC/lib/opensc-pkcs11.so  >> ~/.gnupg/gnupg-pkcs11-scd.conf
# echo SCD LEARN \
#     | gpg-agent --server gpg-connect-agent 2>1 \
#     | grep KEY-FRIEDNLY \
#     | cut -f 3 -d' ' \
#     | sed -e '1s/^/openpgp-auth /' -e '2s/^/openpgp-sign /' -e '3s/^/openpgp-encr /' \
#     >> ~/.gnupg/gnupg-pkcs11-scd.conf
# echo emulate-openpgp >> ~/.gnupg/gnupg-pkcs11-scd.conf
