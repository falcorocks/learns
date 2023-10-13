sudo cat <<EOF >> /etc/hosts
127.0.0.1 fulcio.sigstore.local
127.0.0.1 rekor.sigstore.local 
127.0.0.1 tuf.sigstore.local
127.0.0.1 registry.local # only needed for testing
EOF