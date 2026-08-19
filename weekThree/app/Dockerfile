# Week 3 demo app image (Lab 3 - Containerization).
#
# Base: nginx:1.27-alpine, same version already referenced (and verified live
# against the cluster) in k8s/deployment.yaml's app container, so switching
# from "pull nginx from Docker Hub + a separate busybox initContainer" to
# "pull this image from OCIR" is a drop-in change, not a behavior change.
FROM nginx:1.27-alpine

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
