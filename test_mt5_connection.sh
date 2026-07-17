#!/bin/bash

echo "🔍 Diagnostic: Testing God Mode Connectivity"
echo "============================================"

# 1. Check if Node Bridge is running
BRIDGE_PID=$(lsof -t -i :8891)
if [ -z "$BRIDGE_PID" ]; then
    echo "❌ ERROR: Node.js Bridge is NOT running on port 8891."
    echo "   Action: Run 'npm run dev' in mt5-bridge/web/mt_nodejs"
else
    echo "✅ SUCCESS: Node.js Bridge found (PID: $BRIDGE_PID) on port 8891"
fi

# 2. Check if MT5 EA is listening
EA_PID=$(lsof -t -i :8890)
if [ -z "$EA_PID" ]; then
    echo "❌ ERROR: MT5 Expert Advisor is NOT listening on port 8890."
    echo "   Action: 1. Open MT5"
    echo "           2. Attach 'SocketBridgeEA' to a chart"
    echo "           3. Enable 'Allow Algo Trading'"
else
    echo "✅ SUCCESS: MT5 EA is listening on port 8890"
fi

# 3. Test Bridge -> EA connection (if Bridge is up)
if [ ! -z "$BRIDGE_PID" ]; then
    echo "🌐 Testing Bridge -> EA status..."
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8891/v1/status -H "Authorization: Bearer al3RUuur7PCUjNiE1ja/Dzx5tpWz0EeqGUA618k6VY")

    if [ "$STATUS_CODE" == "200" ]; then
        echo "✅ SUCCESS: Bridge is communicating with EA."
    elif [ "$STATUS_CODE" == "503" ]; then
        echo "❌ ERROR: Bridge is UP, but EA is UNREACHABLE (503)."
    else
        echo "⚠️ WARNING: Bridge returned status $STATUS_CODE"
    fi
fi

echo "============================================"
