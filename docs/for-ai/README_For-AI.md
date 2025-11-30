# 初めにお読みください（For AI）

## このドキュメントについて

このドキュメントは、生成AIのチャットスレッドが新しくなってもスムーズに引き継ぎできるよう、プロジェクトの基本情報と引き継ぎに必要な情報が記載されています。

このドキュメントを受け取ったあなたは、このドキュメント内の情報を確認し、チャットを送るようにしてください。また、ユーザから新たな依頼や「必ずこうして欲しい」など、今後も守るべき情報を受け取った場合はこのドキュメントの中に追記してください。

## プロジェクトについて

プロジェクト名: `Mocolamma`\
プロジェクトのバンドル識別子: `design.taikun.Mocolamma`

このプロジェクトは、Ollama APIを使ってOllamaの様々な管理を行うmacOS用のSwiftアプリケーションです。\
名前の由来は「**Mo**del」「**Co**ntrol」「Ol**lam**a」「**Ma**nage」を組み合わせた造語です。

### プロジェクトの構造

```
Mocolamma
├── Components
│   ├── GlassProminentButtonStyle.swift
│   ├── MarqueeText.swift
│   ├── NavSubtitleIfAvailable.swift
│   ├── SoftEdgeIfAvailable.swift
│   └── VisualEffectView.swift
├── Managers
│   ├── APITimeoutManager.swift
│   ├── CommandExecutor.swift
│   └── ServerManager.swift
├── Models
│   ├── OllamaChat.swift
│   ├── OllamaModel.swift
│   └── ServerInfo.swift
├── Resources
│   ├── AppIcon.icon
│   ├── Assets.xcassets
│   └── Localizable.xcstrings
├── Supporting Files
│   └── MocolammaApp.swift
├── Utilities
│   ├── RefreshTrigger.swift
│   └── VisionOSDetection.swift
└── Views
    ├── AboutView.swift
    ├── AddModelsSheet.swift
    ├── ChatInputView.swift
    ├── ChatMessagesView.swift
    ├── ChatView.swift
    ├── ContentView.swift
    ├── InspectorContentView.swift
    ├── LegacyIPhoneTabView.swift
    ├── LicenseInfoModalView.swift
    ├── LicenseTextView.swift
    ├── MainContentDetailView.swift
    ├── MainNavigationView.swift
    ├── MainTabView.swift
    ├── MessageInputView.swift
    ├── MessageView.swift
    ├── ModelInspectorDetailView.swift
    ├── ModelInspectorView.swift
    ├── ModelListView.swift
    ├── RunningModelsCountView.swift
    ├── ServerFormView.swift
    ├── ServerInspectorDetailView.swift
    ├── ServerInspectorView.swift
    ├── ServerRowView.swift
    ├── ServerView.swift
    └── SettingsView.swift
```

新たなファイルを作成した場合はこの構造に新たなファイルを追加してください。

### 各コードの役割

新たなファイルが作成された場合や機能に変更があった場合は以下の文章を変更・追加してください。コードの変更履歴を記載するものではありません。コードの役割のみを説明する必要があります。

#### `AboutView.swift`

アプリケーションの「About」セクションを表示するビューです。アプリケーションのバージョン情報、ライセンス情報、開発者へのフィードバックやサポートに関するオプションを提供します。

#### `AddModelsSheet.swift`

Ollamaライブラリからモデルを検索し、ダウンロードして追加するためのシートビューです。

#### `APITimeoutManager.swift`

Ollama APIとの通信におけるタイムアウト設定を管理するクラスです。30秒、1分、5分、無制限のオプションを提供し、選択されたタイムアウト設定をUserDefaultsに保存します。

#### `ChatInputView.swift`

`ChatView`の下部に配置される入力コンポーネントです。テキスト入力フィールド、送信ボタン、ストリーミング停止ボタンを提供します。

#### `ChatMessagesView.swift`

`ChatView`内で使用され、チャットメッセージのリストを表示する責務を負います。各メッセージは`MessageView`としてレンダリングされます。

#### `ChatView.swift`

Ollamaモデルとのチャット機能を提供するメインビューです。メッセージの送受信、履歴表示、リビジョン管理などのUIとビジネスロジックを管理します。メッセージの表示自体は`ChatMessagesView`と`MessageView`に委譲しています。

#### `CommandExecutor.swift`

Ollama APIとの通信を非同期で実行し、結果をビューモデルに反映させる中心的なクラスです。チャットの実行、モデル情報の取得、モデルのプルと削除など、アプリケーションの主要なロジックを担います。

#### `ContentView.swift`

アプリケーションのメインUIを構成するビューです。プラットフォームに応じて、`MainNavigationView`または`MainTabView`（iOS 18.0以降）/`LegacyIPhoneTabView`（iOS 18.0未満のiPhone）を使用してUIを構築します。

#### `InspectorContentView.swift`

インスペクター（サイドバーの右側に表示される詳細パネル）のコンテンツを管理するビューです。選択された項目（モデル、サーバー、チャット設定など）に応じて、`ModelInspectorView`、`ServerInspectorView`、またはチャット設定フォームを表示します。

#### `LegacyIPhoneTabView.swift`

iOS 18.0未満のiPhoneデバイスでアプリケーションのメインタブベースUIを構成するビューです。

#### `MainContentDetailView.swift`

メインナビゲーションビュー（`MainNavigationView`）の詳細ペインに表示されるコンテンツを管理するビューです。選択されたサイドバーの項目（モデル、サーバー、チャット、設定）に応じて、対応するビュー（`ModelListView`, `ServerView`, `ChatView`, `SettingsView`）を表示します。

#### `MainNavigationView.swift`

