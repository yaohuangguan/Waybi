FROM ghcr.io/valhalla/valhalla-scripted:3.9.1@sha256:6238809f9dc3057743d70a20efd3911ec38e458bfa13a0601909b58f68dfd956
# An immutable, prebuilt graph. Never download or rebuild NZ on a navigation
# request or container wakeup. prepare-artifact.mjs verifies the input first.
COPY artifact/ /data/
EXPOSE 8002
ENTRYPOINT ["valhalla_service", "/data/valhalla.json", "1"]
