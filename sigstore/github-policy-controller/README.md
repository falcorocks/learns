# testing the policy controller fork from github

## setup

1. I am running all the following in a new Kubernetes cluster deployed with Docker Desktop for Mac
1. There are 2 charts to deploy, hosted at https://github.com/github/artifact-attestations-helm-charts/tree/main
1. `namespaces.yaml` contains the 2 namespaces used
    - `test` the namespace where admission is managed by the controller
    - `github-policy-controller` the namespace where the controller webhook runs
1. I used `helm template` command to generate the kubernetes manifests. `policy-controller.yaml` is for the controller, `trust-policies.yaml` is for the trust policies chart (using the values in `values.trust-policies.yaml`)
1. the values enable the creation of the defaul clusterImagePolicy to only admit images signed by github artifact attestation/public sigstore as well as an exemption ClusterImagePolicy
    ```yaml
    ---
    # Source: trust-policies/templates/clusterimagepolicy-exempt.yaml
    apiVersion: policy.sigstore.dev/v1alpha1
    kind: ClusterImagePolicy
    metadata:
    name: github-exempt-policy
    spec:
    images: 
        - glob: "nginx:latest"
        
    authorities:
        - static:
            action: pass
    ---
    # Source: trust-policies/templates/clusterimagepolicy-github.yaml
    apiVersion: policy.sigstore.dev/v1alpha1
    kind: ClusterImagePolicy
    metadata:
    name: github-policy
    spec:
    images: 
        - glob: "**"
        
    authorities:

    - name: github
        keyless:
        trustRootRef: github
        url: https://fulcio.githubapp.com
        identities:
        - issuer: https://token.actions.githubusercontent.com
            subjectRegExp: https://github.com/*/.*/\.github/workflows/.*
        rfc3161timestamp:
        trustRootRef: github
        signatureFormat: bundle
        attestations:
        - name: require-attestation
        predicateType: https://slsa.dev/provenance/v1

    - name: public-good
        keyless:
        identities:
        - issuer: https://token.actions.githubusercontent.com
            subjectRegExp: https://github.com/*/.*/\.github/workflows/.*
        ctlog:
        url: https://rekor.sigstore.dev
        signatureFormat: bundle
        attestations:
        - name: require-attestation
        predicateType: https://slsa.dev/provenance/v1
    ---
    ```

## experience

The [Github Charts README](https://github.com/github/artifact-attestations-helm-charts#3-enable-the-policy-in-your-namespace) tells us to use an `annotation` to let the controller manage admission in a certain namespace. However we need to use a `label` (indeed the example command just below in the docs uses a `label`).

I tried to deploy these 3 images:
* `ghcr.io/falcorocks/learns:latest`, built [here](../../.github/workflows/build-attest-public.yaml) with GHA using the artifact attestation action: https://github.com/actions/attest-build-provenance. It should be allowed by the policy as it's signed by public good sigstore which is one of the 2 allowed authorities
* `nginx:latest` which I put in the exempt policy, it should be allowed even if it's not signed
* `minio:latest` which should not be allowed as it has no signature and it is not in the exempt policy

### Result

* `minio` is denied deployment, as expected
    ```
    kubectl run minio --namespace test --image=bitnami/minio
    ```
* `nginx` should be allowed deployment, but it is not because there is no associated signature. The `github-exempt-policy` seems to not be working correctly
    ```
    kubectl run nginx --namespace=test --image=nginx:latest
    ```
* `falcorocks/learns` is allowed deployment, however I had to run the command over 10 times to finally make it work. The error I got was related to the webhook refusing to connect
    ```
    kubectl run falcorocks-learns --namespace-test --image=ghcr.io/falcorocks/learns
    ```