macOSおよびiOS 18.0未満のiPadデバイスでアプリケーションのメインナビゲーションベースUIを構成するビューです。

#### `MainTabView.swift`

iOS 18.0以降のデバイスでアプリケーションのメインタブベースUIを構成するビューです。

#### `ModelInspectorDetailView.swift`

モデルインスペクターの詳細ビューです。`ModelInspectorView`をラップし、`OllamaModel`の情報を表示します。

#### `ServerInspectorDetailView.swift`

サーバーインスペクターの詳細ビューです。`ServerInspectorView`をラップし、`ServerInfo`と接続ステータスを表示します。

#### `LicenseInfoModalView.swift`

アプリケーションと依存関係のライセンス情報を表示するモーダルビューです。Mocolamma自身のライセンスと、Ollama、CompactSlider、MarkdownUI、Gemini CLI、opencode、create-dmgなどのオープンソースプロジェクトのライセンスおよびバージョン情報が含まれます。

#### `LicenseTextView.swift`

アプリケーションのライセンス情報を表示するためのビューです。

#### `MarqueeText.swift`

テキストがコンテナに収まらない場合に、マーキー（スクロール）効果で表示するSwiftUIビューです。

#### `MessageInputView.swift`

`ChatView`の下部に配置される入力コンポーネントです。テキスト入力フィールド、送信ボタン、ストリーミング停止ボタンを提供します。

#### `MessageView.swift`

個々のメッセージバブル、思考プロセス、リビジョン機能、メタデータ（トークン数、生成速度など）の表示を担当します。ホバーエフェクトで統計情報や操作ボタンを表示します。

#### `MocolammaApp.swift`

アプリケーションのエントリーポイントです。メインウィンドウと`ContentView`を初期化し、アプリケーション全体で利用する`ServerManager`と`CommandExecutor`を環境オブジェクトとして設定します。

#### `ModelInspectorView.swift`

`ModelListView`で選択されたモデルの詳細情報を表示します。

#### `ModelListView.swift`

利用可能なモデルの一覧を表示・管理するビューです。モデルの削除や詳細情報の表示機能を提供します。

#### `NavSubtitleIfAvailable.swift`

オペレーティングシステムのバージョンがサポートしている場合（iOS 26.0以降またはmacOS）、ビューにナビゲーションサブタイトルを適用するViewModifierです。

#### `OllamaChat.swift`

Ollamaの`/api/chat`エンドポイントとやり取りするためのリクエスト/レスポンスのデータ構造（`ChatMessage`, `ChatRequest`など）を定義しています。

#### `OllamaModel.swift`

Ollamaの`/api/tags`や`/api/show`から取得したモデル情報を保持するためのデータ構造を定義します。

#### `RunningModelsCountView.swift`

指定されたOllamaホストで現在実行中のモデル数を表示するSwiftUIビューです。

#### `ServerFormView.swift`

新規サーバーの追加や既存サーバーの編集を行うためのフォームを提供するシートビューです。

#### `ServerInfo.swift`

Ollamaサーバーの接続情報（名前、URLなど）を保持するためのデータ構造を定義します。

#### `ServerInspectorView.swift`

`ServerView`で選択されたサーバーの詳細情報をインスペクター領域に表示します。

#### `ServerManager.swift`

Ollamaサーバーの追加、削除、選択状態などを管理するクラスです。サーバー情報はUserDefaultsに永続化されます。

#### `ServerRowView.swift`

`ServerView`のリスト内の各サーバー情報を表示するためのビューコンポーネントです。

#### `ServerView.swift`

登録されているOllamaサーバーのリストを表示・管理するビューです。サーバーの追加、削除、選択などの操作を提供します。

#### `SettingsView.swift`

アプリケーション全体の設定（チャット設定、システムプロンプトなど）を行うビューです。

#### `SoftEdgeIfAvailable.swift`

オペレーティングシステムのバージョンがサポートしている場合（iOS 26.0以降またはmacOS 26.0以降）、ビューのスクロールエッジにソフトエッジ効果を適用するViewModifierです。

#### `VisualEffectView.swift`

SwiftUIビューに、プラットフォーム固有のぼかしや鮮やかさなどの視覚効果を組み込むためのViewRepresentableを定義します。

### 開発方針について

ここには開発を行うに当たって可能な限り守るべきことを記載します。ユーザから今後も守るべき新たな情報を受け取った場合はこのドキュメントの中に追記してください。

* ユーザは日本語で応対することを望んでいるため、必ず日本語で会話すること
* 可能な限りSwiftのベストプラクティスに沿うこと
* コード内のコメントは英語で記載すること
* プロジェクトのターゲットはmacOS 14.0以降、iOS 17.0以降、iPadOS 17.0以降であるため、それ以降のバージョンで対応していないレガシーなコードは書かないこと
    * つまり、可能な限り新しいコードを書いておけば問題ありません。
* ローカライズはString Catalogを使って行うため、エラーメッセージなどはローカライズ対応で記述すること
    * String Catalogでは、`Text('サンプルテキスト')`のようなテキストでは自動的にテキスト自体がキーとして認識されるため、この場合はローカライズ対応記述方法を使う必要はありません。
* **デバッグログのローカライズについて**:
    * `print()`文で出力されるデバッグログやコンソール出力は、ローカライズする必要はありません。
    * デバッグログは英語で記述してください。
    * ユーザー向けのUIテキストのみをローカライズ対象とし、デバッグ出力は分離して考えてください。
* 応対するたびに随時このドキュメントを読み込み、編集すること
* コードファイルの先頭にファイル名を示すコメント（例: `// FileName.swift`）は不要なため、削除すること
* SwiftUIのプレビューには、新しい`#Preview`マクロを使用すること。
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
