#!/bin/sh
# TODO for you: add ca.cert.pem to trust store and configure explicit trust
openssl req -x509 -newkey rsa:4096 -keyout ca.private.pem -out ca.cert.pem -sha256 -days 365 -nodes

for service_name in rekor fulcio tuf; do
    cat << EOF > $service_name.cert.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $service_name.sigstore.local
EOF

    openssl req -new -newkey rsa:4096 \
        -keyout $service_name.private.pem \
        -out $service_name.req.pem -nodes

    openssl x509 -req -in $service_name.req.pem \
        -days 365 -CA ca.cert.pem -CAkey ca.private.pem \
        -CAcreateserial -out $service_name.signed.cert.pem \
        -extfile $service_name.cert.ext

    kubectl create secret tls $service_name-tls \
        --namespace=$service_name-system \
        --cert=$service_name.signed.cert.pem \
        --key=$service_name.private.pem
done