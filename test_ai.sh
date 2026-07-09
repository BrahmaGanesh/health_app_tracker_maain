#!/bin/bash

BASE_URL="https://health-app-tracker-maa.onrender.com"
EMAIL="your-email@example.com"
PASSWORD="your-password"

echo "=== Step 1: Login ==="
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo $LOGIN_RESPONSE | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "❌ Login failed!"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi

echo "✅ Token received"

echo ""
echo "=== Step 2: Test AI Chat ==="
AI_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/ai-assistant/chat" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"Is 140/90 BP normal?"}')

echo "Response: $AI_RESPONSE"

if echo $AI_RESPONSE | grep -q '"success":true'; then
    echo ""
    echo "✅ AI is working!"
else
    echo ""
    echo "❌ AI not working - check logs"
fi