# TradingViewシグナル中継システム設計書

## 1. 概要
- **目的**: TradingView の招待制インジケータから生成される LONG / SHORT / TP シグナルと MT5 取引環境を接続し、自動売買ロジックを拡張可能な形で運用する。
- **背景**: インジケータ本体のコードにアクセスできないため、アラート機能を利用して外部へシグナルを送信する必要がある。即時応答 (≤3 秒) と安定稼働を両立する中継基盤が求められる。
- **方針**: Cloudflare Workers + Queues + KV を用いたサーバレス構成で「受信」と「判断/発注」を分離し、将来のロジック追加に備える。

## 2. システム要件
### 2.1 機能要件
- TradingView アラートの Webhook を HTTPS で受信し、即時 ACK を返却する。
- 受信イベントをキューに投入し、順序制御と再試行を行う。
- キューコンシューマ側で以下のロジックを実行する。
  - シグナルの正規化・重複排除。
  - シンボルマッピング (TradingView 表記 ↔ ブローカー表記)。
  - レート制御 (同一シンボルの最小インターバル)。
  - 可変 TP / 部分利確 / 反転処理などのビジネスロジック。
  - PendingSignals ストアへ保存し、Polling API 経由で EA が取得・約定できる状態にする。
- 処理状況とエラーをログに記録し、監視に活用できる形で保持する。

### 2.2 非機能要件
- **可用性**: Cloudflareのマネージド基盤を活用し 24/7 で運用。Queue 再試行により一時的な失敗を吸収。
- **レイテンシ**: TradingView → Worker 受信までは Cloudflare PoP を利用して最小化。実行側は非同期のため数秒以内での発注を目標。
- **スケーラビリティ**: Queue によるピークバッファリングを前提に、Consumer Worker のコンカレンシーを調整可能。
- **セキュリティ**: Authorization トークン、Cloudflare Access/WAF、KV を用いた Idempotency で防御。TradingView からの正当なリクエストのみ許可。
- **運用性**: wrangler による IaC、Logpush/Workers Analytics で可視化、環境変数で戦略パラメータを管理。

## 3. 全体アーキテクチャ
```
TradingView Alerts
        │ (Webhook JSON)
        ▼
[Ingress Worker]
        │  └─(即時ACK)
        ▼
Cloudflare Queue "tv_signals"
        ▼
[Queue Consumer Worker]
        │
        ├─ KV (Idempotency / Rate Limit / SymbolMap)
        ├─ PendingSignals ストア (Durable Object / KV)
        └─ Logpush / Monitoring

MT5 EA (pull)
        ▲
        │  (周期 WebRequest)
        └─ [Polling API Worker] ── PendingSignals から取得/ACK
```

## 4. コンポーネント設計
### 4.1 TradingView アラート設定
- 条件: Shingan_Scalp の LONG / SHORT / TP シグナル。
- 発火: Once per bar close 推奨 (リペイント対策)。
- Payload テンプレート:
```json
{
  "signal": "LONG",
  "symbol_tv": "{{ticker}}",
  "timeframe": "{{interval}}",
  "price": "{{close}}",
  "bar_time": "{{timenow}}",
  "chart": "{{exchange}}:{{ticker}}",
  "token": "${TV_WEBHOOK_TOKEN}"
}
```
- token を JSON に含め、受信Workerで検証することでアクセス制御を強化。URL 秘匿と Cloudflare WAF の併用を前提。

### 4.2 受信 Worker (`src/index.ts`) ✅ **実装済み**
- 責務: 認証、入力検証、Idempotency キー生成、Queue への非同期投入。
- エンドポイント:
  - **推奨**: `POST /webhook` (静的アセット競合回避)
  - **後方互換**: `POST /` (旧バージョン対応)
  - 末尾スラッシュの有無は自動正規化
- 認証方法（3つサポート）:
  1. `Authorization: Bearer <WEBHOOK_TOKEN>` ヘッダ（curl等API クライアント向け）
  2. URLクエリパラメータ `?token=<WEBHOOK_TOKEN>`（**TradingView推奨**）
  3. リクエストボディ内の `token` フィールド（TradingView代替）
- 主な処理:
  1. 上記3つのいずれかの方法で認証トークンを検証。
  2. 必須フィールド (signal / symbol / timeframe / bar_time) の検証。
  3. `idem = sha1(symbol|timeframe|signal|bar_time)` を計算。
  4. Queue へメッセージ送信 (`TV_QUEUE.send(...)`)。
  5. HTTP 200 応答 `{"status":"queued","idem":"..."}`。
- エラーハンドリング: バリデーション失敗は 400、認証失敗は 403、それ以外は 500。

