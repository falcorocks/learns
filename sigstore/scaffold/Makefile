ready:
	helm repo add sigstore https://sigstore.github.io/helm-charts
	helm repo update

install:
	helm upgrade -i local-sigstore sigstore/scaffold --version=0.6.32 --values=values.yaml