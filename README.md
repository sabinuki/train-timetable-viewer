# train-timetable-viewer

指定した駅・路線・方面の、**現在時刻以降の発車時刻**をデスクトップに表示する macOS のメニューバー常駐アプリです。
駅までの所要時間を設定すると、「何時までに出発すれば何時発に乗れるか」を一目で確認できます。

- メニューバーに次の発車と残り時間を常時表示（例: `🚃 18:05 あと12分`）
- 他のアプリのフォーカスを奪わずに最前面に表示するフローティングパネル
- メニューバーかグローバルショートカット `⌥⌘T` で、パネルの表示と非表示を切り替え
- 平日と土休日（祝日を含む）のダイヤを自動で切り替え、0 時台の終電にも対応
- 時刻表はローカルに保存するため、オフラインでも動作します。有料の API やサービスは使いません

設計は [docs/design.md](docs/design.md) を参照してください。

## 必要な環境

- macOS 14 Sonoma 以降
- Xcode 16 以降（Xcode 26.6 で動作を確認）

有料の Apple Developer Program への登録は不要です。

## ビルドと起動

### Xcode で開く

1. リポジトリをクローンし、`App/TrainTimetableViewer.xcodeproj` を Xcode で開きます。
2. スキーム `TrainTimetableViewer` を選び、Run（`⌘R`）で起動します。

既定ではアドホック署名（Sign to Run Locally）でビルドするため、Apple ID の設定なしで自分の Mac で実行できます。

### ターミナルからビルドする

```sh
git clone https://github.com/sabinuki/train-timetable-viewer.git
cd train-timetable-viewer
xcodebuild -project App/TrainTimetableViewer.xcodeproj -scheme TrainTimetableViewer \
  -configuration Release -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Release/TrainTimetableViewer.app
```

常用する場合は、`TrainTimetableViewer.app` を `/Applications` にコピーしてください。

### 無料の Apple ID で署名する（任意）

アドホック署名のままでも使えますが、Apple ID（Personal Team）で署名したい場合は次のようにします。

1. Xcode の Settings > Accounts に Apple ID を追加し、Team ID を確認します。
2. `App/Config/Local.xcconfig.example` を `App/Config/Local.xcconfig` にコピーし、`DEVELOPMENT_TEAM` に Team ID を設定します（このファイルはコミットされません）。

## 使い方

### 1. 時刻表を取り込む

初回起動時は時刻表がないため、メニューバーに「時刻表なし」と表示されます。

1. メニューバーのアイコンをクリックし、「設定…」を開きます。
2. 「時刻表 JSON を取り込む…」で、自分で作った時刻表 JSON を選びます。
   - まず試したい場合は「サンプルを取り込む」を押すと、架空の駅のサンプル時刻表を取り込めます。

ダイヤ改正の前後の時刻表を両方取り込んでおくと、改正日に自動で切り替わります。

### 2. 駅までの所要時間を設定する

設定画面の「駅までの所要時間」に、今いる場所から駅までの分数を入力します。
パネルでは、乗れる次の電車が強調され、その下に「〇〇 までに出発」と表示されます。間に合わない電車は薄く表示されます。

### 3. パネルの表示と非表示

- メニューの「パネルを表示 / 隠す」、グローバルショートカット `⌥⌘T`、パネルの × ボタンで切り替えます。
- パネルは背景をドラッグして移動、端をドラッグしてサイズを変更できます。位置、サイズ、表示状態は次回起動時に復元されます。

## 時刻表 JSON の作り方

鉄道会社の公式サイトなどの時刻表を見ながら、次のようなテキストを書いて変換します。

```text
station: my-station 〇〇駅
line: my-line △△線
direction: outbound ××方面
validFrom: 2026-03-14
type: 快=快速
type-default: 各停
destination-default: ××

[weekday]
18: 05快 12 20快 31
[holiday]
18: 10 30
```

```sh
scripts/make-timetable.sh my-station.txt -o my-station.json
```

書式の詳細は [scripts/README.md](scripts/README.md) を参照してください。時刻表データの著作権と利用条件は各鉄道会社に従い、個人の利用にとどめてください。

## 管理された PC で使う場合

職場などで管理されている PC では、自分でビルドしたアプリのインストールや実行がポリシーで制限されている場合があります。導入する前に、利用してよいか確認してください。

## データの保存場所

| 内容 | 場所 |
| --- | --- |
| 取り込んだ時刻表 | `~/Library/Application Support/com.sabinuki.TrainTimetableViewer/timetables/` |
| 設定（所要時間、パネルの位置と表示状態など） | `defaults read com.sabinuki.TrainTimetableViewer` で確認できます |

## 開発

```sh
# ロジック（TimetableCore）の単体テスト
swift test --package-path Packages/TimetableCore

# アプリのビルド
xcodebuild -project App/TrainTimetableViewer.xcodeproj -scheme TrainTimetableViewer \
  -destination 'platform=macOS' -derivedDataPath build build
```

| ディレクトリ | 内容 |
| --- | --- |
| `App/` | macOS アプリ（メニューバー、フローティングパネル、設定画面） |
| `Packages/TimetableCore/` | UI に依存しないロジック（時刻表モデル、運行日判定、次発の算出、表示状態）と `timetable-convert` |
| `scripts/` | 時刻表 JSON の作成支援スクリプトとサンプル |
| `docs/` | 設計書 |

祝日データは内閣府「[国民の祝日](https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html)」の CSV を同梱しています。
