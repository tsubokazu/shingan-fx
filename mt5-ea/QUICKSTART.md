# TvBridge Pull EA - クイックスタートガイド

## 5分でセットアップ

### ステップ 1: ファイルのインストール

1. MT5を開き、**ファイル > データフォルダを開く**
2. 以下のファイルをコピー:
   ```
   Experts/TvBridgePullEA.mq5  → MQL5/Experts/
   Include/*.mqh               → MQL5/Include/
   ```

### ステップ 2: MT5の設定

1. **ツール > オプション > Expert Advisors**を開く
2. 以下をチェック:
   - ☑ 自動売買を許可する
3. **WebRequestを許可するURL**に追加:
   ```
   https://your-worker.workers.dev
   ```
   ※実際のCloudflare Workers URLに置き換え

### ステップ 3: EAのコンパイル

1. **F4**キーでMetaEditorを開く
2. `TvBridgePullEA.mq5`を開く
3. **F7**キーでコンパイル
4. エラーがないことを確認

### ステップ 4: EAの起動

1. 取引したいチャートを開く（例: EURUSD）
2. ナビゲーターから`TvBridgePullEA`をチャートにドラッグ
3. パラメータを設定:

   **必須項目**:
   - `InpBaseUrl`: `https://your-worker.workers.dev`
   - `InpPollToken`: Cloudflare Workersの`POLL_TOKEN`

   **推奨設定**:
   - `InpSymbolFilter`: `EURUSD`（チャートのシンボルに合わせる）
   - `InpPollIntervalSec`: `2`
   - `InpDefaultLot`: `0.01`

4. **OK**をクリック

### ステップ 5: 動作確認

1. **ターミナル > エキスパート**タブを確認
2. 以下のメッセージが表示されるはず:
   ```
   [TvBridgePullEA] Initialized successfully
   [TvBridgePullEA] Base URL: https://...
   ```

3. チャート左上にステータスが表示される

## トラブルシューティング

### エラー: WebRequest error: 4060

**解決**: MT5の「WebRequestを許可するURL」にAPIのURLを追加してください

### エラー: Status: 401

**解決**: `InpPollToken`パラメータが正しく設定されているか確認してください

### シグナルが取得されない

**確認事項**:
1. Cloudflare Workersが稼働しているか
2. TradingViewアラートが正しく設定されているか
3. `InpSymbolFilter`がチャートのシンボルと一致しているか

## 次のステップ

- 詳細な設定は[README.md](README.md)を参照
- 設定例は`TvBridgePullEA_Settings_Example.txt`を参照
- 本番環境で使用する前に、デモ口座で十分にテストしてください

## サポート

問題が発生した場合は、ログレベルを`DEBUG`に変更して詳細情報を確認してください。
