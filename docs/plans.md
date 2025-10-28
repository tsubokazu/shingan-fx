# 段階的実装計画

## 0. ゴールとスコープ
- TradingView の LONG / SHORT / TP アラートを Cloudflare Workers で受信し、自作EAが稼働する MT5 環境へ自動発注。
- フェーズ1で最低限の自動売買パイプライン（Webhook受信→キュー→EA発注）を完成させ、以降は信頼性・ロジック精緻化を段階追加。

## 1. 前提と準備
- [x] Cloudflare アカウント、Workers / Queues / KV 利用権限を整える。
- [x] ローカル開発環境（Node.js 18+, `wrangler` CLI, Git）をセットアップ。
- [x] MT5 が稼働する VPS/PC と、自作EA受信API（REST/ZeroMQ等）を用意。
- [x] TradingView Pro 以上のアカウントで Webhook アラート利用を確認。

## 2. フェーズ構成

### フェーズ1: 最小ルートの構築（Webhook→Queue→EA）✅ **完了**
- [x] wrangler プロジェクトの環境変数・バインディングを設定。
- [x] `wrangler.jsonc` の Queue 名称や KV Namespace ID を本番値へ差し替える。
- [x] 受信Worker (`src/index.ts`) を実装。
  - [x] Authorization検証・必須フィールドチェック・Idempotencyキー生成を組み込む。
  - [x] Queue へのメッセージ送信と即時ACK処理を実装。
  - [x] URLクエリパラメータ認証を追加（TradingView対応）。
  - [x] `/webhook` エンドポイントを追加（静的アセットとの競合回避）。
- [x] Queue `tv_signals` と KV (`IDEMPOTENCY_KV`, `RATELIMIT_KV`, `MAPPING_KV`, `PENDING_SIGNALS_KV`) を作成。
- [x] Consumer Worker (`src/consumer.ts`) を最小実装。
  - [x] 別サービス用 `wrangler.consumer.jsonc` を作成し、Queueコンシューマ設定を追加。
  - [x] KV 参照による重複排除・シンボル変換・レート制御を実装。
  - [x] PendingSignals ストア（KV）へシグナルを蓄積する処理を実装。
- [x] Polling API Worker を実装し、`GET /api/poll` と `POST /api/ack` を提供。
- [x] EA ポーリング用の認証トークン (`POLL_TOKEN`) を設定。
- [x] **MT5 Pull型EA (`TvBridgePullEA.mq5`) を実装・デプロイ完了**。
  - [x] 10秒間隔でポーリング、シグナル取得、注文実行、ACK送信。
  - [x] HTTP通信、JSON解析、トレード実行モジュールを実装。
  - [x] デバッグログとエラーハンドリングを組み込み。
- [x] TradingView 側でテストアラートを作成し、受信Workerへ接続完了。
- [x] **エンドツーエンドテスト完了**: TradingView → Workers → MT5で実際の取引が成功。

### フェーズ2: 運用レディ化
- [ ] PendingSignals の TTL／再取得ルール／重複防止を整備。
- [ ] Polling API のレート制限・署名検証・IP 制限を導入。
- [ ] KV にシンボルマッピングとロット/SLTP初期設定を登録。
- [ ] Cloudflare WAF ルール・Access を構成し、IP/トークン制御を強化。
- [ ] Logpush / Workers Analytics を可視化基盤へ連携し、運用ダッシュボードを整備。
- [ ] 監視通知（Slack/PagerDuty など）を組み込み。

### フェーズ3: 戦略ロジックの拡張
- [ ] `decideAction()` に可変ロット、部分利確、反転処理を実装。
- [ ] ATRやR倍数などの参考指標を入力する外部データ/API連携を追加（Durable Object 検討）。
- [ ] StrategyパラメータをKVや環境変数で柔軟管理できるDTOを設計。
- [ ] 単体テスト（Vitest）と統合テストを追加し、自動化。

### フェーズ4: フォールトトレランスと拡張
- [ ] Dead Letter Queue の監視と再処理フローを構築。
- [ ] フェイルオーバー環境（AWS Gateway + Lambda 等の代替ルート）を検討・設計。
- [ ] 複数EAや他プラットフォーム (cTrader 等) への対応モジュールを追加。

## 3. マイルストーンと完了条件
| フェーズ | 完了条件 | 成果物 | ステータス |
| --- | --- | --- | --- |
| 1 | TradingViewテストアラートが Polling API 経由で MT5 EAへ届き約定。 | 受信Worker・Consumer Worker・PendingSignals・Polling API・MT5 EA完成版。 | ✅ **完了** (2025-10-28) |
| 2 | エラー発生時に再試行もしくは通知で検知できる。 | PendingSignals管理、監視ダッシュボード、通知基盤。 | 未着手 |
| 3 | ロジック変更をコード修正なしでロールアウト可能。 | decideAction拡張、設定管理、テスト充実。 | 未着手 |
| 4 | 障害時にフェイルオーバーまたは手動対応手順が明文化。 | DR手順書、代替ルート。 | 未着手 |

## 4. 役割と責務（例）
- **アラート整備担当**: TradingView設定、運用監視、フィードバック取得。
- **インフラ担当**: Cloudflare設定、WAF/Access、wranglerデプロイ管理。
- **ロジック担当**: PendingSignals / Polling API / `decideAction()` のロジック実装、テスト。
- **運用担当**: ログ/通知モニタリング、手動介入手順整備。

## 5. リスクとフォローアップ
- TradingViewのアラート遅延・重複 → フェーズ1でIdempotencyとレート制御を必須化。
- EA ポーリング処理の停止 → フェーズ2で再取得/アラート通知を取り入れ、手動発注手順を整備。
- ロジック不具合による誤発注 → フェーズ3でテスト拡充、ステージング（デモ口座）で48hバーンイン。
- Cloudflare 障害 → フェーズ4でバックアップルートを設計。

---
本計画はフェーズ1の達成（Webhook受信→PendingSignals→Polling API→MT5デモ取引まで）を最優先とし、以降は運用状況に応じてフェーズ2以降を段階的に実行する。
