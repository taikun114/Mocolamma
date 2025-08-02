# 初めにお読みください（For AI）

## このドキュメントについて

このドキュメントは、生成AIのチャットスレッドが新しくなってもスムーズに引き継ぎできるよう、プロジェクトの基本情報と引き継ぎに必要な情報が記載されています。

このドキュメントを受け取ったあなたは、このドキュメント内の情報を確認し、チャットを送るようにしてください。また、ユーザから新たな依頼や「必ずこうして欲しい」など、今後も守るべき情報を受け取った場合はこのドキュメントの中に追記してください。

### このドキュメントを編集する際は

あなたがこのドキュメントを編集する際、ユーザには生のマークダウンデータとして提供する必要があります。
つまり、このドキュメントの最も上と最も下に、8つ以上の「`」で囲み、大きなコードブロックとして提供してください。

## プロジェクトについて

プロジェクト名: `Mocolamma`\
プロジェクトのバンドル識別子: `design.taikun.Mocolamma`

このプロジェクトは、Ollama APIを使ってOllamaの様々な管理を行うmacOS用のSwiftアプリケーションです。\
名前の由来は「**Mo**del」「**Co**ntrol」「Ol**lam**a」「**Ma**nage」を組み合わせた造語です。

### プロジェクトの構造

```
Mocolamma
├── AddModelsSheet.swift
├── ChatInputView.swift
├── ChatMessagesView.swift
├── ChatView.swift
├── CommandExecutor.swift
├── ContentView.swift
├── LicenseTextView.swift
├── MessageInputView.swift
├── ModelDetailsView.swift
├── ModelListView.swift
├── MocolammaApp.swift
├── OllamaChat.swift
├── OllamaModel.swift
├── ServerFormView.swift
├── ServerInfo.swift
├── ServerInspectorView.swift
├── ServerManager.swift
├── ServerRowView.swift
├── ServerView.swift
└── SettingsView.swift
```

新たなファイルを作成した場合はこの構造に新たなファイルを追加してください。

### 各コードの役割

新たなファイルが作成された場合や機能に変更があった場合は以下の文章を変更・追加してください。コードの変更履歴を記載するものではありません。コードの役割のみを説明する必要があります。

#### `MocolammaApp.swift`

アプリケーションのエントリーポイントです。メインウィンドウと`ContentView`を初期化し、アプリケーション全体で利用する`ServerManager`と`CommandExecutor`を環境オブジェクトとして設定します。

#### `ContentView.swift`

アプリケーションのメインUIを構成するビューです。`NavigationSplitView`を使用し、サイドバーで`ServerView`、`ModelListView`、`ChatView`、`SettingsView`を切り替えて表示します。

#### `ChatView.swift`

Ollamaモデルとのチャット機能を提供するメインビューです。メッセージの送受信、履歴表示、リビジョン管理などのUIとビジネスロジックを管理します。

#### `ChatMessagesView.swift`

`ChatView`内で使用され、チャットメッセージのリストを表示する責務を負います。各メッセージは`MessageView`としてレンダリングされます。

#### `MessageView.swift`

個々のメッセージバブル、思考プロセス、リビジョン機能、メタデータ（トークン数、生成速度など）の表示を担当します。ホバーエフェクトで統計情報や操作ボタンを表示します。

#### `ChatInputView.swift`

`ChatView`の下部に配置される入力コンポーネントです。テキスト入力フィールド、送信ボタン、ストリーミング停止ボタンを提供します。

#### `ServerView.swift`

登録されているOllamaサーバーのリストを表示・管理するビューです。サーバーの追加、削除、選択などの操作を提供します。

#### `ServerRowView.swift`

`ServerView`のリスト内の各サーバー情報を表示するためのビューコンポーネントです。

#### `ServerFormView.swift`

新規サーバーの追加や既存サーバーの編集を行うためのフォームを提供するシートビューです。

#### `ServerInspectorView.swift`

`ServerView`で選択されたサーバーの詳細情報をインスペクター領域に表示します。

#### `ModelListView.swift`

利用可能なモデルの一覧を表示・管理するビューです。モデルの削除や詳細情報の表示機能を提供します。

#### `ModelDetailsView.swift`

`ModelListView`で選択されたモデルの詳細情報を表示します。

#### `AddModelsSheet.swift`

Ollamaライブラリからモデルを検索し、ダウンロードして追加するためのシートビューです。

#### `SettingsView.swift`

アプリケーション全体の設定（チャット設定、システムプロンプトなど）を行うビューです。

#### `LicenseTextView.swift`

アプリケーションのライセンス情報を表示するためのビューです。

#### `CommandExecutor.swift`

Ollama APIとの通信を非同期で実行し、結果をビューモデルに反映させる中心的なクラスです。チャットの実行、モデル情報の取得、モデルのプルと削除など、アプリケーションの主要なロジックを担います。

#### `ServerManager.swift`

Ollamaサーバーの追加、削除、選択状態などを管理するクラスです。サーバー情報はUserDefaultsに永続化されます。

#### `OllamaChat.swift`

Ollamaの`/api/chat`エンドポイントとやり取りするためのリクエスト/レスポンスのデータ構造（`ChatMessage`, `ChatRequest`など）を定義しています。

#### `OllamaModel.swift`

Ollamaの`/api/tags`や`/api/show`から取得したモデル情報を保持するためのデータ構造を定義します。

#### `ServerInfo.swift`

Ollamaサーバーの接続情報（名前、URLなど）を保持するためのデータ構造を定義します。

### 開発方針について

ここには開発を行うに当たって可能な限り守るべきことを記載します。ユーザから今後も守るべき新たな情報を受け取った場合はこのドキュメントの中に追記してください。

* ユーザは日本語で応対することを望んでいるため、必ず日本語で会話すること
* 可能な限りSwiftのベストプラクティスに沿うこと
* コード内のコメントは日本語で記載すること
* プロジェクトのターゲットはmacOS 14.0以降であるため、それ以降のバージョンで対応していないレガシーなコードは書かないこと
    * つまり、可能な限り新しいコードを書いておけば問題ありません。
* Canvasを使ってコードを提供する場合、過去のファイルを編集するのではなく、新しいファイルとして提供すること
    * 現在のGoogle Geminiでは、過去のファイルを編集した場合、過去のチャット履歴にさかのぼらなければ編集されたファイルを開くことができないため、ユーザが不便です。新しいファイルとして提供することで、常に最新のチャット履歴にコードを開くボタンが表示されるため、ユーザが快適に開発を進めることができます。
* ローカライズはString Catalogを使って行うため、エラーメッセージなどはローカライズ対応で記述すること
    * String Catalogでは、`Text('サンプルテキスト')`のようなテキストでは自動的にテキスト自体がキーとして認識されるため、この場合はローカライズ対応記述方法を使う必要はありません。
* **デバッグログのローカライズについて**:
    * `print()`文で出力されるデバッグログやコンソール出力は、ローカライズする必要はありません。
    * デバッグログは日本語で記述し、開発者が理解しやすいように可読性を優先してください。
    * ユーザー向けのUIテキストのみをローカライズ対象とし、デバッグ出力は分離して考えてください。
* 応対するたびに随時このドキュメントを読み込み、編集すること
* コードファイルの先頭にファイル名を示すコメント（例: `// FileName.swift`）は不要なため、削除すること
* SwiftUIのプレビューには、新しい`#Preview`マクロを使用すること。
* コードは、変更があったファイルのみを提供すること。
* UIに表示されるテキストと、そのローカライズキーは英語で書くこと。
* メインアクター上でのUI更新など、非同期処理を行う場合は、`DispatchQueue.main.async { ... }`の代わりに`Task { @MainActor in ... }`を使用してください。
* **Listアイテムの選択挙動について**:
    * SwiftUIの`List`において、UI上のハイライト選択（ユーザーがクリックした行を視覚的にハイライトする機能）と、API通信で使用する「現在選択されているサーバー」を区別して管理する場合がある。
    * UI上のハイライト選択には`List`の`selection`バインディングを使用し、独立した`@State`プロパティにバインドすること。
    * API通信に使用する「現在選択されているサーバー」は、`@ObservedObject`または`@StateObject`として管理されるデータモデル（例: `ServerManager`の`selectedServerID`）で保持すること。
    * リストの項目がフォーカスされている状態でEnterキーを押す、または項目をダブルクリックした際に特定のカスタムアクション（例: API通信用サーバーの切り替え）を実行するには、`contextMenu(forSelectionType:menu:primaryAction:)`モディファイアの`primaryAction`引数を使用すること。この際、UI上のハイライト選択（`listSelection`）とAPI通信用選択（`serverManager.selectedServerID`）の両方を更新することが推奨される。
