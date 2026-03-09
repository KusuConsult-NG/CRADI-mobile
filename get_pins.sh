#!/bin/bash
DOMAIN=$1
openssl s_client -connect $DOMAIN:443 -servername $DOMAIN -showcerts </dev/null 2>/dev/null | awk '/-----BEGIN CERTIFICATE-----/{cert=""} {cert=cert $0 "\n"} /-----END CERTIFICATE-----/{print cert > "cert_" ++i ".pem"}'
for f in cert_*.pem; do
    if [ -f "$f" ]; then
        pin=$(openssl x509 -in "$f" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)
        subject=$(openssl x509 -in "$f" -noout -subject)
        issuer=$(openssl x509 -in "$f" -noout -issuer)
        echo "File: $f"
        echo "Subject: $subject"
        echo "Issuer: $issuer"
        echo "Pin: $pin"
        echo "------------------------"
    fi
done
rm -f cert_*.pem
