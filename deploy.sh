#!/bin/bash
# Deploy Paul Voice Assistant to remote Mac
# Usage: ./deploy.sh

set -e

REMOTE="paul@192.168.1.89"
REMOTE_PATH="~/Paul/paul-voice-assistant"
LOCAL_PATH="/Users/tg/Paul/paul-voice-assistant"
IDENTIFIER="com.paul.voiceassistant"

echo "=== Paul Voice Assistant Deploy ==="

# 1. Sync source files
echo "[1/4] Syncing source files..."
rsync -av --delete \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '*.xcodeproj' \
    --exclude 'DerivedData' \
    "$LOCAL_PATH/Paul/" "$REMOTE:$REMOTE_PATH/Paul/"

rsync -av "$LOCAL_PATH/Package.swift" "$REMOTE:$REMOTE_PATH/"

# 2. Build on remote (x86_64)
echo "[2/4] Building on remote (x86_64)..."
ssh "$REMOTE" "cd $REMOTE_PATH && swift build -c release --arch x86_64 2>&1 | tail -5"

# 3. Sign with stable identifier
echo "[3/4] Signing binary..."
ssh "$REMOTE" "codesign -s - -f --identifier '$IDENTIFIER' $REMOTE_PATH/.build/release/Paul"

# 4. Restart LaunchAgent
echo "[4/4] Restarting Paul..."
ssh "$REMOTE" "launchctl stop com.paul.assistant 2>/dev/null || true; sleep 1; launchctl start com.paul.assistant"

# Verify
echo ""
echo "=== Deploy complete ==="
ssh "$REMOTE" "launchctl list | grep paul && tail -3 ~/Paul/paul.log"
