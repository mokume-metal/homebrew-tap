<!--
SPDX-FileCopyrightText: 2026 mokume-metal
SPDX-License-Identifier: MIT
-->

# mokume の Homebrew tap

[mokume](https://github.com/mokume-metal/mokume) — Swift + Metal のクリエイティブ
コーディング環境 — の道具を Homebrew で入れるための tap。

```bash
brew install mokume-metal/tap/mokume
```

macOS 26 (Tahoe) 以上・Apple Silicon 専用。スケッチを作り直すのに Xcode 26 が要る。

```bash
mokume new my-sketch   # そのまま動くスケッチ一式を作る
cd my-sketch
mokume run             # 作って走らせる
```

ライブラリ本体は入れなくてよい。`mokume new` が作るスケッチが依存として引く。

## この tap の性質

**`Formula/mokume.rb` は手で書き換えない。** mokume のリリースが出るたびに
`scripts/update-formula.sh` が組み立て直して commit するので、手で編集しても次の更新で
消える。形を変えるなら `scripts/formula.rb.template` を直す。

**formula がここに居るのは、mokume 側でリリースがファイルを変えないようにするため。**
formula は `url` + `sha256` を固定で持つので版ごとに中身が変わる。これを mokume に置くと
「リリースがリポジトリのファイルを変える」ことになり、あちらの release.yml が避けている
迂回 (main へ入れるための PR と、そこを通すための必須チェックの回避) が要る
([mokume#398](https://github.com/mokume-metal/mokume/issues/398))。

**ソースからビルドし直さない。** 引くのは mokume のリリースが既に作っている配布物
`mokume-macos-arm64.tar.gz` そのもの。同じタグから 2 通りの実行ファイルが出る状態を
作らないため。

**更新はこちらから見に行く。** `Update formula` ワークフローが 4 時間ごとに
mokume の最新リリースを見て、版が変わっていれば追随して入れて試してから commit する。
mokume の定期リリースは日次で、出る時刻は GitHub の混雑で数時間ずれるため、時刻を
合わせず回数で拾う。新しい版はおおむね 4 時間以内に反映される。

**止まったらここに Issue が立つ。** 追随が落ちても、既に配ってある formula は壊れないので
利用者からは見えない。放っておくと出荷だけが静かに止まるので、定期実行が落ちた日に
「いつから止まっていて、上流から何版ぶん遅れているか」を書いた Issue が自動で立ち、
緑に戻ると自動で閉じる ([#8](https://github.com/mokume-metal/homebrew-tap/issues/8))。
バッジを置いていないのは、バッジでは「直近の run が緑か」しか言えず、
いちばん知りたい**遅れの長さ**を表せないため。

**鍵は 1 本も要らない。** あちらから伝令を投げてもらう形も試したが、それには mokume 側へ
このリポジトリを書ける token を常設することになり、期限が切れれば黙って止まる
([mokume#410](https://github.com/mokume-metal/mokume/issues/410))。臨時に出た版を待たずに
取り込みたいときは Actions から手で起こせる。

## 作業の進め方

正典は [mokume 本体の AGENTS.md](https://github.com/mokume-metal/mokume/blob/main/AGENTS.md)。
Issue も、この tap に固有でない限り [mokume](https://github.com/mokume-metal/mokume/issues)
へ立てる — 出荷の話は本体と切り離せないので、置き場を 2 つ持たない。
