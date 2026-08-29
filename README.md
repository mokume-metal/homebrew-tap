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

**更新はこちらから見に行く。** `Update formula` ワークフローが日次 (01:00 UTC) で
mokume の最新リリースを見て、追随して入れて試してから commit する。mokume の定期
リリースは月曜 00:00 UTC なので、その 1 時間後に反映される。

**鍵は 1 本も要らない。** あちらから伝令を投げてもらう形も試したが、それには mokume 側へ
このリポジトリを書ける token を常設することになり、期限が切れれば黙って止まる
([mokume#410](https://github.com/mokume-metal/mokume/issues/410))。臨時に出た版を待たずに
取り込みたいときは Actions から手で起こせる。

## 作業の進め方

正典は [mokume 本体の AGENTS.md](https://github.com/mokume-metal/mokume/blob/main/AGENTS.md)。
Issue も、この tap に固有でない限り [mokume](https://github.com/mokume-metal/mokume/issues)
へ立てる — 出荷の話は本体と切り離せないので、置き場を 2 つ持たない。
