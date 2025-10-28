# TradingView アラート クイックスタート

## 🚀 5分でアラート設定

### ステップ1: WEBHOOK_TOKENを確認

```bash
wrangler secret list
```

表示されたトークンをメモしてください（例: `my-secret-token-123`）

### ステップ2: TradingViewでアラートを作成

1. TradingViewにログイン → BTCUSDチャートを開く
2. 右上の**時計アイコン**をクリック → 「アラートを作成」
3. **条件**: `価格 > 0`（テスト用に即座にトリガーされる条件）

### ステップ3: Webhook URLを設定

**方法A: URLにトークンを含める（推奨）**

```
https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/?token=YOUR_WEBHOOK_TOKEN
```

※ `YOUR_WEBHOOK_TOKEN`を実際のトークンに置き換え

**方法B: メッセージにトークンを含める**

URLフィールド:
```
https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/
```

### ステップ4: メッセージを設定

#### BUY（買い）シグナル

**方法A使用時:**
```json
{
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "LONG",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

**方法B使用時:**
```json
{
  "token": "YOUR_WEBHOOK_TOKEN",
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "LONG",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

#### SELL（売り）シグナル

`"signal": "LONG"` を `"signal": "SHORT"` に変更

#### 部分決済シグナル

`"signal": "LONG"` を `"signal": "TP"` に変更

### ステップ5: アラートを保存

1. アラート名: "BTCUSD Buy Test"
2. 「作成」をクリック

## ✅ 動作確認

### 1. Workerログで確認

```bash
wrangler tail
```

**期待される出力:**
```
POST / - 200
{"status":"queued"}
```

### 2. MT5で確認

EAが読み込まれていれば、10秒以内にエキスパートログに表示:

```
[TvBridgePullEA] Received 1 signal(s)
[TvBridgeSignal] Processing BUY signal
[TvBridgeTrade] BUY order opened: BTCUSD, lot=0.01
```

### 3. MT5の「取引」タブで確認

新しいポジションが開かれているはずです！

## 📋 対応シグナル一覧

| signal値 | アクション | 説明 |
|---------|----------|------|
| `LONG` | 買い注文 | 買いポジションオープン |
| `SHORT` | 売り注文 | 売りポジションオープン |
| `TP` | 部分決済 | ポジションの50%を決済 |
| `TP_LONG` | 部分決済 | 買いポジションの50%を決済 |
| `TP_SHORT` | 部分決済 | 売りポジションの50%を決済 |

## 🔧 認証方法まとめ

以下の3つの方法がサポートされています：

### 1. Authorization ヘッダー（curl用）
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" ...
```

### 2. URLクエリパラメータ（TradingView推奨）
```
https://...workers.dev/?token=YOUR_TOKEN
```

### 3. リクエストボディ（TradingView代替）
```json
{"token": "YOUR_TOKEN", ...}
```

## ⚠️ トラブルシューティング

### 認証エラー（403 Forbidden）

- トークンが正しいか確認
- URLまたはメッセージにトークンが含まれているか確認

### シグナルが届かない

```bash
# Consumer Workerのログを確認
wrangler tail --config wrangler.consumer.jsonc
```

### MT5でシグナルが取得されない

1. MT5 EAが起動しているか確認
2. `InpSymbolFilter`が正しいか確認（BTCUSD）
3. エキスパートログにエラーがないか確認

## 🎯 次のステップ

- 実際の取引戦略に合わせてアラート条件を設定
- 複数のシンボル/タイムフレームでアラートを作成
- バックテストとフォワードテストを実施

詳細は `docs/tradingview_alert_setup.md` を参照してください！
