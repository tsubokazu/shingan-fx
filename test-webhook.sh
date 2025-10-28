#!/bin/bash

# TradingView Webhook テストスクリプト

echo "=== TradingView Webhook テスト ==="
echo ""

# WEBHOOK_TOKENを入力
read -p "WEBHOOK_TOKEN を入力してください: " WEBHOOK_TOKEN

if [ -z "$WEBHOOK_TOKEN" ]; then
    echo "❌ エラー: トークンが入力されていません"
    exit 1
fi

WORKER_URL="https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/webhook"
BAR_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo ""
echo "📤 テストシグナルを送信中..."
echo "URL: ${WORKER_URL}?token=***"
echo "Symbol: BTCUSD"
echo "Signal: LONG"
echo ""

# 方法1: URLパラメータでトークン送信
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${WORKER_URL}?token=${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"symbol\": \"BTCUSD\",
    \"timeframe\": \"15m\",
    \"signal\": \"LONG\",
    \"price\": \"67000\",
    \"bar_time\": \"${BAR_TIME}\"
  }")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo "📥 レスポンス:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""
echo "HTTP Status: $HTTP_STATUS"
echo ""

if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Webhook送信成功！"
    echo ""
    echo "次の確認手順:"
    echo "  1. 3秒待機してConsumer Workerが処理するのを待つ"
    sleep 3
    echo "  2. PendingSignals KVを確認"

    # KVを確認
    echo ""
    echo "📦 PendingSignals KVの内容:"
    wrangler kv key list --namespace-id a5488e7d0cb64966b8c5a6decf022069 --prefix "pending:BTCUSD" 2>&1

    echo ""
    echo "  3. MT5のエキスパートログを確認してください"
    echo "     最大10秒でMT5 EAがポーリングで取得します"
else
    echo "❌ エラー: HTTP Status $HTTP_STATUS"
    echo ""
    if [ "$HTTP_STATUS" == "403" ]; then
        echo "原因: WEBHOOK_TOKENが間違っている可能性があります"
        echo "解決: 正しいトークンを確認してください"
    elif [ "$HTTP_STATUS" == "400" ]; then
        echo "原因: リクエストボディの形式が正しくありません"
    elif [ "$HTTP_STATUS" == "405" ]; then
        echo "原因: メソッドが許可されていません"
        echo "     Workerのルーティング設定を確認してください"
    fi
fi