### 4.3 Cloudflare Queue
- 名前: `tv_signals`。
- Producer: 受信 Worker。
- Consumer: 後段 Worker (`tv-bridge-consumer`)。
- 可視性タイムアウト: 30 秒 (発注処理に十分な時間を確保)。
- 再試行回数: デフォルト 3 回 → 上限に達したメッセージは Dead Letter Queue (オプション) へ送る。

### 4.4 KV ストア
- `IDEMPOTENCY_KV`: idem キーを TTL 付きで保存 (例: 10 分)。
- `RATELIMIT_KV`: シンボルごとの最終実行時刻 (ミリ秒)。
- `MAPPING_KV`: TradingView シンボルとブローカーシンボルの対応表。例: `XAUUSD -> XAUUSD.a`。
- オプション: `STRATEGY_PARAM_KV` に時間足や銘柄ごとの戦略パラメータを格納。

### 4.5 Consumer Worker (`src/consumer.ts`) ✅ **実装済み**
- イベント処理フロー:
  1. KV で idem を照合 (ヒットなら ACK して終了)。
  2. シンボルマッピングを適用し、許可対象外なら ACK。
  3. Rate limit (最小インターバル) を超過していないかチェック。
  4. 取引ロジック `decideAction()` を実行。
  5. PendingSignals KVにシグナルを保存（`pending:{symbol}:{timestamp}:{idem}` 形式）。
  6. 成功時に ACK、ログへ出力。
- インフラ構成:
  - Webhook受信WorkerとConsumer Workerを別サービスとして管理。
  - `wrangler.jsonc` はProducerバインディングのみ。
  - `wrangler.consumer.jsonc` で Queue コンシューマを定義。
  - Worker名: `tv-bridge-consumer`
- 取引ロジック実装 (`decideAction()`):
  - `LONG` → `{type: 'OPEN', side: 'BUY', volume: DEFAULT_LOT}`
  - `SHORT` → `{type: 'OPEN', side: 'SELL', volume: DEFAULT_LOT}`
  - `TP` / `TP_LONG` / `TP_SHORT` → `{type: 'CLOSE_PARTIAL', volume_ratio: TP_CLOSE_RATIO}`
  - その他のシグナルは `null` を返しACK（未対応シグナル）
- 設定値（環境変数）:
  - `MIN_INTERVAL_MS`: `"2000"` (デフォルト)
  - `DEFAULT_LOT`: `"0.10"`
  - `TP_CLOSE_RATIO`: `"0.5"` (50%部分決済)

### 4.6 Polling API Worker（pull型 EA 連携）✅ **実装済み**
- 役割: MT5 EA が一定間隔でアクセスし、未処理シグナルの取得・ACK を行う HTTP エンドポイントを提供。
- エンドポイント（Producer Workerに統合）:
  - `GET /api/poll?symbol=BTCUSD&limit=10` → 未処理シグナル配列を返却。
    - レスポンス: `{"items": [{key, action, volume, volume_ratio, symbol, bar_time}]}`
    - タイムスタンプ順でソート（古いものから）
  - `POST /api/ack` → EA が約定済みシグナルの `keys` 配列を送信。
    - リクエスト: `{"keys": ["pending:BTCUSD:...", ...]}`
    - レスポンス: `{"acknowledged": 1, "missing": 0}`
- 認証: `Authorization: Bearer <POLL_TOKEN>` (TradingView用トークンとは別管理)
- 実装:
  - PendingSignals KVから `pending:{symbol}:*` でプレフィックス検索
  - ACK時はKVから該当キーを削除
  - TTL: 24時間（自動削除）

### 4.7 PendingSignals ストア設計
- Storage 選択肢:
  - **Durable Object**: 1シンボル1 DO インスタンスで順序保証・再試行制御が容易。
  - **KV + Metadata**: 実装が簡易。`pending:{symbol}:{idem}` をキーに保存し、ACK 時に削除。
- 保存フィールド: `id`（idem）、`symbol_norm`、`timeframe`、`signal`、元の payload、`enqueue_time`、`status`。
- TTL: 24 時間程度。ACK の取りこぼし・EA停止の検知時に警報を出す。

### 4.8 MT5 Pull型EA (`TvBridgePullEA.mq5`) ✅ **実装完了**
- **ファイル構成**:
  - `mt5-ea/Experts/TvBridgePullEA.mq5` - メインEA
  - `mt5-ea/Include/TvBridgeHttp.mqh` - HTTP通信（Poll/Ack）
  - `mt5-ea/Include/TvBridgeJson.mqh` - JSON解析とシグナル構造体
  - `mt5-ea/Include/TvBridgeTrade.mqh` - トレード実行（Buy/Sell/Close/ClosePartial）
  - `mt5-ea/Include/TvBridgeSignal.mqh` - シグナルハンドリング
  - `mt5-ea/Include/TvBridgeLogger.mqh` - ロギング機能
