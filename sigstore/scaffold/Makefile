repo:
	helm repo add sigstore https://sigstore.github.io/helm-charts
	helm repo update

dns:
	./dns.sh

install:
	helm upgrade -i local-sigstore sigstore/scaffold --version=0.6.32 --values=values.yaml
	sleep 5
	kubectl rollout status deployment local-sigstore-tuf-tuf -n tuf-system --timeout=120s

tls:
	./tls.sh

cleanup:
	helm uninstall local-sigstore
