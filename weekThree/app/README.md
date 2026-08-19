# Week 3 demo app image (Lab 3 - Containerization)

This directory is what was missing from the original Week 3 build: a real
Dockerfile for the demo app, instead of just pulling public `nginx` +
`busybox` images straight from Docker Hub. Building and pushing this image to
OCIR is Lab 3; pointing OKE at the pushed image (`k8s/deployment.ocir.yaml`)
is the "proper" version of Lab 4.

I could not build or run this image inside the cloud sandbox that produced
it -- that sandbox's network is locked down to an allowlist that does not
include Docker Hub or any other image registry, so `docker build` fails at
the `FROM nginx:1.27-alpine` step with a 403. I did verify `entrypoint.sh`'s
actual logic by running it directly (not inside Docker) and confirmed it
renders valid HTML with the right pod/node/timestamp substitutions. The
Dockerfile itself is three lines and about as low-risk as they come, but you
should still do the build and the local `docker run` test yourself before
trusting it, since I couldn't.

## 1. Build

```bash
cd app
docker build -t week3-demo-app:v1 .
```

## 2. Test locally (before touching OCIR or OKE at all)

```bash
docker run --rm -p 8080:80 -e NODE_NAME=local-test week3-demo-app:v1
```

In another terminal:

```bash
curl http://localhost:8080
```

You should see the same proof-of-life page the initContainer used to
render, now coming from the image itself. Ctrl+C the `docker run` when done.

## 3. Log in to OCIR

Your screenshot's login snippet had `-u BEARER_TOKEN` as a literal
placeholder, not something to type as-is. The real `-u` value for OCIR is
`<tenancy-namespace>/<username>` (add `oracleidentitycloudservice/` before
the username if your account is federated/IDCS-based). Find your tenancy
namespace with:

```bash
oci os ns get --query data --raw-output
```

Then:

```bash
OCIR_ACCESS_TOKEN=$(oci container-registry access-token get \
  --query 'data."access-token"' \
  --raw-output)

printf '%s' "$OCIR_ACCESS_TOKEN" | \
  docker login jed.ocir.io \
  -u '<tenancy-namespace>/<your-username>' \
  --password-stdin
```

(`jed` = the Jeddah region key, matching `me-jeddah-1` from the rest of this
build -- this part of your screenshot was already correct.)

## 4. Tag and push

```bash
docker tag week3-demo-app:v1 jed.ocir.io/<tenancy-namespace>/week3-demo-app:v1
docker push jed.ocir.io/<tenancy-namespace>/week3-demo-app:v1
```

If OCIR rejects the push because the repository doesn't exist yet: OCIR
auto-creates a private repository on first push in most tenancies. If yours
doesn't, create `week3-demo-app` as a repository in the OCI Console under
Developer Services > Container Registry first, then repeat the push.

## 5. Point the manifest at your image

Edit `k8s/deployment.ocir.yaml` and replace
`<region-key>.ocir.io/<tenancy-namespace>/week3-demo-app:v1` with the exact
tag you just pushed.

## 6. Deploy it

The namespace, StorageClass, PVC, and Service from the original build don't
change -- only the Deployment does. From a cluster where those four are
already applied:

```bash
kubectl delete -f k8s/deployment.yaml    # remove the nginx/busybox version
kubectl apply -f k8s/deployment.ocir.yaml
kubectl get pods -n week3-demo -w
```

Watch for `ImagePullBackOff` specifically -- if OKE's worker nodes can't
pull from your OCIR repository, it's almost always one of: the repository is
private and the node pool has no pull secret, or the image path/tag doesn't
match exactly what you pushed. If that happens, the fix is a Kubernetes
`docker-registry` secret referencing the same auth token from step 3,
attached to the pod spec via `imagePullSecrets` -- ask me and I'll wire that
in once you know whether you actually hit this.

## 7. Verify

Same checks as before: `kubectl get pods -n week3-demo` for `1/1 Running`,
then a browser request against the load balancer's external IP should show
the proof-of-life page, this time rendered by your own image instead of a
public one.

## Files here

- `Dockerfile` -- three lines: `nginx:1.27-alpine` base, copy in
  `entrypoint.sh`, run nginx via that entrypoint.
- `entrypoint.sh` -- renders `index.html` into the (PVC-backed) docroot at
  container start, then hands off to nginx. Same content the old busybox
  initContainer used to render, just now owned by this image instead of
  depending on a second public image.
