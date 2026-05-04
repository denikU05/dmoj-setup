#!/bin/bash

echo "================================"
echo "  DMOJ Online Judge Uninstaller "
echo "================================"
echo ""
echo "WARNING: This will remove all DMOJ containers, volumes and files."
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMOJ_DIR="$SCRIPT_DIR/dmoj"

# --- Stop and remove containers ---
echo "[1/4] Stopping and removing containers..."

if [ -d "$DMOJ_DIR/dmoj-docker/dmoj" ]; then
  cd "$DMOJ_DIR/dmoj-docker/dmoj"
  docker compose down 2>/dev/null || true
else
  echo "dmoj-docker not found, skipping docker compose down."
fi

if docker inspect judge > /dev/null 2>&1; then
  docker stop judge
  docker rm judge
  echo "Judge container removed."
else
  echo "Judge container not found, skipping."
fi

# --- Remove volumes ---
echo "[2/4] Removing Docker volumes..."
for VOL in dmoj_assets dmoj_cache dmoj_datacache dmoj_pdfcache; do
  if docker volume inspect $VOL > /dev/null 2>&1; then
    docker volume rm $VOL
    echo "  Removed volume: $VOL"
  fi
done

# --- Remove judge image ---
echo "[3/4] Removing judge Docker image..."
for TIER in 1 2 3; do
  if docker image inspect dmoj/judge-tier${TIER} > /dev/null 2>&1; then
    docker image rm dmoj/judge-tier${TIER}
    echo "  Removed image: dmoj/judge-tier${TIER}"
  fi
done

# --- Remove files ---
echo "[4/4] Removing directory: $DMOJ_DIR ..."
if [ -d "$DMOJ_DIR" ]; then
  sudo rm -rf "$DMOJ_DIR"
  echo "Done."
else
  echo "$DMOJ_DIR not found, skipping."
fi

echo ""
echo "================================"
echo "  Uninstall complete!           "
echo "================================"
echo ""