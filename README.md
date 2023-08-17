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
    - what happens in keyless mode? it fails
    - what happens in keyed mode? it fails. But why?
* custom claims can be added to the signature with `--annotations`
    - we could add the git hash, the branch name, if the branch is protected...
    - we could try to check for the integrity of the repository...
    - we could use annotations for promotion (instead of using different keys)

### what is the purpose of the transparency log?

* signature tells us that an authorized entity (= in possession of the private key) has certified the content of the container image
* transparancy log tells us also:
    - when the signing took place
    - who triggered the signing (keyless mode only)
    - which workflow triggered the signing (keyless mode only), including its file hash
    - repository information at the time of signing (keyless mode only), including branch, commit hash
* in keyless mode, working with a transparency log is therefore mandatory

### BYO annotations

Signer can add custom key-value pairs to the image signature.
These claims can be later verified for integrity testing.
In `.github/workflows/cosign-keyed-ttl.yml` we add annotations for git porcelain, the commit hash from github action and the commit hash from the actual tree. These 3 info provide substantial evidence that the repository has not been tampered during the execution of the workflow (porcelain should be 0 and the two hashes should match).
This approach in the keyed mode does not seem to leak information about the repository in the transparency log.

### BYO rekor

* using keys has risks
* OIDC "keyless" workflow much more elegant
* but leaks way too much information on public rekor instance
* solution: deploy your own rekor (& trillian) instance

#### deploy rekor locally (for testing purposes only)
1. add sigstore repository and install rekor
```
helm repo add sigstore https://sigstore.github.io/helm-charts
helm upgrade -i testrekor sigstore/rekor --version=1.2.2
```

on an apple silicon mac, it won't work. See https://github.com/sigstore/helm-charts/issues/589. You also need to pass this value file:

```yaml
#apple-silicon.yaml
trillian:
  logServer:
    nodeSelector:
      kubernetes.io/arch: arm64
  logSigner:
    nodeSelector:
      kubernetes.io/arch: arm64
```

so

```
helm upgrade -i testrekor sigstore/rekor --version=1.2.2 --values=apple-silicon.yaml
```

2. port-forward the trillian service

```
kubectl port-forward svc/testrekor-server 9999:80
```

3. test you can reach the instance

