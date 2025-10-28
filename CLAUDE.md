# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

TradingViewシグナルをMT5取引環境に中継するサーバレスシステム（Cloudflare Workers）。
- `tv-bridge/shiny-smoke-04f2/`: Cloudflare Workers プロジェクト
- TradingViewアラートをWebhookで受信し、Queueを介して処理、MT5 EAがPolling APIで取得

## 開発コマンド

### プロジェクトディレクトリ
すべての作業は `tv-bridge/shiny-smoke-04f2/` で行う。

### ローカル開発
```bash
npm run dev          # Producer Worker (Webhook受信)を起動
wrangler dev --config wrangler.consumer.jsonc  # Consumer Workerを起動
```

### テスト
```bash
npm test            # 全テスト実行
npm run lint        # TypeScript型チェック
```

### デプロイ
```bash
npm run deploy      # Producer Workerをデプロイ
wrangler deploy --config wrangler.consumer.jsonc  # Consumer Workerをデプロイ
```

### 型定義生成
```bash
npm run cf-typegen  # Cloudflare Workersの型定義を生成
```

## アーキテクチャ

### 2層構成のWorker
1. **Producer Worker** (`src/index.ts`):
   - TradingView Webhookを受信
   - 認証・バリデーション後、Queueに投入
   - エンドポイント: `POST /` (Webhook), `GET /api/poll`, `POST /api/ack`

2. **Consumer Worker** (`src/consumer.ts`):
   - Queueからメッセージを受信し処理
   - 重複排除、シンボルマッピング、レート制限を適用
   - トレードディレクティブを判定し、PendingSignals KVに保存

### Cloudflareリソース
- **Queue**: `tv_signals` - Producer→Consumer間の非同期メッセージング
- **KV Namespaces**:
  - `IDEMPOTENCY_KV`: 重複排除（SHA-1 hash）
  - `RATELIMIT_KV`: シンボルごとの最終実行時刻
  - `MAPPING_KV`: TradingViewシンボル↔ブローカーシンボルのマッピング
  - `PENDING_SIGNALS_KV`: MT5 EAがポーリングで取得する保留中シグナル

### 設定ファイル
- `wrangler.jsonc`: Producer Worker設定（Queueプロデューサー、KV、環境変数）
- `wrangler.consumer.jsonc`: Consumer Worker設定（Queueコンシューマー）
- KV Namespace IDは各設定ファイルの `__REPLACE_*_NS__` を実際のIDに置き換える

### 環境変数
- `WEBHOOK_TOKEN`: TradingView Webhook認証トークン（シークレット）
- `POLL_TOKEN`: MT5 EA Polling API認証トークン（シークレット）
- `MIN_INTERVAL_MS`: レート制限の最小間隔（ミリ秒）
- `DEFAULT_LOT`: デフォルトロットサイズ
- `TP_CLOSE_RATIO`: TP時の部分決済比率

## シグナル処理フロー

1. TradingView → `POST /` → 認証/検証 → Queue送信 → 即時ACK
2. Queue → Consumer → 重複排除 → シンボルマッピング → レート制限チェック
3. Consumer → `decideAction()` → PendingSignals KVに保存
4. MT5 EA → `GET /api/poll?symbol=XXX` → シグナル取得 → `POST /api/ack` → KVから削除

## テスト戦略

- `test/pipeline.test.ts`: エンドツーエンドのパイプラインテスト
- `test/smoke.test.ts`: 基本的なスモークテスト
- InMemoryKV/TestQueueでローカルテスト可能

## 重要な設計パターン

### 冪等性保証
- `idem = sha1(symbol|timeframe|signal|bar_time)` で一意キーを生成
- Consumer側で `IDEMPOTENCY_KV` を照合し重複を排除

### シグナル判定ロジック (`consumer.ts:decideAction`)
- `LONG` → `{type: 'OPEN', side: 'BUY', volume: DEFAULT_LOT}`
- `SHORT` → `{type: 'OPEN', side: 'SELL', volume: DEFAULT_LOT}`
- `TP/TP_LONG/TP_SHORT` → `{type: 'CLOSE_PARTIAL', volume_ratio: TP_CLOSE_RATIO}`
- 未知のシグナルは `null` を返し、ACKして終了

### PendingSignal Key形式
```
pending:{symbol}:{timestamp(13桁)}:{idem}
```
- タイムスタンプでソート可能
- シンボルでフィルタリング可能（Polling APIで使用）

## 開発時の注意点

- シークレット（WEBHOOK_TOKEN, POLL_TOKEN）は `wrangler secret put` で設定
- KV Namespaceは事前に `wrangler kv namespace create` で作成し、IDを設定ファイルに反映
- Queueは `wrangler queues create tv_signals` で作成
- Consumer Workerは別途デプロイが必要（2つの独立したWorker）
- `docs/system_design.md` に詳細な設計ドキュメントあり
