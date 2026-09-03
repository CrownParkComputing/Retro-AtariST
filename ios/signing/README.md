# Signing material, encrypted

Nothing is here yet. When the App Store record and its provisioning profile
exist, four encrypted blobs live in this directory:

    dist.p12.enc                 certificate and private key
    profile.mobileprovision.enc  the App Store profile for this bundle id
    asc_key.p8.enc               App Store Connect API key
    signing.env.enc              CERT_PASSWORD, ASC_KEY_ID, ASC_ISSUER_ID

AES-256-CBC, PBKDF2 at 600,000 iterations, all four under one passphrase.

## The one secret

CI needs a single repository secret, `SIGNING_PASSPHRASE`, and decrypts all
four with it. Without it the `ios-release` job does nothing and the unsigned
simulator build still runs, so a broken tree still fails loudly.

**The passphrase never goes in this repository.** Encrypted files stored beside
their passphrase are plaintext with extra steps.

## Creating them

    export PASS='<a passphrase you generate>'
    enc() { openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
              -in "$1" -out "ios/signing/$2" -pass env:PASS; }
    enc dist.p12                     dist.p12.enc
    enc RetroAtariST.mobileprovision profile.mobileprovision.enc
    enc AuthKey_XXXXXXXXXX.p8        asc_key.p8.enc
    printf 'CERT_PASSWORD=%s\nASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' ... > /tmp/env
    enc /tmp/env                     signing.env.enc

Verify every blob decrypts byte-identical before committing, and re-encrypt
**all four together** when rotating: a half-rotated set fails in CI at
`security import` with a message about the password, which reads like a broken
certificate and is not one.

## If the passphrase leaks

Revoke the certificate, issue a new one, re-encrypt under a new passphrase. A
leaked distribution certificate lets anyone sign and upload as this developer.
