# MT5 Pull型EA 実装ガイド

## 1. 概要
Cloudflare Workers で提供される `GET /api/poll` と `POST /api/ack` を利用し、MT5 上で定期的にシグナルを取得・約定・ACK する EA の実装フローをまとめます。EA は以下の機能を持つ必要があります。

- `WebRequest()` で Workers にアクセスできるよう WebRequest 許可設定を追加。
- 一定間隔（例: 1 秒～3 秒）で `GET /api/poll?symbol=XXX&limit=N` を呼び出す。
- 取得したシグナルを解析し、ロット、方向、部分決済指示などに応じて注文/決済を実行。
- 正常に処理したシグナルの `key` を `POST /api/ack` にまとめて送信。
- 例外・エラー時はローカルログ/通知で確認できるようにする。

## 2. MT5 側の事前設定
1. MT5 の「ツール > オプション > Expert Advisors」で以下を設定:
   - 「WebRequest を許可するURL」に Cloudflare Workers の URL（例: `https://tv-bridge.example.com`）を追加。
   - EA の DLL 使用は不要。
2. VPS など 24/7 で稼働できる環境に MT5 を配置。
3. `POLL_TOKEN` を EA 内で安全に保持（ハードコードを避け、外部ファイル参照を推奨）。

## 3. シグナル処理アルゴリズム
1. `OnInit()`:
   - タイマーを `EventSetTimer(intervalSeconds)` でセット（1～3秒程度）。
   - 必要パラメータ（ロット、SL/TP、ポジション保持数など）を入力変数で受け取る。
2. `OnTimer()`:
   - `HttpGetPendingSignals()` で `GET /api/poll` を呼び出し JSON を取得。
   - `ParseSignals()` で JSON を配列に変換。`items` フィールドが未処理シグナル。
   - 各シグナルについて `HandleSignal()` を呼び出し、方向に応じて `OrderSend` / `OrderClose` 等を実行。
   -  成功したシグナルの `key` をリスト化。
   - `HttpAckSignals()` で `POST /api/ack` に成功一覧を送信。
3. 約定失敗時は:
   - ローカルログ (`Print`) や `Alert` で通知。
   - ACK は送らず、次回ポーリング時に再取得されるようにする。
4. `OnDeinit()`:
   - `EventKillTimer()` でタイマー停止。

## 4. HTTP ユーティリティ実装例（擬似コード）
```mq5
input string InpBaseUrl = "https://tv-bridge.example.com";
input string InpPollToken = "<POLL_TOKEN>";
input string InpSymbolFilter = "EURUSD";
input int    InpPollIntervalSec = 2;
input int    InpPollLimit = 5;

string HttpGetPendingSignals(string symbol, int limit)
{
   string url = StringFormat("%s/api/poll?symbol=%s&limit=%d", InpBaseUrl, symbol, limit);
   string headers = "Authorization: Bearer " + InpPollToken + "\r\n";
   char data[];
   int res = WebRequest("GET", url, headers, 5000, NULL, 0, data, NULL);
   if(res != 200)
   {
      PrintFormat("[EA] Poll failed. status=%d", res);
      return "";
   }
   return CharArrayToString(data);
}

bool HttpAckSignals(const string &ackBody)
{
   string url = InpBaseUrl + "/api/ack";
   string headers = "Authorization: Bearer " + InpPollToken + "\r\nContent-Type: application/json\r\n";
   char data[];
   int res = WebRequest("POST", url, headers, 5000, ackBody, StringLen(ackBody), data, NULL);
   if(res != 200)
   {
      PrintFormat("[EA] Ack failed. status=%d body=%s", res, CharArrayToString(data));
      return false;
   }
   return true;
}
```

## 5. シグナル → 注文変換サンプル
```mq5
struct Signal
{
   string key;
   string action;   // "BUY", "SELL", "CLOSE", "CLOSE_PARTIAL"
   double volume;
   double volume_ratio;
   string symbol;
   string bar_time;
};

bool HandleSignal(const Signal &sig)
{
   if(sig.action == "BUY")
      return OpenBuy(sig.symbol, sig.volume);
   if(sig.action == "SELL")
      return OpenSell(sig.symbol, sig.volume);
   if(sig.action == "CLOSE_PARTIAL")
      return ClosePartial(sig.symbol, sig.volume_ratio);
   if(sig.action == "CLOSE")
      return CloseAll(sig.symbol);
   return false;
}
```

各アクションに対して、ブローカーの口座仕様（ヘッジ/ネッティング、最小ロット、ステップ）を踏まえた詳細ロジックを実装してください。

## 6. エラーハンドリング・再試行
- WebRequest が失敗した場合は次回タイマーで再試行し、連続失敗回数を監視してアラートを出す。
- ACK 失敗時はレスポンスをログに残し、同じキーを再度送信。
- 大量の未処理が残っている場合はポーリング間隔を短縮するなど調整。

## 7. 監視・運用
- EA 内で `Journal` ログに処理結果を出力し、VPS の監視ツールで確認。
- 必要に応じて Slack / Discord などの通知サービスと連携。
- 週1回は PendingSignals に溜まり続けるシグナルがないか確認。

---
このガイドをベースに EA を実装すれば、Cloudflare Workers が提供する pull 型パイプラインと直接連携できます。不明点があれば追加で相談してください。