* **Ollama APIのモデル情報からコンテキスト長を取得する際**:
    * Ollama APIの`/api/show`エンドポイントから返されるモデル情報（`model_info`）には、モデルの種類によって異なるキー（例: `llama.context_length`, `mistral.context_length`など）でコンテキスト長が提供される。
    * そのため、`context_length`の値を抽出する際は、キーのプレフィックスに依存せず、`.context_length`で終わるキーを検索して値を取得すること。

### TODOリスト

ここには、今後開発をする上で一時的に保留にしている作業を記載します。

例えば、ユーザが「実際の機能は後で実装するので、とりあえず設定にオプションだけ追加してください」のような言った場合、このリストに「〇〇のオプションを追加したため、この後、実際の機能を実装する」のような項目を追加します。どのような機能を実装するのか、このドキュメントを見た誰もが理解できるように詳細に記載する必要があります。

作業が完了して実装が終わったら、実装が完了した項目をこのリストから削除してください。

* **2025/07/25**: 「設定」タブの基本的なUI構造を作成したため、今後は設定項目（例: Ollama APIのホストURL設定、ダークモード/ライトモード切り替えなど）を実装する。
* **2025/07/25**: メインサイドバーに「サーバー」タブの基本的なUI構造を作成したため、今後はメインコンテンツとしてのサーバー関連機能（例: Ollamaサーバーの起動/停止、ステータス表示など）を実装する。

## その他の情報

引き継ぎにあたって、上記以外で他に伝えるべき情報がある場合はこちらに記載してください。

* ビルドコマンド: `xcodebuild -project /Users/taikun/Documents/Xcode/Mocolamma/Mocolamma/Mocolamma.xcodeproj -scheme Mocolamma build`