# testing the policy controller fork from github

## setup

1. I am running all the following in a new Kubernetes cluster deployed with Docker Desktop for Mac
1. There are 2 charts to deploy, hosted at https://github.com/github/artifact-attestations-helm-charts/tree/main
1. `namespaces.yaml` contains the 2 namespaces used
    - `test` the namespace where admission is managed by the controller
    - `github-policy-controller` the namespace where the controller webhook runs
1. I used `helm template` command to generate the kubernetes manifests. `policy-controller.yaml` is for the controller, `trust-policies.yaml` is for the trust policies chart (using the values in `values.trust-policies.yaml`)
  ```
  helm template github-policy-controller oci://ghcr.io/github/artifact-attestations-helm-charts/policy-controller --version v0.10.0-github5 --namespace=github-policy-controller > policy-controller.yaml
  helm template github-trust-policies oci://ghcr.io/github/artifact-attestations-helm-charts/policy-controller --version v0.5.0 --namespace=github-policy-controller --values=values.trust-policies.yaml > trust-policies.yaml
  ```

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

## Experience

❗The [Github Charts README](https://github.com/github/artifact-attestations-helm-charts#3-enable-the-policy-in-your-namespace) tells us to use an `annotation` to let the controller manage admission in a certain namespace. However we actually need to use a `label` (indeed the example command just below in the docs uses a `label`).

I tried to deploy these 3 images:
* `ghcr.io/falcorocks/learns:latest`, built [here](../../.github/workflows/build-attest-public.yaml) with GHA using the artifact attestation action: https://github.com/actions/attest-build-provenance. It should be allowed by the policy as it's signed by public good sigstore which is one of the 2 allowed authorities
* `nginx:latest` which I put in the exempt policy, it should be allowed even if it's not signed
* `minio:latest` which should not be allowed as it has no signature and it is not in the exempt policy

### Result

🆗 `minio` is denied deployment, as expected the `github-policy` fails
```
% kubectl run minio --namespace=test --image=bitnami/minio:latest
Error from server (BadRequest): admission webhook "policy.sigstore.dev" denied the request: validation failed: failed policy: github-policy: spec.containers[0].image index.docker.io/bitnami/minio@sha256:b3f9d8b5fc4ee245219a703ec805e37642bae521194244b28ce794ca29d652df no bundle found in referrers no bundle found in referrers
```

❎🤔 `nginx` should be allowed deployment, but it is not. The `github-policy` fails, which is expected as the image is unsigned. According to the Sigstore Policy Controller docs https://docs.sigstore.dev/policy-controller/overview/#admission-of-images to be deployed an image must pass at least 1 authority in each of the policies that regard it (that is when the image falls under the provided `images` glob). In this case the image falls under `images` glob of both the `github-policy` and the `github-exempt-policy`.
```
% kubectl run nginx --namespace=test --image=nginx:latest        
Error from server (BadRequest): admission webhook "policy.sigstore.dev" denied the request: validation failed: failed policy: github-policy: spec.containers[0].image index.docker.io/library/nginx@sha256:6af79ae5de407283dcea8b00d5c37ace95441fd58a8b1d2aa1ed93f5511bb18c no bundle found in referrers no bundle found in referrers
```

⚠️`falcorocks/learns` is allowed deployment as expected, however I run into some errors when I repeat the command:
```
% kubectl run falcorocks-learns --namespace=test --image=ghcr.io/falcorocks/learns@sha256:4ac65f23061de2faef157760fa2125c954b5b064bc25e10655e90bd92bc3b354
pod/falcorocks-learns created
% kubectl run falcorocks-learns --namespace=test --image=ghcr.io/falcorocks/learns@sha256:4ac65f23061de2faef157760fa2125c954b5b064bc25e10655e90bd92bc3b354
Error from server (InternalError): Internal error occurred: failed calling webhook "policy.sigstore.dev": failed to call webhook: Post "https://webhook.github-policy-controller.svc:443/validations?timeout=10s": EOF
```

Turns out, the webhook crashed with some memory error when I repeated the command. I can reproduce this consistently. I also get this problem when I use a tag instead of the digest. I tried to reproduce these errors with the upstream sigstore controller, and I cannot, so this is specific to the Github fork.

My first thought was that this had to be a memory limit, the request is for `128Mi` and the limit is for `512Mi`. But that is not the case, doubling the memory did not help

```
{"level":"info","ts":1722955214.0927722,"logger":"fallback","caller":"webhook/main.go:132","msg":"Initializing TUF root from  => https://tuf-repo-cdn.sigstore.dev"}
main.go:149: {
  "gitVersion": "v0.10.0-github5",
  "gitCommit": "c294fd1281ad4b7e861f96fb3cb719b08deb4d62",
  "gitTreeState": "clean",
  "buildDate": "2024-07-09T19:35:00Z",
  "goVersion": "go1.22.0",
  "compiler": "gc",
  "platform": "linux/amd64"
}
main.go:228: Registering 3 clients
main.go:229: Registering 4 informer factories
main.go:230: Registering 7 informers
main.go:231: Registering 8 controllers
{"level":"info","ts":"2024-08-06T14:40:14.457Z","logger":"policy-controller","caller":"profiling/server.go:65","msg":"Profiling enabled: false","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.461Z","logger":"policy-controller","caller":"leaderelection/context.go:47","msg":"Running with Standard leader election","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.494Z","logger":"policy-controller","caller":"sharedmain/main.go:283","msg":"Starting configuration manager...","commit":"c294fd1"}
{"level":"info","ts":1722955214.595121,"logger":"fallback","caller":"injection/injection.go:63","msg":"Starting informers..."}
{"level":"info","ts":"2024-08-06T14:40:14.610Z","logger":"policy-controller","caller":"clusterimagepolicy/controller.go:102","msg":"Doing a global resync on ClusterImagePolicies due to ConfigMap changing or resync period.","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.611Z","logger":"policy-controller","caller":"trustroot/controller.go:67","msg":"Doing a global resync on TrustRoot due to ConfigMap changing or resync period.","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.696Z","logger":"policy-controller","caller":"webhook/webhook.go:218","msg":"Informers have been synced, unblocking admission webhooks.","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.696Z","logger":"policy-controller","caller":"sharedmain/main.go:311","msg":"Starting controllers...","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.696Z","logger":"policy-controller","caller":"injection/health_check.go:43","msg":"Probes server listening on port 8080","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.696Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.resource-conversion.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_e802eb03-8c8d-4852-98e5-d81905cca32b\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.696Z","logger":"policy-controller.resource-conversion","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.resource-conversion","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.webhookcertificates.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_249cf0b4-0b0d-44c0-be61-2d4de53ce9b6\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.WebhookCertificates","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.WebhookCertificates","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.policy.sigstore.dev-validating.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_a8cd42b6-4e50-4bb0-b747-15a13279d1eb\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.policy.sigstore.dev","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.policy.sigstore.dev","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.policy.sigstore.dev-mutating.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_8e32d06a-e062-4aed-a232-a73c93f4a67b\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.policy.sigstore.dev","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.697Z","logger":"policy-controller.policy.sigstore.dev","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.github.com.sigstore.policy-controller.pkg.reconciler.trustroot.reconciler.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_ecea11c5-bb67-4d79-bace-eb51210c39cb\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1","knative.dev/controller":"github.com.sigstore.policy-controller.pkg.reconciler.trustroot.Reconciler","knative.dev/kind":"policy.sigstore.dev.TrustRoot"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1","knative.dev/controller":"github.com.sigstore.policy-controller.pkg.reconciler.trustroot.Reconciler","knative.dev/kind":"policy.sigstore.dev.TrustRoot"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.github.com.sigstore.policy-controller.pkg.reconciler.clusterimagepolicy.reconciler.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_015fc30c-3df1-4068-a845-dfed63098d58\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1","knative.dev/controller":"github.com.sigstore.policy-controller.pkg.reconciler.clusterimagepolicy.Reconciler","knative.dev/kind":"policy.sigstore.dev.ClusterImagePolicy"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1","knative.dev/controller":"github.com.sigstore.policy-controller.pkg.reconciler.clusterimagepolicy.Reconciler","knative.dev/kind":"policy.sigstore.dev.ClusterImagePolicy"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.validating.clusterimagepolicy.sigstore.dev.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_749a928e-16dc-4998-b911-3116c8a49047\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller.validating.clusterimagepolicy.sigstore.dev","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller.validating.clusterimagepolicy.sigstore.dev","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
I0806 14:40:14.698656       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.resource-conversion.00-of-01...
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller","caller":"leaderelection/context.go:149","msg":"policy-controller.defaulting.clusterimagepolicy.sigstore.dev.00-of-01 will run in leader-elected mode with id \"github-policy-controller-webhook-8496984cbc-cjchv_cc7e277c-f8e7-4c7a-9097-320dd3580fd7\"","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller.defaulting.clusterimagepolicy.sigstore.dev","caller":"controller/controller.go:486","msg":"Starting controller and workers","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:14.698Z","logger":"policy-controller.defaulting.clusterimagepolicy.sigstore.dev","caller":"controller/controller.go:496","msg":"Started workers","commit":"c294fd1"}
I0806 14:40:14.699204       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.webhookcertificates.00-of-01...
I0806 14:40:14.699532       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.policy.sigstore.dev-validating.00-of-01...
I0806 14:40:14.699795       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.policy.sigstore.dev-mutating.00-of-01...
I0806 14:40:14.700144       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.github.com.sigstore.policy-controller.pkg.reconciler.trustroot.reconciler.00-of-01...
I0806 14:40:14.700335       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.github.com.sigstore.policy-controller.pkg.reconciler.clusterimagepolicy.reconciler.00-of-01...
I0806 14:40:14.700597       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.validating.clusterimagepolicy.sigstore.dev.00-of-01...
I0806 14:40:14.700956       1 leaderelection.go:250] attempting to acquire leader lease github-policy-controller/policy-controller.defaulting.clusterimagepolicy.sigstore.dev.00-of-01...
{"level":"info","ts":"2024-08-06T14:40:45.530Z","logger":"policy-controller","caller":"webhook/admission.go:93","msg":"Webhook ServeHTTP request=&http.Request{Method:\"POST\", URL:(*url.URL)(0xc000928480), Proto:\"HTTP/1.1\", ProtoMajor:1, ProtoMinor:1, Header:http.Header{\"Accept\":]string{\"application/json, */*\"}, \"Accept-Encoding\":]string{\"gzip\"}, \"Content-Length\":]string{\"2628\"}, \"Content-Type\":]string{\"application/json\"}, \"User-Agent\":]string{\"kube-apiserver-admission\"}}, Body:(*http.body)(0xc0008dd000), GetBody:(func() (io.ReadCloser, error))(nil), ContentLength:2628, TransferEncoding:]string(nil), Close:false, Host:\"webhook.github-policy-controller.svc:443\", Form:url.Values(nil), PostForm:url.Values(nil), MultipartForm:(*multipart.Form)(nil), Trailer:http.Header(nil), RemoteAddr:\"192.168.65.3:63154\", RequestURI:\"/mutations?timeout=10s\", TLS:(*tls.ConnectionState)(0xc00086e210), Cancel:(<-chan struct {})(nil), Response:(*http.Response)(nil), ctx:(*context.cancelCtx)(0xc0008bf9f0), pat:(*http.pattern)(0xc0007f6120), matches:]string(nil), otherValues:map[string]string(nil)}","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:45.536Z","logger":"policy-controller","caller":"defaulting/defaulting.go:158","msg":"Kind: \"/v1, Kind=Pod\" PatchBytes: null","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop"}
{"level":"info","ts":"2024-08-06T14:40:45.536Z","logger":"policy-controller","caller":"webhook/admission.go:151","msg":"remote admission controller audit annotations=map[string]string(nil)","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop","admissionreview/uid":"fde10b05-3a28-4b55-9930-7edba851bd67","admissionreview/allowed":true,"admissionreview/result":"nil"}
{"level":"info","ts":"2024-08-06T14:40:45.540Z","logger":"policy-controller","caller":"webhook/admission.go:93","msg":"Webhook ServeHTTP request=&http.Request{Method:\"POST\", URL:(*url.URL)(0xc000ab0240), Proto:\"HTTP/1.1\", ProtoMajor:1, ProtoMinor:1, Header:http.Header{\"Accept\":]string{\"application/json, */*\"}, \"Accept-Encoding\":]string{\"gzip\"}, \"Content-Length\":]string{\"2732\"}, \"Content-Type\":]string{\"application/json\"}, \"User-Agent\":]string{\"kube-apiserver-admission\"}}, Body:(*http.body)(0xc0009b01c0), GetBody:(func() (io.ReadCloser, error))(nil), ContentLength:2732, TransferEncoding:]string(nil), Close:false, Host:\"webhook.github-policy-controller.svc:443\", Form:url.Values(nil), PostForm:url.Values(nil), MultipartForm:(*multipart.Form)(nil), Trailer:http.Header(nil), RemoteAddr:\"192.168.65.3:63162\", RequestURI:\"/validations?timeout=10s\", TLS:(*tls.ConnectionState)(0xc00086e370), Cancel:(<-chan struct {})(nil), Response:(*http.Response)(nil), ctx:(*context.cancelCtx)(0xc0009ba000), pat:(*http.pattern)(0xc0007f60c0), matches:]string(nil), otherValues:map[string]string(nil)}","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:52.096Z","logger":"policy-controller","caller":"webhook/validator.go:1266","msg":"Validated 1 policies for image ghcr.io/falcorocks/learns@sha256:4ac65f23061de2faef157760fa2125c954b5b064bc25e10655e90bd92bc3b354","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop"}
{"level":"info","ts":"2024-08-06T14:40:52.096Z","logger":"policy-controller","caller":"webhook/admission.go:151","msg":"remote admission controller audit annotations=map[string]string(nil)","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop","admissionreview/uid":"b91be04c-cbc1-48c4-bb52-f2fac4b976b8","admissionreview/allowed":true,"admissionreview/result":"nil"}
{"level":"info","ts":"2024-08-06T14:40:56.339Z","logger":"policy-controller","caller":"webhook/admission.go:93","msg":"Webhook ServeHTTP request=&http.Request{Method:\"POST\", URL:(*url.URL)(0xc000c065a0), Proto:\"HTTP/1.1\", ProtoMajor:1, ProtoMinor:1, Header:http.Header{\"Accept\":]string{\"application/json, */*\"}, \"Accept-Encoding\":]string{\"gzip\"}, \"Content-Length\":]string{\"2628\"}, \"Content-Type\":]string{\"application/json\"}, \"User-Agent\":]string{\"kube-apiserver-admission\"}}, Body:(*http.body)(0xc001094d40), GetBody:(func() (io.ReadCloser, error))(nil), ContentLength:2628, TransferEncoding:]string(nil), Close:false, Host:\"webhook.github-policy-controller.svc:443\", Form:url.Values(nil), PostForm:url.Values(nil), MultipartForm:(*multipart.Form)(nil), Trailer:http.Header(nil), RemoteAddr:\"192.168.65.3:63154\", RequestURI:\"/mutations?timeout=10s\", TLS:(*tls.ConnectionState)(0xc00086e210), Cancel:(<-chan struct {})(nil), Response:(*http.Response)(nil), ctx:(*context.cancelCtx)(0xc0010cb270), pat:(*http.pattern)(0xc0007f6120), matches:]string(nil), otherValues:map[string]string(nil)}","commit":"c294fd1"}
{"level":"info","ts":"2024-08-06T14:40:56.396Z","logger":"policy-controller","caller":"defaulting/defaulting.go:158","msg":"Kind: \"/v1, Kind=Pod\" PatchBytes: null","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop"}
{"level":"info","ts":"2024-08-06T14:40:56.396Z","logger":"policy-controller","caller":"webhook/admission.go:151","msg":"remote admission controller audit annotations=map[string]string(nil)","commit":"c294fd1","knative.dev/kind":"/v1, Kind=Pod","knative.dev/namespace":"test","knative.dev/name":"falcorocks-learns","knative.dev/operation":"CREATE","knative.dev/resource":"/v1, Resource=pods","knative.dev/subresource":"","knative.dev/userinfo":"docker-for-desktop","admissionreview/uid":"0bfaa010-f026-49a1-b9bd-c52676f9c594","admissionreview/allowed":true,"admissionreview/result":"nil"}
{"level":"info","ts":"2024-08-06T14:40:56.405Z","logger":"policy-controller","caller":"webhook/admission.go:93","msg":"Webhook ServeHTTP request=&http.Request{Method:\"POST\", URL:(*url.URL)(0xc000c74480), Proto:\"HTTP/1.1\", ProtoMajor:1, ProtoMinor:1, Header:http.Header{\"Accept\":]string{\"application/json, */*\"}, \"Accept-Encoding\":]string{\"gzip\"}, \"Content-Length\":]string{\"2732\"}, \"Content-Type\":]string{\"application/json\"}, \"User-Agent\":]string{\"kube-apiserver-admission\"}}, Body:(*http.body)(0xc001095cc0), GetBody:(func() (io.ReadCloser, error))(nil), ContentLength:2732, TransferEncoding:]string(nil), Close:false, Host:\"webhook.github-policy-controller.svc:443\", Form:url.Values(nil), PostForm:url.Values(nil), MultipartForm:(*multipart.Form)(nil), Trailer:http.Header(nil), RemoteAddr:\"192.168.65.3:63162\", RequestURI:\"/validations?timeout=10s\", TLS:(*tls.ConnectionState)(0xc00086e370), Cancel:(<-chan struct {})(nil), Response:(*http.Response)(nil), ctx:(*context.cancelCtx)(0xc000e78190), pat:(*http.pattern)(0xc0007f60c0), matches:]string(nil), otherValues:map[string]string(nil)}","commit":"c294fd1"}
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x1c3d260]

goroutine 842 [running]:
github.com/sigstore/sigstore-go/pkg/root.(*TrustedRoot).RekorLogs(0xc0008a8700?)
    github.com/sigstore/sigstore-go@v0.3.0/pkg/root/trusted_root.go:74
github.com/sigstore/sigstore-go/pkg/verify.VerifyArtifactTransparencyLog({0x347da30, 0xc0008a8700}, {0x3477fe0, 0x0}, 0x1, 0x1, 0x0)
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/tlog.go:85 +0x289
github.com/sigstore/sigstore-go/pkg/verify.(*SignedEntityVerifier).VerifyTransparencyLogInclusion(0xc000bc3e90?, {0x347da30?, 0xc0008a8700?})
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/signed_entity.go:618 +0x65
github.com/sigstore/sigstore-go/pkg/verify.(*SignedEntityVerifier).Verify(0xc000115880, {0x347da30, 0xc0008a8700}, {0xc000bc3e90?, {0xc0000a3d58?, 0x10?, 0xc0000a4808?}})
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/signed_entity.go:475 +0xdb
github.com/sigstore/policy-controller/pkg/webhook.VerifiedBundles({0x3477fa0, 0xc000e78410}, {0x3477fe0?, 0x0?}, {0xc0010f7b90, 0x2, 0x2}, {0xc0000a3d58, 0x1, 0x1}, ...)
    github.com/sigstore/policy-controller/pkg/webhook/bundle.go:116 +0x28d
github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicyAttestationsForAuthorityWithBundle({0x34750f8, 0xc000e4de00}, {0x3477fa0, 0xc000e78410}, {{0xc00054c150, 0xb}, 0x0, 0xc0004d8b00, 0x0, {0x0, ...}, ...}, ...)
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:1028 +0x669
github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicy.func1()
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:542 +0x44d
created by github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicy in goroutine 840
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:516 +0x1e5
Stream closed EOF for github-policy-controller/github-policy-controller-webhook-8496984cbc-cjchv (policy-controller-webhook)
```

After raising the request to `512Mi` and the limit to `1024Mi` I run into the same exact error again

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x1c3d260]

