#!/bin/bash

# TvBridge テストシグナル送信スクリプト

WORKER_URL="https://shiny-smoke-04f2.tsubokazu-dev.workers.dev"

# WEBHOOK_TOKENを環境変数から取得
# export WEBHOOK_TOKEN="your-token-here" を事前に実行してください
if [ -z "$WEBHOOK_TOKEN" ]; then
    echo "❌ エラー: WEBHOOK_TOKENが設定されていません"
    echo "以下のコマンドで設定してください:"
    echo "  export WEBHOOK_TOKEN=\"your-webhook-token-here\""
    exit 1
fi

# 現在時刻を取得
BAR_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "📤 テストシグナルを送信中..."
echo "URL: $WORKER_URL"
echo "Symbol: EURUSD"
echo "Signal: LONG"
echo "Bar Time: $BAR_TIME"
echo ""

# シグナル送信
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$WORKER_URL/" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WEBHOOK_TOKEN" \
  -d "{
    \"symbol\": \"EURUSD\",
    \"timeframe\": \"15m\",
    \"signal\": \"LONG\",
    \"bar_time\": \"$BAR_TIME\"
  }")

# HTTPステータスコードを抽出
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo "📥 レスポンス:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""

# ステータスコードを確認
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ シグナル送信成功！"
    echo ""
    echo "📋 次の確認手順:"
    echo "  1. Consumer Workerの処理を待つ（1～3秒）"
    echo "  2. MT5のエキスパートログを確認（最大2秒でポーリング）"
    echo "  3. '[TvBridgePullEA] Received 1 signal(s)' が表示されるはず"
    echo "  4. MT5の「取引」タブでポジションを確認"
else
    echo "❌ エラー: HTTPステータス $HTTP_STATUS"
    echo ""
    echo "トラブルシューティング:"
    if [ "$HTTP_STATUS" == "401" ] || [ "$HTTP_STATUS" == "403" ]; then
        echo "  - WEBHOOK_TOKENが正しいか確認してください"
    elif [ "$HTTP_STATUS" == "400" ]; then
        echo "  - リクエストボディの形式を確認してください"
    else
        echo "  - Cloudflare Workersが正常に動作しているか確認してください"
    fi
fi
