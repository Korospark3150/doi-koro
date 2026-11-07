# nakolog（LINE風チャット）

元のLINE風CSS・アイコン・41種類のスタンプを使い、ホーム / AI / トーク / スタンプの4画面を下部メニューで切り替えられるWebアプリです。

## 画面と機能
- **ホーム**：AI、トーク、スタンプへのショートカットと最近のトーク
- **AI**：Gemini 2.5 Flashとの会話、Supabaseへの会話履歴保存、音声入力・読み上げ
- **トーク**：表示名でユーザー検索、1対1メッセージ、リアルタイム更新
- **スタンプ**：41種類のスタンプをAIまたは開いているトークへ送信
- **名前登録**：メールアドレスなしのSupabase匿名ログイン
- Supabase URLとPublishable/anon keyは `config.js` の1か所だけで設定

## 1. Supabase設定
1. Supabaseプロジェクトの Authentication 設定で **Anonymous Sign-Ins（匿名ログイン）** を有効にします。
2. SQL Editorで `supabase/schema.sql` 全体を実行します。既存の `chat_messages` があっても実行できるようにしています。
3. `config.js` の `SUPABASE_URL` と `SUPABASE_ANON_KEY` を自分のプロジェクトの値に置き換えます。Publishable key（または旧anon key）のみを使用してください。Secret/service-role keyは絶対にブラウザへ入れないでください。

## 2. Geminiの設定
1. Supabase Dashboardの Edge Functions / Secrets に `GEMINI_API_KEY` を登録します。
2. `supabase/functions/gemini-chat/index.ts` を `gemini-chat` Edge Functionとしてデプロイします。
3. Edge Functionの公開後、AI画面から送信して応答を確認します。

Gemini APIキーは `index.html`、`app.js`、`config.js` に書かないでください。

## 3. 開き方
`chat_line_css/index.html` を開きます。ネット接続が必要です。音声入力はEdge/Chromeで、必要に応じてHTTPSまたはlocalhostから使ってください。

## 4. トークの使い方
1. 名前を登録します。
2. 相手もnakologで名前登録を済ませている必要があります。
3. 下の「トーク」→名前を検索→相手を押すと1対1トークが開きます。
4. 送信したメッセージは `direct_messages` に保存され、Realtime設定が有効なら相手側にも更新が届きます。

## 注意
- 匿名アカウントはメールアドレスに紐づいていません。ブラウザのデータを消すと同じアカウントに戻れない場合があります。
- 表示名は本人確認ではなく、同じ名前を別の人が使える仕様です。
- AI機能にはGemini APIキーとEdge Functionのデプロイが必要です。
- Supabaseの設定とデプロイは利用者のプロジェクト側で必要です。アプリのコードを置いただけで、こちらからSupabaseへログインやデプロイは行っていません。