* you need to install the [rekor-cli](https://edu.chainguard.dev/open-source/sigstore/rekor/how-to-install-rekor/)

```
rekor-cli loginfo --rekor_server=http://localhost:9999

Verification Successful!
Active Tree Size:       1
Total Tree Size:        1
Root Hash:              609abac55ed7e4c2565f83fd8081fe5d5add9f805543a0a29668b74b6215ea13
Timestamp:              2023-08-17T11:46:52Z
TreeID:                 539983248407926811
```

notice that the tree is not empty, because I had already inserted another record before recording this session. It should be empty at first!

4. you can now use the instance with cosign

```
# copy alpine:latest in a temporary registry (ttl.sh is awesome!)
cosign copy alpine ttl.sh/thisisjustatest:1h

# get the digest with crane
DIGEST=$(crane digest ttl.sh/thisisjustatest:1h)

# sign with cosign OIDC 'keyless' method
# this will pop up a browser window, but in CI it will work automatically (at least on github actions)
cosign sign --rekor-url=http://localhost:9999  ttl.sh/thisisjustatest@$DIGEST
Generating ephemeral keys...
Retrieving signed certificate...

	The sigstore service, hosted by sigstore a Series of LF Projects, LLC, is provided pursuant to the Hosted Project Tools Terms of Use, available at https://lfprojects.org/policies/hosted-project-tools-terms-of-use/.
	Note that if your submission includes personal data associated with this signed artifact, it will be part of an immutable record.
	This may include the email address associated with the account with which you authenticate your contractual Agreement.
	This information will be used for signing this artifact and will be stored in public transparency logs and cannot be removed later, and is subject to the Immutable Record notice at https://lfprojects.org/policies/hosted-project-tools-immutable-records/.

By typing 'y', you attest that (1) you are not submitting the personal data of any other person; and (2) you understand and agree to the statement and the Agreement terms at the URLs listed above.
Are you sure you would like to continue? [y/N] y
Your browser will now be opened to:
https://oauth2.sigstore.dev/auth/auth?access_type=online&client_id=sigstore&code_challenge=ViG9Si5Mj5zd87UxzsQSv30xwYM3x8GTosYLPLyBLjw&code_challenge_method=S256&nonce=2U6vX13FQCmlb4i0fY06KyjCgCi&redirect_uri=http%3A%2F%2Flocalhost%3A63720%2Fauth%2Fcallback&response_type=code&scope=openid+email&state=2U6vX2K24UAOdPHwm7oYXsP745P
Successfully verified SCT...
tlog entry created with index: 1
Pushing signature to: ttl.sh/thisisjustatest
```

we can now inspect the record

```
rekor-cli --rekor_server=http://localhost:9999 get --log-index=1
LogID: df0a1a6c942840859346de55ace242078c0f778703d8a0c42930633ce1c3b9be
Index: 1
IntegratedTime: 2023-08-17T11:48:21Z
UUID: 077e67e74a04181bffff3d9694346e8044815f41fa8063c918a6950c558a773e4de3dcaffdbbf2b6
Body: {
  "HashedRekordObj": {
    "data": {
      "hash": {
        "algorithm": "sha256",
        "value": "0e748728acf1644f78d23a8fcdda91903a4b6e7720ae8ef0af9944c75dc86e2f"
      }
    },
    "signature": {
      "content": "MEUCIQCId5q8eN1YJ/ud1+Al9j+0v/+rQk1tVbQ1NhWc2ZPmOQIgE663PegN9gp6buTtA3T1SPTSUxcYu2X6vVGHXckdqII=",
      "publicKey": {
        "content": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMwakNDQWxlZ0F3SUJBZ0lVZUxrN2xCL3p5bEhkUnJ0enVneVlsMVNNMERRd0NnWUlLb1pJemowRUF3TXcKTnpFVk1CTUdBMVVFQ2hNTWMybG5jM1J2Y21VdVpHVjJNUjR3SEFZRFZRUURFeFZ6YVdkemRHOXlaUzFwYm5SbApjbTFsWkdsaGRHVXdIaGNOTWpNd09ERTNNVEUwT0RFMldoY05Nak13T0RFM01URTFPREUyV2pBQU1Ga3dFd1lICktvWkl6ajBDQVFZSUtvWkl6ajBEQVFjRFFnQUVtTXFzN2pDSU12alhtd09kQjlPTU9OSFdPUDk4bTc5Mk1uWEMKL05LamxNVEl2VDVNaVhvZ2ExcUtNRHM4VENiKzh6T2dEcktGQkdjb3VPb2s0aXhrNnFPQ0FYWXdnZ0Z5TUE0RwpBMVVkRHdFQi93UUVBd0lIZ0RBVEJnTlZIU1VFRERBS0JnZ3JCZ0VGQlFjREF6QWRCZ05WSFE0RUZnUVUrMHEyCk83MEppcEt0K1JGSDFVeXp3R3NyeDFnd0h3WURWUjBqQkJnd0ZvQVUzOVBwejFZa0VaYjVxTmpwS0ZXaXhpNFkKWkQ4d0lRWURWUjBSQVFIL0JCY3dGWUVUYldGcGJFQm1ZV3hqYjNKdlkydHpMbU52YlRBc0Jnb3JCZ0VFQVlPLwpNQUVCQkI1b2RIUndjem92TDJkcGRHaDFZaTVqYjIwdmJHOW5hVzR2YjJGMWRHZ3dMZ1lLS3dZQkJBR0R2ekFCCkNBUWdEQjVvZEhSd2N6b3ZMMmRwZEdoMVlpNWpiMjB2Ykc5bmFXNHZiMkYxZEdnd2dZa0dDaXNHQVFRQjFua0MKQkFJRWV3UjVBSGNBZFFEZFBUQnF4c2NSTW1NWkhoeVpaemNDb2twZXVONDhyZitIaW5LQUx5bnVqZ0FBQVlvRApVeWxBQUFBRUF3QkdNRVFDSUY0ZnRicFlEQ3BvVTlPY0l4OVRoOXlvdmgvQlpmT2Rxa25xam9rMkpsN1pBaUFlCkZvUTFQRXpNaXR6eXhUZFlmQlBBUmtjV3VYTmYwYUpGSVBMQ0ErTmVlVEFLQmdncWhrak9QUVFEQXdOcEFEQm0KQWpFQXkvSk8wbEFBTEpQZHd0bk9wNmtKUEQ0NjZqSGhMTmhVdm0yTXVYdjhzTG1qODN6MFBIckIyRCs1RU1PVQo5cDVjQWpFQTR3cWpTRWdBdDd1c3RJUi9pRzRLTGlyYVMwREoxSWVpMjlPVDNCMDdDeWhCVFRaK0NJQmNoWE1OCi9RK1I5aUgxCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
      }
    }
  }
}
```

but in order to verify the signature it is necessary to use the flag `--insecure-ignore-tlog=true` (notice here I'm referring to yet another signature, since the earlier ones expired by the time I got to this (ttl.sh deletes images tagged 1h after 1h))

```
cosign verify ttl.sh/thisisjustatest@$DIGEST --rekor-url=http://localhost:9999 --certificate-identity=REDACTED --certificate-oidc-issuer=https://github.com/login/oauth --insecure-ignore-tlog=true
WARNING: Skipping tlog verification is an insecure practice that lacks of transparency and auditability verification for the signature.

Verification for ttl.sh/thisisjustatest@sha256:7144f7bab3d4c2648d7e59409f15ec52a18006a128c733fcff20d3a4a54ba44a --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The code-signing certificate was verified using trusted certificate authority certificates

[{"critical":{"identity":{"docker-reference":"ttl.sh/thisisjustatest"},"image":{"docker-manifest-digest":"sha256:7144f7bab3d4c2648d7e59409f15ec52a18006a128c733fcff20d3a4a54ba44a"},"type":"cosign container image signature"},"optional":{"1.3.6.1.4.1.57264.1.1":"https://github.com/login/oauth","Bundle":{"SignedEntryTimestamp":"MEUCIEhcKOvS/LckmcO6khdW2ky68YE1bly8PijZFj5L0sUbAiEAgyiyTpil42UaRfWqv0saeryl2eapj5qQ+2jRyb1GedE=","Payload":{"body":"eyJhcGlWZXJzaW9uIjoiMC4wLjEiLCJraW5kIjoiaGFzaGVkcmVrb3JkIiwic3BlYyI6eyJkYXRhIjp7Imhhc2giOnsiYWxnb3JpdGhtIjoic2hhMjU2IiwidmFsdWUiOiIwZTc0ODcyOGFjZjE2NDRmNzhkMjNhOGZjZGRhOTE5MDNhNGI2ZTc3MjBhZThlZjBhZjk5NDRjNzVkYzg2ZTJmIn19LCJzaWduYXR1cmUiOnsiY29udGVudCI6Ik1FUUNJQmxOTHJDd1NUNXF6RmZOVlU5aVZjZkltZDJBaXc2cVFJWFU0YkpiWEMyWUFpQUtGOVpqdHliOEE2MVJqZ05mdkZ1bnMza082SXNHa1NPV0luZ0RwcTVRWnc9PSIsInB1YmxpY0tleSI6eyJjb250ZW50IjoiTFMwdExTMUNSVWRKVGlCRFJWSlVTVVpKUTBGVVJTMHRMUzB0Q2sxSlNVTXdla05EUVd4cFowRjNTVUpCWjBsVlZsQTRjV3A0TVU1clZFdHNaV0p3TlVOeVMycEhRVE0xY25aRmQwTm5XVWxMYjFwSmVtb3dSVUYzVFhjS1RucEZWazFDVFVkQk1WVkZRMmhOVFdNeWJHNWpNMUoyWTIxVmRWcEhWakpOVWpSM1NFRlpSRlpSVVVSRmVGWjZZVmRrZW1SSE9YbGFVekZ3WW01U2JBcGpiVEZzV2tkc2FHUkhWWGRJYUdOT1RXcE5kMDlFUlROTlZFbDZUa1JGZDFkb1kwNU5hazEzVDBSRk0wMVVTVEJPUkVWM1YycEJRVTFHYTNkRmQxbElDa3R2V2tsNmFqQkRRVkZaU1V0dldrbDZhakJFUVZGalJGRm5RVVV5Y0d0YVNYQXhWemxTZVVsNVdHSTFNMXBvWjNoTEsybDVLM1ZTZWs5bU1YTjBhVmtLY3pkcGRWQnFXVU5VZW10b1pEQlViekU1ZFVkU1lUQnpUazlGVTNwVk9YWXZWMjlUTnpSb1RERTNlWFJyUmpGcVVUWlBRMEZZWTNkblowWjZUVUUwUndwQk1WVmtSSGRGUWk5M1VVVkJkMGxJWjBSQlZFSm5UbFpJVTFWRlJFUkJTMEpuWjNKQ1owVkdRbEZqUkVGNlFXUkNaMDVXU0ZFMFJVWm5VVlZUU1VScENtaG5aMVZvWVZacEt6TTFRMFpzYTA1UFQxbERNMHRGZDBoM1dVUldVakJxUWtKbmQwWnZRVlV6T1ZCd2VqRlphMFZhWWpWeFRtcHdTMFpYYVhocE5Ga0tXa1E0ZDBsUldVUldVakJTUVZGSUwwSkNZM2RHV1VWVVlsZEdjR0pGUW0xWlYzaHFZak5LZGxreWRIcE1iVTUyWWxSQmMwSm5iM0pDWjBWRlFWbFBMd3BOUVVWQ1FrSTFiMlJJVW5kamVtOTJUREprY0dSSGFERlphVFZxWWpJd2RtSkhPVzVoVnpSMllqSkdNV1JIWjNkTVoxbExTM2RaUWtKQlIwUjJla0ZDQ2tOQlVXZEVRalZ2WkVoU2QyTjZiM1pNTW1Sd1pFZG9NVmxwTldwaU1qQjJZa2M1Ym1GWE5IWmlNa1l4WkVkbmQyZFpiMGREYVhOSFFWRlJRakZ1YTBNS1FrRkpSV1pCVWpaQlNHZEJaR2RFWkZCVVFuRjRjMk5TVFcxTldraG9lVnBhZW1ORGIydHdaWFZPTkRoeVppdElhVzVMUVV4NWJuVnFaMEZCUVZsdlJBcG1VelJhUVVGQlJVRjNRa2hOUlZWRFNWRkRPV1pEYjJKR1IzcFhjR3cyTVVGc1YwMXNVMnQxV0ZodVdqTkhNRkpaWVd4ck9XMXZjV2x5UlhFeVFVbG5Dazh3YVhWdldVWjRaVkZ2VVRWUlRsWmxkRGhPVUZjd1puUktlVVpoY21GU1lsVmlhbFZEU3pZd1RHZDNRMmRaU1V0dldrbDZhakJGUVhkTlJHRlJRWGNLV21kSmVFRkxSVFk0Tm5KSlZHMVhZV1F4VERWV1JWY3lXSFZMY1VWTFl5dFNXQzk0YWpkaE5FTmllVWhSWmk5R2N6aFFTaXRHVWpoaU5rWnhPVXh4ZEFwRmRUaHpTbWRKZUVGS2JWWnNXWGhEUkM5VVZXWkRORGhRTTBOVFZXMWhWM0JHZDFWMVNtNXlRWGRLV2t0bmJ5dFhVRnBoYVROVFp6UTRSMGhMU1M4NENscExTM2gwUVhNdldsRTlQUW90TFMwdExVVk9SQ0JEUlZKVVNVWkpRMEZVUlMwdExTMHRDZz09In19fX0=","integratedTime":1692275652,"logIndex":5,"logID":"df0a1a6c942840859346de55ace242078c0f778703d8a0c42930633ce1c3b9be"}},"Issuer":"https://github.com/login/oauth","Subject":"REDACTED"}}]
```

TODO: understand why it is necessary to use that flag, considering the following checks listed.