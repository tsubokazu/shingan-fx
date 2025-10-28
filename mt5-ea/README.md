# TvBridge Pull EA

TradingViewシグナルをCloudflare WorkersのAPIからポーリングして、MT5で自動取引を実行するExpert Advisorです。

## 概要

このEAは、Cloudflare Workersが提供するPull型API（`/api/poll`と`/api/ack`）を使用して、TradingViewからのシグナルを定期的に取得し、MT5で自動的に取引を実行します。

### 主な機能

- **定期ポーリング**: 1～3秒間隔でシグナルをポーリング
- **自動取引実行**: BUY/SELL/CLOSE/CLOSE_PARTIALアクションを自動実行
- **ACK機能**: 正常に処理されたシグナルをサーバーに通知
- **エラーハンドリング**: 連続エラー時のアラート機能
- **詳細ログ**: Journal/ファイルへのログ出力

## ディレクトリ構造

```
mt5-ea/
├── Experts/
│   └── TvBridgePullEA.mq5       # メインEAファイル
├── Include/
│   ├── TvBridgeHttp.mqh         # HTTP通信ユーティリティ
│   ├── TvBridgeJson.mqh         # JSON解析ユーティリティ
│   ├── TvBridgeSignal.mqh       # シグナル処理
│   ├── TvBridgeTrade.mqh        # トレード実行
│   └── TvBridgeLogger.mqh       # ロギング機能
└── README.md                     # このファイル
```

## インストール手順

### 1. ファイルのコピー

1. MT5のデータフォルダを開く:
   - MT5メニュー: `ファイル > データフォルダを開く`

2. 以下のファイルをコピー:
   ```
   mt5-ea/Experts/TvBridgePullEA.mq5
     → MQL5/Experts/TvBridgePullEA.mq5

   mt5-ea/Include/*.mqh
     → MQL5/Include/*.mqh
   ```

### 2. MT5の設定

#### WebRequest許可設定

1. MT5メニュー: `ツール > オプション > Expert Advisors`
2. 「WebRequestを許可するURL」に以下を追加:
   ```
   https://tv-bridge.example.com
   ```
   ※実際のCloudflare WorkersのURLに置き換えてください

3. 以下のオプションも確認:
   - ☑ 自動売買を許可する
   - ☑ DLLの使用を許可する（任意）

#### EAのコンパイル

1. MT5の「MetaEditor」を開く（F4キー）
2. `TvBridgePullEA.mq5`を開く
3. コンパイル（F7キー）
4. エラーがないことを確認

### 3. EAのパラメータ設定

チャートにEAをドラッグ&ドロップし、以下のパラメータを設定します。

#### API Settings（必須）

| パラメータ | 説明 | 例 |
|----------|------|-----|
| InpBaseUrl | Cloudflare WorkersのベースURL | `https://tv-bridge.example.com` |
| InpPollToken | ポーリング認証トークン | `your-poll-token-here` |

#### Polling Settings

| パラメータ | 説明 | デフォルト値 | 推奨値 |
|----------|------|------------|--------|
| InpSymbolFilter | フィルタリングするシンボル | `EURUSD` | 取引したいシンボル |
| InpPollIntervalSec | ポーリング間隔（秒） | `2` | `1-3` |
| InpPollLimit | 1回のポーリングで取得する最大シグナル数 | `10` | `5-20` |

#### Trade Settings

| パラメータ | 説明 | デフォルト値 |
|----------|------|-----------|
| InpDefaultLot | デフォルトロットサイズ | `0.01` |
| InpStopLossPips | ストップロス（pips、0=無効） | `0` |
| InpTakeProfitPips | テイクプロフィット（pips、0=無効） | `0` |
| InpSlippagePoints | 最大スリッページ（ポイント） | `10` |
| InpTradeComment | トレードコメント | `TvBridge` |

#### Error Handling

| パラメータ | 説明 | デフォルト値 |
|----------|------|-----------|
| InpMaxConsecutiveErrors | アラートを出すまでの連続エラー数 | `5` |

#### Logging

| パラメータ | 説明 | デフォルト値 |
|----------|------|-----------|
| InpLogLevel | ログレベル（DEBUG/INFO/WARNING/ERROR） | `INFO` |
| InpEnableFileLogging | ファイルへのログ出力を有効化 | `false` |
| InpLogFileName | ログファイル名 | `TvBridgeEA.log` |

## 使用方法