- **動作フロー**:
  1. `OnInit()` でタイマーを設定（デフォルト2秒、設定可能）
  2. `OnTimer()` で定期的に `GET /api/poll` を実行
  3. JSONレスポンスを解析してシグナル配列を取得
  4. 各シグナルに対して注文を実行:
     - `BUY` → 買い注文（0.10ロット）
     - `SELL` → 売り注文（0.10ロット）
     - `CLOSE_PARTIAL` → 指定比率で部分決済
     - `CLOSE` → 全ポジション決済
  5. 成功したシグナルの `key` を収集
  6. `POST /api/ack` で処理済みを通知
  7. KVから削除される
- **パラメータ**:
  - `InpBaseUrl`: Workers URL
  - `InpPollToken`: 認証トークン（`POLL_TOKEN`）
  - `InpSymbolFilter`: フィルタリングするシンボル（例: BTCUSD）
  - `InpPollIntervalSec`: ポーリング間隔（秒）
  - `InpPollLimit`: 1回で取得する最大シグナル数
  - `InpDefaultLot`: デフォルトロットサイズ
  - `InpStopLossPips`: ストップロス（pips、0=無効）
  - `InpTakeProfitPips`: テイクプロフィット（pips、0=無効）
- **エラーハンドリング**:
  - WebRequest失敗時（4060エラー）の検知とログ出力
  - 認証失敗（401/403）の検知
  - 連続エラーカウントとアラート機能
- **ログ機能**:
  - ポーリング成功/失敗のログ
  - シグナル取得・処理状況のログ
  - 注文実行結果のログ
  - ACK送信結果のログ
- **設定要件**:
  - MT5の「WebRequestを許可するURL」に Workers URLを追加
  - VPS環境で24/7稼働推奨

### 4.9 発注ロジック（EA側）✅ **実装完了**
- Polling API から受け取った JSON を基に MT5 内で注文処理。
- シグナル構造体: `{key, action, volume, volume_ratio, symbol, bar_time}`
- アクション解釈:
  - `BUY` → `OrderSend()` で成行買い
  - `SELL` → `OrderSend()` で成行売り
  - `CLOSE_PARTIAL` → `PositionClosePartial()` で部分決済
  - `CLOSE` → `PositionClose()` で全決済
- ロットサイズ正規化: ブローカーの最小ロット・ステップに準拠
- SL/TP計算: ピップス指定からブローカー価格への変換
- ACK は注文が正常完了したタイミングで送信。失敗時は再取得されるよう idempotent 設計。

### 4.9 代替プッシュ構成
- PineConnector など既製ブリッジを併用する場合は、PendingSignals から別Worker経由でPush通知する二経路構成も拡張として検討可。

### 4.10 環境変数・シークレット
- `WEBHOOK_TOKEN`: TradingView Webhook 受信時の認証トークン。
- `MIN_INTERVAL_MS`: 同一シンボルでの最小実行間隔（ミリ秒）。
- `DEFAULT_LOT`: フェーズ1向けのデフォルトロットサイズ（例: `0.10`）。
- `TP_CLOSE_RATIO`: TP シグナルでの部分決済率（0〜1）。
- `POLL_TOKEN`: EA ポーリングAPIの認証トークン。
- Durable Object ID や namespace 名など初期化に必要な値。
- `PC_ENDPOINT`, `PC_KEY`: PineConnector を併用する場合に設定。

## 5. データフロー詳細
1. TradingView がシグナル発生バー確定後に Webhook を送信。
2. 受信 Worker が認証・検証後、Queue にメッセージ投入し即 200 を返す。
3. Queue から Consumer Worker がメッセージを受領。
4. KV 参照による重複排除・レート制御・シンボル変換。
5. `decideAction()` が取引内容を決定。
6. PendingSignals ストアへシグナルを登録（状態: pending）。
7. MT5 EA が `GET /api/poll` で未処理シグナルを取得。
8. EA が MT5 内で注文処理し、成功時に `POST /api/ack` で処理済みに更新。
9. Worker 側で状態を更新し、監視基盤 (Workers Analytics / Logpush / Slack通知) に連携。

