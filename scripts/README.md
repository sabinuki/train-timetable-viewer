# scripts

## make-timetable.sh

鉄道会社の公式サイトなどの時刻表を見ながら書いたテキストを、アプリで読み込める時刻表 JSON（設計書 §8.1）に変換します。
変換結果はアプリと同じ読み込み処理で検証してから出力します。

```sh
scripts/make-timetable.sh my-station.txt -o my-station.json
```

`-o` を省略すると、JSON を標準出力に書き出します。初回は `Packages/TimetableCore` のビルドが走るため少し時間がかかります。

### テキストの書式

[sample-timetable.txt](sample-timetable.txt) が実際に変換できる例です。

```text
# # 以降はコメント
station: example-station 〇〇駅      # <ID> <表示名>
line: example-line △△線
direction: outbound ××方面
validFrom: 2026-03-14                # ダイヤ改正日（この日以降に有効）

type: 快=快速, 特=特急               # 種別の略記（1 文字 = 正式名）
type-default: 各停                   # 記号のない発車の種別（省略可）
destination: □=□□, 折=〇〇          # 行き先の略記
destination-default: ××              # 記号のない発車の行き先（省略可）

[weekday]                            # 平日
5: 12 30 45
18: 05快 12 20快□ 31特
24: 21□                              # 終電の 0:21 は 24 時台として書く

[saturday]                           # 土曜（土曜ダイヤがない路線は省略する）
7: 00 30

[holiday]                            # 土休日
6: 00 30
```

- 発車は `時: 分 分 分 …` の形で 1 時間ずつ書きます。時は 0〜47、分は 1〜2 桁です。
- 分の後ろに付けた 1 文字の記号を、`type` と `destination` の定義に従って展開します。種別と行き先の記号は組み合わせられます（例: `20快□`）。
- `[weekday]` と `[holiday]` は必須です。`[saturday]` を省略すると、土曜は土休日ダイヤとして扱います。
- ID（`example-station` など）は、同じ駅・路線・方面の時刻表をダイヤ改正の前後で見分けるために使います。英数字とハイフンで付けてください。

## sample-timetable.txt

架空の駅・路線のサンプルです。`App/TrainTimetableViewer/Resources/SampleTimetable.json` はこのファイルから生成しています。

```sh
scripts/make-timetable.sh scripts/sample-timetable.txt -o App/TrainTimetableViewer/Resources/SampleTimetable.json
```