### 1. EAの起動

1. 取引したいシンボルのチャートを開く
2. ナビゲーターから`TvBridgePullEA`をチャートにドラッグ
3. パラメータを設定
4. 「OK」をクリック

### 2. 動作確認

EAが正常に動作していることを確認します：

1. **ジャーナルログを確認**:
   - `[TvBridgePullEA] Initialized successfully`が表示される
   - 定期的にポーリングログが表示される

2. **チャート上の情報を確認**:
   - チャート左上にEAのステータスが表示される
   - 処理済みシグナル数が表示される

3. **エキスパートログを確認**:
   - 各シグナルの処理状況が記録される

### 3. トレードの実行フロー

1. **ポーリング**: 設定された間隔でAPIから未処理シグナルを取得
2. **解析**: JSONレスポンスからシグナル情報を抽出
3. **実行**: 各シグナルに応じてトレードを実行
   - `BUY`: 買いポジションをオープン
   - `SELL`: 売りポジションをオープン
   - `CLOSE`: 指定シンボルの全ポジションをクローズ
   - `CLOSE_PARTIAL`: 指定割合でポジションを部分決済
4. **ACK**: 正常に処理されたシグナルをサーバーに通知

## トラブルシューティング

### WebRequestエラー（エラーコード4060）

**症状**: `[TvBridgeHttp] WebRequest error: 4060`

**原因**: URLが許可リストに含まれていない

**解決方法**:
1. MT5メニュー: `ツール > オプション > Expert Advisors`
2. 「WebRequestを許可するURL」に正しいURLを追加
3. MT5を再起動

### 認証エラー（Status: 401/403）

**症状**: `[TvBridgeHttp] Poll failed. Status: 401`

**原因**: 認証トークンが無効または未設定

**解決方法**:
1. `InpPollToken`パラメータを確認
2. Cloudflare Workersの環境変数`POLL_TOKEN`と一致しているか確認

### シグナルが処理されない

**症状**: シグナルが取得されるが、トレードが実行されない

**確認事項**:
1. **自動売買が有効**: MT5の「自動売買」ボタンが緑色
2. **口座資金**: 十分な証拠金があるか
3. **シンボル**: 正しいシンボル名が使用されているか
4. **ロットサイズ**: ブローカーの最小ロットサイズを満たしているか

### 連続エラーアラート

**症状**: `TvBridge EA: X consecutive poll failures!`

**原因**: APIサーバーとの通信に問題がある

**確認事項**:
1. インターネット接続
2. Cloudflare Workersが稼働しているか
3. URLが正しいか

## 高度な設定

### VPS環境での24/7稼働

1. VPSにMT5をインストール
2. EAを設定
3. 自動起動設定:
   - Windowsの「スタートアップ」フォルダにMT5のショートカットを配置
   - ログインプロファイルを保存（自動的にEAが起動）

### 複数シンボルの監視

現在のEAは1シンボルのみをフィルタリングします。複数シンボルを監視する場合:

1. 各シンボル用のチャートを開く
2. 各チャートに別々のEAインスタンスを設定
3. `InpSymbolFilter`パラメータをそれぞれ異なるシンボルに設定

または、`InpSymbolFilter`を空文字列に設定して全シンボルのシグナルを受け取る（コード修正が必要）。

### ログファイルの確認

ファイルログを有効にした場合:

1. MT5データフォルダを開く: `ファイル > データフォルダを開く`
2. `MQL5/Files/TvBridgeEA.log`を確認

## セキュリティ注意事項

1. **トークンの保護**:
   - `InpPollToken`は安全に管理してください
   - プリセットファイル（.set）をGitにコミットしないでください

2. **WebRequest許可URL**:
   - 信頼できるURLのみを許可してください
   - ワイルドカードは使用しないでください

3. **バックテスト**:
   - 本番環境で使用する前に、デモ口座で十分にテストしてください

## サポート

問題が発生した場合:

1. ジャーナルログを確認
2. エキスパートログを確認
3. ログレベルを`DEBUG`に変更して詳細情報を取得
4. プロジェクトのIssueに報告

## ライセンス

このプロジェクトはTvBridgeプロジェクトの一部です。

## 更新履歴

### v1.00 (2025-10-28)
- 初回リリース
- Pull型APIとの統合
- BUY/SELL/CLOSE/CLOSE_PARTIALアクション対応
- エラーハンドリングとロギング機能
