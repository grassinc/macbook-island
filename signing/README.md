# Local code-signing certificate

`Pill Local Dev` is a self-signed certificate in the login keychain, trusted for
code signing. `scripts/build-app.sh` uses it when present and falls back to
ad-hoc otherwise.

## Why it exists

An ad-hoc signature makes the app's TCC identity its **cdhash**, which changes on
every build. That silently invalidates Accessibility and Automation grants while
the app still appears ticked in System Settings — permission that looks granted
but is not. Signing with a stable certificate pins the identity to the
certificate instead:

    designated => identifier "com.pill.app" and certificate leaf = H"6813afb4...5756"

Verified identical across rebuilds.

## Recreating it

    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout pill.key -out pill.crt -config pillcert.cnf
    openssl pkcs12 -export -inkey pill.key -in pill.crt \
      -name "Pill Local Dev" -out pill.p12 -passout pass:pill
    security import pill.p12 -k ~/Library/Keychains/login.keychain-db \
      -P pill -T /usr/bin/codesign -A
    security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db pill.crt

The private key stays in the keychain and is deliberately NOT in this repo.
`pill.crt` is the public certificate only.

## Removing it

    security delete-certificate -c "Pill Local Dev"
