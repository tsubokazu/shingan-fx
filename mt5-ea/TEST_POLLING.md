# ポーリング動作確認ガイド

## 🔍 確認方法

### 1. MT5ログで確認（最も確実）

#### ジャーナルログ
1. MT5下部の「ターミナル」を開く（Ctrl+T）
2. 「ジャーナル」タブを選択
3. 以下のログを確認:

```
✅ 正常起動時:
[TvBridgePullEA] Initialized successfully
[TvBridgePullEA] Base URL: https://shiny-smoke-04f2.tsubokazu-dev.workers.dev
[TvBridgePullEA] Symbol Filter: EURUSD
[TvBridgePullEA] Poll Interval: 2 seconds
```

#### エキスパートログ（詳細）
1. 「エキスパート」タブを選択
2. 2秒ごとにログが表示されるか確認

```
✅ ポーリング成功（シグナルなし）:
[TvBridgeHttp] GET https://... - Status: 200

✅ シグナル取得成功:
[TvBridgePullEA] Received 2 signal(s)
[TvBridgeJson] Parsed signal[0]: key=pending:EURUSD:..., action=BUY
[TvBridgeSignal] Processing BUY signal
[TvBridgeTrade] BUY order opened: EURUSD, lot=0.01
[TvBridgePullEA] Acknowledged 2 signal(s)

❌ エラー例:
[TvBridgeHttp] Poll failed. Status: 401
→ 原因: InpPollTokenが間違っている

[TvBridgeHttp] WebRequest error: 4060
→ 原因: URLが許可リストに入っていない（MT5再起動が必要）
```

### 2. チャート上のステータス表示

EAが読み込まれたチャートの左上に表示:

```
TvBridge Pull EA
Status: Running
Symbol Filter: EURUSD
Last Poll: 2025-10-28 15:45:32  ← 2秒ごとに更新
Signals Processed: 0
Signals Acked: 0
Consecutive Errors: 0  ← 0であればOK
```

### 3. Cloudflare Workers側でログ確認

#### リアルタイムログ（ターミナル）

```bash
# Producer Workerのログ
wrangler tail

# Consumer Workerのログ
wrangler tail --config wrangler.consumer.jsonc
```

**ポーリングが届いている場合:**
```
GET /api/poll?symbol=EURUSD&limit=10
Status: 200
Response: {"items":[]}
```

#### Cloudflare Dashboardでログ確認

1. https://dash.cloudflare.com/ にログイン
2. **Workers & Pages** > **shiny-smoke-04f2** を選択
3. **Logs** タブを開く
4. リアルタイムログストリームを確認

## 🧪 テストシグナルを送信して動作確認

### 方法1: curlコマンドでテスト

```bash
# WEBHOOK_TOKENを取得
# wrangler secret list で確認済みか確認

# テストシグナルを送信
curl -X POST https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_WEBHOOK_TOKEN" \
  -d '{
    "symbol": "EURUSD",
    "timeframe": "1H",
    "signal": "LONG",
    "bar_time": "2025-10-28T15:00:00Z"
  }'
```

**期待される応答:**
```json
{"status":"queued"}
```

### 方法2: テストスクリプトを使用

以下のスクリプトを作成して実行:

```bash
# test-signal.sh
#!/bin/bash

WORKER_URL="https://shiny-smoke-04f2.tsubokazu-dev.workers.dev"
WEBHOOK_TOKEN="YOUR_WEBHOOK_TOKEN"

curl -X POST "$WORKER_URL/" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WEBHOOK_TOKEN" \
  -d '{
    "symbol": "EURUSD",
    "timeframe": "15m",
    "signal": "LONG",
    "bar_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'
```

実行:
```bash
chmod +x test-signal.sh
./test-signal.sh
```

### 確認手順

1. **テストシグナル送信**
   ```bash
   curl -X POST https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/ ...
   ```

2. **Consumer Workerの処理を待つ**（1～3秒）

3. **MT5 EAがポーリングで取得**（最大2秒待機）

4. **MT5のエキスパートログを確認**
   ```
   [TvBridgePullEA] Received 1 signal(s)
   [TvBridgeSignal] Processing BUY signal
   [TvBridgeTrade] BUY order opened
   ```

5. **ポジションが開かれたか確認**
   - MT5の「取引」タブでポジションを確認

## ❌ トラブルシューティング

### エラー: WebRequest error: 4060

**原因:** URLが許可リストに含まれていない

**解決:**
1. MT5: ツール > オプション > Expert Advisors
2. 「WebRequestを許可するURL」を確認
3. 正しく設定されていれば、**MT5を再起動**

### エラー: Poll failed. Status: 401

**原因:** InpPollTokenが間違っている

**解決:**
```bash
# Cloudflare側のトークンを確認
wrangler secret list

# MT5のEAパラメータで正しいトークンを設定
```

### エラー: Poll failed. Status: 404

**原因:** URLが間違っている

**解決:**
- InpBaseUrlを確認: `https://shiny-smoke-04f2.tsubokazu-dev.workers.dev`

### ポーリングは成功するがシグナルが来ない

**原因:** シグナルがPendingSignals KVに保存されていない

**確認:**
1. TradingViewアラートが送信されているか
2. Consumer Workerが正常に動作しているか
3. シンボル名が一致しているか（EURUSD vs EURUSD.a など）

**デバッグ:**
```bash
# Consumer Workerのログを確認
wrangler tail --config wrangler.consumer.jsonc

# KVにシグナルが保存されているか確認
wrangler kv key list --namespace-id a5488e7d0cb64966b8c5a6decf022069 --prefix "pending:EURUSD"
```

## 📊 正常動作時のログフロー

```
1. TradingView
   └─> Webhook送信

2. Producer Worker (index.ts)
   ├─> 認証チェック
   ├─> バリデーション
   └─> Queue送信 → {"status":"queued"}

3. Consumer Worker (consumer.ts)
   ├─> Queue受信
   ├─> 重複排除
   ├─> シグナル判定
   └─> PendingSignals KVに保存

4. MT5 EA (2秒ごと)
   ├─> GET /api/poll
   ├─> シグナル取得
   ├─> 注文実行
   └─> POST /api/ack → KVから削除
```

## ✅ 正常動作の確認チェックリスト

- [ ] MT5ジャーナルに "Initialized successfully" が表示される
- [ ] エキスパートログで2秒ごとにポーリングログが表示される
- [ ] チャート左上の "Last Poll" が2秒ごとに更新される
- [ ] Consecutive Errors が 0 のまま
- [ ] `wrangler tail` でGET /api/poll のログが表示される
- [ ] テストシグナル送信後、MT5でシグナルが取得される
- [ ] 注文が正常に実行される

すべてチェックがついていれば、正常に動作しています！
