#!/bin/bash

echo "==============================="
echo "  Starting DMOJ Online Judge   "
echo "==============================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMOJ_DIR="$SCRIPT_DIR/dmoj"

cd "$DMOJ_DIR/dmoj-docker/dmoj"

# Start all main containers
echo "Starting containers..."
docker compose up -d

# Check if judge container exists
if docker inspect judge > /dev/null 2>&1; then
  echo "Starting judge..."
  docker start judge
else
  echo "WARNING: judge container not found."
  echo "Run install.sh if you haven't installed the system yet."
fi

echo ""
echo "Done! Wait 10-15 seconds for everything to start."
echo ""
echo "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}"