goroutine 6094 [running]:
github.com/sigstore/sigstore-go/pkg/root.(*TrustedRoot).RekorLogs(0xc000f69950?)
    github.com/sigstore/sigstore-go@v0.3.0/pkg/root/trusted_root.go:74
github.com/sigstore/sigstore-go/pkg/verify.VerifyArtifactTransparencyLog({0x347da30, 0xc000f69950}, {0x3477fe0, 0x0}, 0x1, 0x1, 0x0)
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/tlog.go:85 +0x289
github.com/sigstore/sigstore-go/pkg/verify.(*SignedEntityVerifier).VerifyTransparencyLogInclusion(0xc001280a20?, {0x347da30?, 0xc000f69950?})
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/signed_entity.go:618 +0x65
github.com/sigstore/sigstore-go/pkg/verify.(*SignedEntityVerifier).Verify(0xc00065ce70, {0x347da30, 0xc000f69950}, {0xc001280a20?, {0xc0010a1ef0?, 0x10?, 0xc000101808?}})
    github.com/sigstore/sigstore-go@v0.3.0/pkg/verify/signed_entity.go:475 +0xdb
github.com/sigstore/policy-controller/pkg/webhook.VerifiedBundles({0x3477fa0, 0xc000ac85f0}, {0x3477fe0?, 0x0?}, {0xc000965b90, 0x2, 0x2}, {0xc0010a1ef0, 0x1, 0x1}, ...)
    github.com/sigstore/policy-controller/pkg/webhook/bundle.go:116 +0x28d
github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicyAttestationsForAuthorityWithBundle({0x34750f8, 0xc0010252c0}, {0x3477fa0, 0xc000ac85f0}, {{0xc001184f50, 0xb}, 0x0, 0xc000443a80, 0x0, {0x0, ...}, ...}, ...)
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:1028 +0x669
github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicy.func1()
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:542 +0x44d
created by github.com/sigstore/policy-controller/pkg/webhook.ValidatePolicy in goroutine 6092
    github.com/sigstore/policy-controller/pkg/webhook/validator.go:516 +0x1e5
Stream closed EOF for github-policy-controller/test-policy-controller-webhook-685767d4f-zcs6n (policy-controller-webhook)
```
