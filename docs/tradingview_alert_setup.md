# TradingView アラート設定ガイド

## 概要

TradingViewからWebhookでシグナルを送信し、MT5で自動取引を実行するための設定方法を説明します。

## 対応シグナル

以下のシグナルが対応しています（`consumer.ts:decideAction()`で定義）：

| シグナル | アクション | 説明 |
|---------|----------|------|
| `LONG` | BUY注文 | 買いポジションをオープン |
| `SHORT` | SELL注文 | 売りポジションをオープン |
| `TP` | 部分決済 | 全ポジションの50%を決済（デフォルト） |
| `TP_LONG` | 部分決済 | 買いポジションの50%を決済 |
| `TP_SHORT` | 部分決済 | 売りポジションの50%を決済 |

**注意**: `CLOSE`シグナルは現在未実装です。全決済が必要な場合は、別途実装が必要です。

## 事前準備

### 1. WEBHOOK_TOKENの確認

```bash
# トークンが設定されているか確認
wrangler secret list

# まだ設定していない場合は設定
wrangler secret put WEBHOOK_TOKEN
# プロンプトでトークンを入力（例: my-secret-webhook-token-123）
```

このトークンをTradingViewのアラート設定で使用します。

### 2. Worker URLの確認

```
https://shiny-smoke-04f2.tsubokazu-dev.workers.dev
```

## TradingView アラート設定手順

### ステップ1: チャートを開く

1. TradingView（https://www.tradingview.com/）にログイン
2. テストしたいシンボルのチャートを開く（例: BTCUSD）

### ステップ2: アラートを作成

1. チャート右上の**時計アイコン（アラート）**をクリック
2. 「アラートを作成」を選択

### ステップ3: アラート条件を設定

#### 条件タブ

1. **条件**: 任意の条件を選択（例: 価格が特定の値を上回る/下回る）
   - テスト目的なら簡単な条件でOK（例: `価格 > 0`）
2. **オプション**:
   - 「一度だけ」または「アラートが再び有効になったら」

### ステップ4: 通知設定

#### 通知タブ

1. **Webhook URL**をチェック
2. URLフィールドに以下を入力:
   ```
   https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/
   ```

### ステップ5: メッセージ設定

#### メッセージフィールド

以下のJSON形式のメッセージを入力してください：

#### BUY（買い）シグナルの例

```json
{
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "LONG",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

#### SELL（売り）シグナルの例

```json
{
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "SHORT",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

#### 部分決済シグナルの例

```json
{
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "TP",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

**TradingViewのプレースホルダー変数:**
- `{{ticker}}`: シンボル名（例: BTCUSD）
- `{{interval}}`: タイムフレーム（例: 15、60）
- `{{close}}`: 終値
- `{{time}}`: バー時刻（ISO 8601形式）

### ステップ6: 認証ヘッダーの設定

**重要**: TradingViewのWebhookは現在、カスタムHTTPヘッダーをサポートしていません。
代わりに、以下の2つの方法があります：

#### 方法A: URLにトークンを含める（推奨）

Worker側でクエリパラメータからトークンを受け取るように修正が必要です。

```
https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/?token=YOUR_WEBHOOK_TOKEN
```

#### 方法B: メッセージ内にトークンを含める

```json
{
  "auth_token": "YOUR_WEBHOOK_TOKEN",
  "symbol": "{{ticker}}",
  "timeframe": "{{interval}}",
  "signal": "LONG",
  "price": "{{close}}",
  "bar_time": "{{time}}"
}
```

Worker側で`auth_token`フィールドを検証する必要があります。

**注意**: 現在のWorker実装は`Authorization`ヘッダーを期待しているため、TradingViewから直接使用するには修正が必要です。

### ステップ7: アラートを保存

1. アラート名を入力（例: "BTCUSD Buy Signal"）
2. 「作成」をクリック

## テスト方法

### 手動でアラートをトリガー

1. 作成したアラートの条件を満たすように、チャート上で価格を調整
2. または、簡単な条件（`価格 > 0`など）を設定して即座にトリガー

### ログで確認

#### Producer Worker（Webhook受信）

```bash
wrangler tail
```

**期待される出力:**
```
POST / - 200
Body: {"symbol":"BTCUSD","timeframe":"15","signal":"LONG",...}
```

#### Consumer Worker（シグナル処理）

```bash
wrangler tail --config wrangler.consumer.jsonc
```

**期待される出力:**
```
Processing queue message: LONG for BTCUSD
Saved to PendingSignals KV: pending:BTCUSD:...
```

#### MT5 EA（ポーリング）

MT5のエキスパートログ:
```
[TvBridgePullEA] Received 1 signal(s)
[TvBridgeSignal] Processing BUY signal: key=pending:BTCUSD:...
[TvBridgeTrade] BUY order opened: BTCUSD, lot=0.01
```

## 認証の問題を解決する（暫定対応）

TradingViewがカスタムヘッダーをサポートしていないため、以下の修正をWorker側に適用します：

### index.tsを修正してクエリパラメータ認証をサポート

```typescript
// src/index.ts
// 既存の認証チェックを修正

const authHeader = request.headers.get('Authorization');
const urlParams = new URL(request.url).searchParams;
const tokenParam = urlParams.get('token');

const providedToken = authHeader?.replace('Bearer ', '') || tokenParam;

if (!providedToken || providedToken !== env.WEBHOOK_TOKEN) {
    return new Response('Unauthorized', { status: 401 });
}
```

この修正により、以下の2つの方法で認証できます：
1. Authorizationヘッダー（curl等）
2. クエリパラメータ `?token=XXX`（TradingView）

## シンボルマッピング

TradingViewのシンボル名とブローカーのシンボル名が異なる場合、MAPPING_KVで変換できます：

```bash
# TradingView: BTCUSD → ブローカー: BTCUSD.a
wrangler kv key put "BTCUSD" "BTCUSD.a" --namespace-id bc90751113654108a53da1ef1c6cdff8
```

## トラブルシューティング

### アラートが発火しない

1. アラート条件を確認
2. アラートが「一度だけ」に設定されている場合、再作成が必要

### Webhook URLエラー

- URLが正しいか確認（末尾のスラッシュ`/`を含める）
- Cloudflare Workersがデプロイされているか確認

### 認証エラー（401）

- WEBHOOK_TOKENが正しく設定されているか確認
- URLにトークンパラメータが含まれているか確認

### シグナルがMT5に届かない

1. Consumer Workerが正常に動作しているか確認
2. シンボル名が一致しているか確認（BTCUSD vs BTCUSD.a）
3. MT5 EAの`InpSymbolFilter`が正しく設定されているか確認

## まとめ

TradingViewアラートを使用することで、以下のフローで自動取引が実行されます：

```
TradingView Alert
  ↓ Webhook
Producer Worker (index.ts)
  ↓ Queue
Consumer Worker (consumer.ts)
  ↓ KV Storage
MT5 EA (Polling)
  ↓ 注文実行
MT5 取引口座
```

認証の問題を解決すれば、完全に自動化された取引システムが完成します！
