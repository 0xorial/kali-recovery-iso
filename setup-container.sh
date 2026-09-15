#!/bin/sh
# Recreate the kali-iso-builder container on the Colima "kali" profile and
# apply everything this repo tracks: the Rosetta patches (container-overlay/)
# and the image customizations (kali-config-overlay/).
#
# Prereq (asks for ~8GB RAM / 80GB disk):
#   colima start --profile kali --vm-type vz --vz-rosetta --cpu 8 --memory 8 --disk 80
# Undo everything: colima delete -p kali
set -eu
CTX="colima-kali"
NAME="kali-iso-builder"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

docker --context "$CTX" volume create kali-iso-build
docker --context "$CTX" volume create kali-iso-cache
docker --context "$CTX" run -d --name "$NAME" --privileged --platform linux/amd64 \
    -v kali-iso-build:/build -v kali-iso-cache:/cache \
    kalilinux/kali-rolling sleep infinity

docker --context "$CTX" exec "$NAME" sh -c \
    'apt-get update && apt-get install -y git live-build simple-cdd cdebootstrap curl'

# Patched files were written against: live-build 1:20250814+kali3,
# debootstrap 1.0.144 (see README for what each patch does). The wrapper
# needs the real chroot diverted out of the way first.
docker --context "$CTX" exec "$NAME" \
    dpkg-divert --divert /usr/sbin/chroot.real --rename --add /usr/sbin/chroot
tar -C "$REPO_DIR/container-overlay" -cf - . | \
    docker --context "$CTX" exec -i "$NAME" tar -C / -xf -
docker --context "$CTX" exec "$NAME" chmod +x /usr/sbin/chroot

docker --context "$CTX" exec "$NAME" sh -c '
    set -eu
    cd /build
    [ -d live-build-config ] || git clone --depth 1 \
        https://gitlab.com/kalilinux/build-scripts/live-build-config.git
    rm -rf live-build-config/cache
    ln -sfn /cache live-build-config/cache
'
tar -C "$REPO_DIR/kali-config-overlay" -cf - . | docker --context "$CTX" exec -i "$NAME" \
    tar -C /build/live-build-config/kali-config -xf -

echo "Container ready. Build with:"
echo "  docker --context $CTX exec -d $NAME sh -c 'cd /build/live-build-config && ./build.sh --variant xfce --verbose > /build/build.log 2>&1; echo \$? > /build/build.exit'"
echo "  docker --context $CTX exec $NAME tail -f /build/build.log"