## 6. セキュリティ設計
- **認証**: `Authorization: Bearer WEBHOOK_TOKEN` (TradingView がヘッダ不可の場合は Body の token を必須化)。
- **ネットワーク制御**: Cloudflare WAF/Access で TradingView 発信元IPアドレス帯を許可、他を遮断。
- **データ保護**: HTTPS (TLS) 強制、Secrets は Cloudflare Secrets Manager、ログには個人情報を含めない。
- **リプレイ対策**: idem キー + TTL と timestamp チェック (`bar_time` が現在±許容範囲内か検証)。
- **入力検証**: JSONスキーマ (任意) を導入し、フォーマット不正時は 400 で破棄。

## 7. 信頼性・運用
- **再試行**: Consumer Worker で例外が投げられた場合、Queue が自動リトライ。最大リトライ回数超過分は Dead Letter Queue に転送し通知。
- **監視**: Cloudflare Logpush を BigQuery / Datadog 等に連携。重要イベントは Slack / PagerDuty Webhook を追加。
- **可観測性**: `console.log` に requestId, symbol, signal, action, latency を出力。必要に応じて Structured Logging。
- **デプロイ管理**: `wrangler deploy` を GitHub Actions などCIに組み込み、環境 (stg/prod) ごとに wrangler.toml を分割。
- **ロールバック**: Wrangler のバージョン管理と Git タグで追跡。

## 8. テスト計画
- **ユニットテスト**: `decideAction()` や検証関数に対する Vitest ベースのテストを `test/` 配下に追加。
- **統合テスト**: Queue → PendingSignals 登録 → Polling API 取得／ACK までを `unstable_dev` や Vitest モックで検証。
  - Durable Object を採用する場合は DO のローカルテストを追加。
- **ステージング**: Cloudflare の Preview / Separate namespace を使用。TradingView のデモアラートで E2E を確認。
- **運用前確認**: webhook.site で受信 → Queue でのメッセージ到達 → デモ口座で約定までを逐次検証。

## 9. 変更容易性
- 取引ルールや部分利確比率を KV/環境変数で管理し、コードを変更せずに調整可能。
- 新しいシグナル種別が増えた場合は `decideAction()` を拡張し、KVにシンボル別設定を追加。
- MT5 から別プラットフォームへ移行する場合も、Polling クライアントを差し替えるだけで対応可能 (共通フォーマットを維持する前提)。

## 10. リスクと対策
- **TradingView アラート重複**: idem 管理 + レート制御で多重発注を防止。
- **PineConnector 停止**: Dead Letter Queue で検知し、監視通知とフェイルオーバー (予備EAや手動対応) を準備。
- **Cloudflare 障害**: 重大障害時に備え、予備として AWS API Gateway + Lambda の代替ルートを設計しておく。
- **戦略ロジックのバグ**: テストカバレッジを確保し、staging 環境で数日間デモ運用してから本番投入。

## 11. 実装済みドキュメント

### MT5 EA関連
- **完全ガイド**: `mt5-ea/README.md` - EA設定、パラメータ、トラブルシューティング
- **クイックスタート**: `mt5-ea/QUICKSTART.md` - 5分でセットアップ
- **動作確認ガイド**: `mt5-ea/TEST_POLLING.md` - ポーリング動作のテスト方法
- **設定例**: `mt5-ea/TvBridgePullEA_Settings_Example.txt` - パラメータ設定サンプル

### TradingView連携
- **詳細ガイド**: `docs/tradingview_alert_setup.md` - アラート設定の完全手順
- **クイックスタート**: `docs/tradingview_quickstart.md` - 5分でアラート設定
- **実装指示書**: `docs/mt5_pull_ea_guide.md` - Pull型EA実装仕様

### テストスクリプト
- `test-webhook.sh` - Webhook動作確認スクリプト
- `test-signal.sh` - テストシグナル送信スクリプト

### 運用URL
- **Webhook**: `https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/webhook?token=XXX`
- **Polling API**: `https://shiny-smoke-04f2.tsubokazu-dev.workers.dev/api/poll?symbol=XXX&limit=N`

## 12. 今後の拡張案
- Durable Object を用いたポジション情報キャッシュとリアルタイムダッシュボード。
- 多通貨対応の戦略パラメータ管理 (KV → D1 設定画面)。
- アラート内容に SL/TP/ロット指定を含めるテンプレ対応。
- 発注結果を逆方向に通知する Slack/Telegram Bot。
- MT5 以外 (cTrader, NinjaTrader 等) への拡張モジュール化。
- CLOSEシグナルの実装（全ポジション決済）。

---
**本設計書の実装状況**: フェーズ1完了（2025-10-28）。TradingView → Cloudflare Workers → MT5 の完全なパイプラインが稼働中。実際の取引で動作確認済み。
