# learns

## cosign

### keyless signing

`cosign`` will generate a disposable keypair for us, and ask fulcio to certify that these keys belong to us through a certificate.
Authentication happens through github action OIDC.
Evidence of the signing will be stored in the public append-only `rekor` registry.
The entry contains sensitive informations related to the identity of the signer and the github project, such as:
* github project url
* github workflow file path
* github repo identifier
* github repo branch
* github repo commit hash

See for instance the certificate stored at the [record](https://search.sigstore.dev/?logIndex=30748641) generated through workflow at `.github/workflows/cosign-keyless-ttl.yml`

```yaml
data:
  Serial Number: '0x78d0b90a609473406ff0e8dff68f486205e2713e'
Signature:
  Issuer: O=sigstore.dev, CN=sigstore-intermediate
  Validity:
    Not Before: 2 minutes ago (2023-08-10T10:41:03+02:00)
    Not After: in 8 minutes (2023-08-10T10:51:03+02:00)
  Algorithm:
    name: ECDSA
    namedCurve: P-256
  Subject:
    extraNames:
      items: {}
    asn: []
X509v3 extensions:
  Key Usage (critical):
  - Digital Signature
  Extended Key Usage:
  - Code Signing
  Subject Key Identifier:
  - 6D:E1:A2:97:45:81:6E:3C:FA:BE:0C:FC:AF:DB:9B:20:7D:7F:27:99
  Authority Key Identifier:
    keyid: DF:D3:E9:CF:56:24:11:96:F9:A8:D8:E9:28:55:A2:C6:2E:18:64:3F
  Subject Alternative Name (critical):
    url:
    - https://github.com/falcorocks/learns/.github/workflows/cosign-keyless-ttl.yml@refs/heads/main
  OIDC Issuer: https://token.actions.githubusercontent.com
  GitHub Workflow Trigger: push
  GitHub Workflow SHA: 560cc1e96680d6aca3b2b1667203a67bd62359df
  GitHub Workflow Name: cosign ttl.sh
  GitHub Workflow Repository: falcorocks/learns
  GitHub Workflow Ref: refs/heads/main
  OIDC Issuer (v2): https://token.actions.githubusercontent.com
  Build Signer URI: https://github.com/falcorocks/learns/.github/workflows/cosign-keyless-ttl.yml@refs/heads/main
  Build Signer Digest: 560cc1e96680d6aca3b2b1667203a67bd62359df
  Runner Environment: github-hosted
  Source Repository URI: https://github.com/falcorocks/learns
  Source Repository Digest: 560cc1e96680d6aca3b2b1667203a67bd62359df
  Source Repository Ref: refs/heads/main
  Source Repository Identifier: '676546930'
  Source Repository Owner URI: https://github.com/falcorocks
  Source Repository Owner Identifier: '14293929'
  Build Config URI: https://github.com/falcorocks/learns/.github/workflows/cosign-keyless-ttl.yml@refs/heads/main
  Build Config Digest: 560cc1e96680d6aca3b2b1667203a67bd62359df
  Build Trigger: push
  Run Invocation URI: https://github.com/falcorocks/learns/actions/runs/5818892927/attempts/1
  1.3.6.1.4.1.57264.1.22: 0c:06:70:75:62:6c:69:63
  1.3.6.1.4.1.11129.2.4.2: 04:7a:00:78:00:76:00:dd:3d:30:6a:c6:c7:11:32:63:19:1e:1c:99:67:37:02:a2:4a:5e:b8:de:3c:ad:ff:87:8a:72:80:2f:29:ee:8e:00:00:01:89:de:9b:3e:f4:00:00:04:03:00:47:30:45:02:20:6d:4e:85:d4:41:28:4c:46:73:11:ce:d6:f4:38:af:cd:9c:9b:e5:af:18:9f:b0:98:d4:77:79:e7:46:43:ae:b8:02:21:00:ed:31:cc:3e:48:3b:d6:16:9f:60:40:24:1b:ff:05:17:cc:f3:d5:ec:f8:5c:56:b8:be:92:b5:a5:15:46:ff:9a
```

### keyed signing

Where the user brings their own keys.
I generated the keys stored in this repo at `cosign.key` and `cosign.pub` through the handy `cosign generate keypair`.
However you can also load keys from elsewhere, including Vault and cloud vendor KMSs.
The private key is stored encrypted.
The password is made available to the workflow through a Github secret, see the workflow file at `.github/workflows/cosign-keyed-ttl.yml`.

Since this method does not use OIDC, there is no certificate containing identity related information stored at the public `rekor` instance.
See for instance the entry https://search.sigstore.dev/?logIndex=30751454, generated from this repo through the aforementioned workflow file.
This method gains privacy at the cost of losing the main advantage of the keyless approach: using identity over long lived keys that have to be managed.
However the gain in privacy is significant.

### interesting options

* we can issue a code signing certificate from Fulcio, even if a key is provided `--issue-certificate=false`
    - what happens when this is enabled? It does not work without providing `id-token: write` permissions. What happens if you give it? Then you get a certificate in the transparency log that looks exactly like the one from the keyless workflow. See for instance https://search.sigstore.dev/?logIndex=30755007
* the upload to the transparency log can be disabled with the flag `--tlog-upload=true`
    - what happens in keyless mode?
    - what happens in keyed mode?
    - in both cases, verification fails. Verification checks the validity of a signature