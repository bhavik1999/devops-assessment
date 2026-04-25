#!/bin/bash
# Simulate traffic to the sample API
# Usage: ./03-simulate-traffic.sh [duration_seconds]

DURATION=${1:-300}
API_URL="http://localhost:8888"
END_TIME=$((SECONDS + DURATION))

echo "==> Port-forwarding API..."
kubectl port-forward svc/sample-api -n sample-api 8888:80 &
PF_PID=$!
sleep 2

echo "==> Sending traffic for ${DURATION}s to ${API_URL}..."

while [ $SECONDS -lt $END_TIME ]; do
  # Normal endpoints
  curl -s "$API_URL/" > /dev/null
  curl -s "$API_URL/health" > /dev/null
  curl -s "$API_URL/users" > /dev/null
  curl -s "$API_URL/users/$((RANDOM % 10 + 1))" > /dev/null
  curl -s -X POST "$API_URL/orders" > /dev/null

  # Occasional slow and error endpoints
  if (( RANDOM % 5 == 0 )); then
    curl -s "$API_URL/slow" > /dev/null
  fi
  if (( RANDOM % 8 == 0 )); then
    curl -s "$API_URL/error" > /dev/null || true
    curl -s "$API_URL/users/999" > /dev/null || true
  fi

  sleep 0.5
  echo -n "."
done

echo ""
echo "==> Traffic simulation complete!"
kill $PF_PID 2>/dev/null
