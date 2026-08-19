#!/bin/sh
# Renders the demo "proof of life" page into the nginx docroot before nginx
# starts, then hands off to the real CMD (nginx itself).
#
# This replaces what a separate busybox initContainer used to do in
# k8s/deployment.yaml. Baking it into the app image's own entrypoint is the
# point of Lab 3 (Containerization): the image is now self-contained, rather
# than depending on a second public image at deploy time just to render one
# page.
#
# The docroot ($OUT_DIR) is still a PersistentVolumeClaim-backed mount (see
# k8s/deployment.yaml) - writing here at every container start is also what
# proves, live, that the CSI-provisioned OCI block volume is actually
# writable, not just attached.
set -eu

OUT_DIR="/usr/share/nginx/html"
mkdir -p "$OUT_DIR"

cat <<EOF > "$OUT_DIR/index.html"
<html>
  <head><title>Ejada Week 3 - OKE Demo</title></head>
  <body style="font-family: sans-serif;">
    <h1>Ejada Internship - Week 3 OKE Lab</h1>
    <p>Served by pod: $(hostname)</p>
    <p>Node: ${NODE_NAME:-unknown}</p>
    <p>Rendered at container start: $(date -u)</p>
    <p>Image: ${IMAGE_TAG:-week3-demo-app:local}</p>
    <p>This page is being read from a PersistentVolumeClaim backed
       by an OCI block volume, attached via the CSI driver.</p>
  </body>
</html>
EOF

exec "$@"
