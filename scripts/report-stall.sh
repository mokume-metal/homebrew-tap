#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# 追随が止まったことを Issue で名乗り、戻ったら畳む (#8)。
#
# **塞ぐのは「赤が誰にも拾われない」である。** 上流 v0.8.0 で CLI の表示が英語へ移ったとき、
# formula の検査が古い文言のままで毎日落ち、tap は v0.7.1 のまま 9 日間止まった (#7)。
# それが見えなかったのは、この形に次の性質があるため:
#
#   既に配ってある formula は壊れない … 利用者は困らないので、外から声が上がらない
#   formula は自分が最新かを名乗らない … tap を見ても遅れは分からない
#   定期実行の赤は Actions のタブとメールにしか出ない … 毎朝 1 通増えるだけで
#                                                      「いつから」「何版ぶん」が読めない
#
# 気付く契機が人の巡回しかなかった。ここは追跡単位を Issue 一覧へ移す部品である。
#
# **同じ事故が本体でも起きている。** mokume の scripts/report-check-failure.sh は、
# publication の検査が 7 日連続で赤のまま見落とされた事象 (mokume#1295) から生まれた。
# 題を固定して 1 本だけ立てる形・判断をワークフローでなくスクリプトに置く形はそちらに倣う。
#
# **この tap に立てる。** README は「Issue も、この tap に固有でない限り mokume へ立てる」と
# 引いているが、止まっているのはこの tap の CI なので固有である。上流へ投げない。
#
# **本体の「自動では閉じない」から意図して外れる。** report-check-failure.sh は
# ADR-0008 決定 3・5 を引いて閉じる機構を持たない — あちらは**指し先を消しても緑になる**ので
# 「緑に戻った」が「直った」を意味しないためである。こちらの緑は「上流の最新を組んで・
# 入れて・試して・push できた」であり、**緑 = 出荷**で退化した緑への経路が無い。
# さらに本体が唯一残した危うさ (「open なままだと重複抑止が次の事象を黙らせる」) は、
# 自動で閉じることがそのまま解消する。だからここでは閉じる。
set -euo pipefail

# 自分と上流。上流の既定は scripts/update-formula.sh と同じ綴りにしてある
REPO="${GITHUB_REPOSITORY:-mokume-metal/homebrew-tap}"
UPSTREAM="${MOKUME_REPO:-mokume-metal/mokume}"

# **重複判定は固定の題そのもの。** 本文へ埋めた不可視の目印は使わない — 人が本文を
# 編集しただけで dedupe が黙って壊れ、症状が「Issue が 2 本ある」になる。
# 版や日付を題に入れないのも同じ理由で、入れると毎日別物になって dedupe が死ぬ。
#
# 「検査が落ちている」ではなく「追随が止まっている」と名乗る。runner の故障でも
# Homebrew 側の都合でも、出荷が止まっていることに変わりはないので、題が嘘にならない
readonly TITLE="chore(ci): mokume への追随が止まっている"

# 起票と同時に付けたい Issue Type。分類の正典はラベルでなく Issue Type である (#4)
readonly TYPE="Task"

run_url() {
  [ -n "${GITHUB_RUN_ID:-}" ] || return 0
  echo "${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/$GITHUB_RUN_ID"
}

# 題が完全一致する open な Issue の番号を、見つかっただけ返す。
#
# **検索 (--search) を引かない。** 本体の report-check-failure.sh は索引を引くが、
# あちらは Issue が数百本ある。ここは数本なので素の一覧で足り、索引の遅れを踏まずに済む。
# とりわけこちらは自動で閉じるので、**閉じた直後の Issue が索引の遅れで「open」と返り、
# 次の停止の起票を黙らせる**形が起こり得る — 症状が「何も起きない」になる類で、
# 本体が #1295 で踏んだのと同じ質の壊れ方である。題の完全一致で絞るのは本体と同じ。
#
# 二重起票の心配は要らない。ワークフローが concurrency: update-formula
# (cancel-in-progress: false) で直列化しているので、2 つの run が同時にここへ来ない
find_open() {
  gh issue list -R "$REPO" --state open --limit 100 --json number,title \
    --jq "[.[] | select(.title == \"$TITLE\")] | .[].number"
}

# 出している版。**working tree からは読まない。**
#
# scripts/update-formula.sh は検査より前に Formula/mokume.rb を書き換えるので、
# 検査で落ちた時点の working tree に入っているのは「出せなかった版」である。
# それを読むと上流の最新と一致してしまい、**遅れを数える Issue が「遅れ 0 版」と
# 名乗る**。実際 9 日の停止の間、毎日そう書くところだった。
# 数えたいのは commit されて配られている版なので HEAD から読む
shipped_version() {
  git show HEAD:Formula/mokume.rb 2>/dev/null |
    sed -n 's/^  version "\(.*\)"$/\1/p' || true
}

# 手元の版より後に出た正式リリースの数。読めなければ空を返す
releases_behind() {
  local here="$1"
  [ -n "$here" ] || return 0
  gh release list -R "$UPSTREAM" --limit 100 --json tagName \
    --jq "[.[].tagName] | index(\"v$here\") // empty" 2>/dev/null || true
}

# 最後に緑だった定期実行からの日数。
# Actions の履歴は 90 日ほどで消えるので、読めなければ unknown (= 90 日以上、または記録が無い)
stalled_days() {
  gh run list -R "$REPO" --workflow update-formula.yml --event schedule \
    --status success --limit 1 --json createdAt \
    --jq 'if length == 0 then "unknown"
          else ((now - (.[0].createdAt | fromdateiso8601)) / 86400 | floor | tostring) end' \
    2>/dev/null || echo unknown
}

last_green_url() {
  gh run list -R "$REPO" --workflow update-formula.yml --event schedule \
    --status success --limit 1 --json url --jq '.[0].url // empty' 2>/dev/null || true
}

# 停止を名乗る本文。**一度書いたら書き換えない** (理由は report() を参照)
compose_body() {
  local days="$1" shipped="$2" latest="$3" behind="$4" failed="$5" green="$6"

  printf '定期の追随が **%s** 止まっている。\n\n' \
    "$([ "$days" = unknown ] && echo "いつからか読めないほど長く" || echo "${days} 日")"

  if [ -z "$shipped" ]; then
    printf 'まだ 1 度も formula を出していない。\n\n'
  elif [ -z "$latest" ]; then
    printf '出しているのは **v%s**。上流の最新は読めなかった — この run 自体が上流を読めていない可能性がある。\n\n' "$shipped"
  elif [ -z "$behind" ] || [ "$behind" = 0 ]; then
    printf '出しているのは **v%s** で、上流の最新 (**%s**) に追い付いている。遅れはまだ 0 版 — 新しい版が出ていないだけで、**出た瞬間に出せない状態**にある。\n\n' "$shipped" "$latest"
  else
    printf '出しているのは **v%s** で、上流の最新は **%s** — **%s 版ぶん**遅れている。\n\n' "$shipped" "$latest" "$behind"
  fi

  printf '既に配ってある formula は動くので、利用者からは見えない。見えるのはここだけである。\n\n'

  [ -n "$failed" ] && printf -- '- 落ちた run: %s\n' "$failed"
  [ -n "$green" ] && printf -- '- 最後に緑だった定期実行: %s\n' "$green"
  [ -n "$shipped" ] && printf -- '- 出している版: `Formula/mokume.rb` (HEAD) = %s\n' "$shipped"
  [ -n "$latest" ] && printf -- '- 上流の最新: %s\n' "$latest"

  cat <<'BODY'

## どう読むか

追随の段が成功していて後段の `brew test` が落ちている形なら、上流の表示や振る舞いが
変わって formula の検査が古くなっている (#7 がその 1 例)。落ちた run のログで、
どの段で落ちたかをまず見る。

追随の段そのものが落ちているなら、上流のリリースや資産の側を見る。

## 解消

定期実行が緑に戻ると、**この Issue は自動で閉じる**。手で閉じても、追随が止まったままなら
翌日また立つ — 止めるには原因を直すか、定期実行そのものを止める。
BODY
}

# 停止を名乗る。既に開いていれば立て直さず、上流に新しい版が出たときだけ 1 本足す
report() {
  local dry="$1"
  local days shipped latest behind failed green existing

  # **どれも読めなくても止まらない。** 上流が読めない回にこそ起票したいので、
  # 事実の収集が失敗しても報告そのものは続ける。報告が落ちたら警報が鳴らない
  days="$(stalled_days)"
  shipped="$(shipped_version)"
  latest="$(gh release view -R "$UPSTREAM" --json tagName --jq .tagName 2>/dev/null || true)"
  behind="$(releases_behind "$shipped")"
  failed="$(run_url)"
  green="$(last_green_url)"

  # **`| head -1` で絞らない。** pipefail の下では head が先に閉じた側を失敗と読み、
  # 出力が多いときにスクリプトごと黙って落ちる (実地で再現する)。ここが落ちると
  # 警報が鳴らないので、パイプを挟まず先頭行だけ取り出す
  existing="$(find_open)"
  existing="${existing%%$'\n'*}"

  if [ -n "$existing" ]; then
    # **本文は書き換えない。** gh issue edit は通知が飛ばないので、既に読んだ人には
    # 悪化が届かない。しかも初日の記述が消える — #7 の切り分けは「最後に緑だった回が
    # どの版を検査していたか」から始まったので、そこを潰すと次の切り分けが立たない。
    #
    # 代わりに**上流に新しい版が出たときだけ** 1 本足す。日次で鳴らすと意味を失う
    # (mokume#642)。9 日の停止なら v0.8.1 と v0.9.0 の 2 本で、どちらも新しい事実を運ぶ。
    # 既に名乗ったかは本文とコメントを読んで決め、状態の置き場を増やさない
    if [ -z "$latest" ]; then
      echo "report: #$existing が開いている。上流の最新が読めないので何も足さない"
      return 0
    fi

    local seen
    seen="$(gh issue view "$existing" -R "$REPO" --json body,comments \
      --jq '[.body] + [.comments[].body] | join("\n")' 2>/dev/null || true)"
    case "$seen" in
      *"$latest"*)
        echo "report: #$existing が開いていて $latest は既に名乗っている — 足さない"
        return 0
        ;;
    esac

    local note
    note="$(printf 'その後さらに上流が進み、最新は **%s** になった (出しているのは v%s で **%s 版ぶん**遅れ)。\n\n- この run: %s\n\n---\n<sub>🤖 .github/workflows/update-formula.yml が自動で足した (#8)</sub>\n' \
      "$latest" "$shipped" "${behind:-?}" "$failed")"

    if [ "$dry" = 1 ]; then
      printf 'report: 起票しない (手で起こした回)。#%s へ足すはずだったコメント:\n%s\n' "$existing" "$note"
      return 0
    fi
    gh issue comment "$existing" -R "$REPO" --body "$note" >/dev/null
    echo "report: #$existing へ $latest を名乗るコメントを足した"
    return 0
  fi

  local body
  body="$(compose_body "$days" "$shipped" "$latest" "$behind" "$failed" "$green")"
  body="$body
$(printf '\n---\n<sub>🤖 .github/workflows/update-formula.yml が自動起票した (#8)</sub>\n')"

  if [ "$dry" = 1 ]; then
    printf 'report: 起票しない (手で起こした回)。立てるはずだった Issue:\n\n# %s\n\n%s\n' "$TITLE" "$body"
    return 0
  fi

  local url num
  url="$(gh issue create -R "$REPO" --title "$TITLE" --body "$body")"
  echo "report: $url を立てた"

  # **型は後付けで、失敗しても止めない。** org の Issue Type は既定の GITHUB_TOKEN から
  # 読めないことがあり、gh issue create --type に渡すと型が引けないだけで**起票ごと落ちる** —
  # 鳴らない警報になる。分類が欠けるほうが、警報が消えるよりずっとましである
  num="${url##*/}"
  gh issue edit "$num" -R "$REPO" --type "$TYPE" >/dev/null 2>&1 ||
    echo "report: 型 $TYPE を付けられなかった (起票はできている)。org の Issue Type を確かめる" >&2
}

# 追い付いたので印を下ろす。**開いているものは全部畳む** — 万一 2 本立っていても残さない
resolve() {
  local dry="$1"
  local shipped latest note n found=0

  shipped="$(shipped_version)"
  latest="$(gh release view -R "$UPSTREAM" --json tagName --jq .tagName 2>/dev/null || true)"

  # 緑は「出せるものは出した」であって「最新と一致」とは限らない。資産がまだ載っていない
  # 版があれば追随しないまま緑になるので、閉じる言葉もそのとおりに書く
  if [ -n "$latest" ] && [ -n "$shipped" ] && [ "v$shipped" != "$latest" ]; then
    note="$(printf '緑に戻った。v%s を出している (上流の最新は %s だが、まだ追随の対象になっていない)。\n' "$shipped" "$latest")"
  elif [ -n "$shipped" ]; then
    note="$(printf '緑に戻った。v%s を出している。\n' "$shipped")"
  else
    note="緑に戻った。"
  fi
  note="$note
$(printf '\n- この run: %s\n\n---\n<sub>🤖 .github/workflows/update-formula.yml が自動で閉じた (#8)</sub>\n' "$(run_url)")"

  while read -r n; do
    [ -n "$n" ] || continue
    found=1
    if [ "$dry" = 1 ]; then
      printf 'resolve: #%s を閉じる (手で起こした回なので実際には閉じない):\n%s\n' "$n" "$note"
      continue
    fi
    gh issue close "$n" -R "$REPO" --comment "$note" >/dev/null
    echo "resolve: #$n を閉じた"
  done < <(find_open)

  # **緑の日に赤を作らない。** 閉じるものが無いのは通常であって失敗ではない
  [ "$found" = 1 ] || echo "resolve: 開いている報告は無い"
}

# **手で起こした回は素振りにする。** workflow_dispatch は tag を任意に指定できるので、
# 古い tag で試した回に本当に起票すると遅れの算術が嘘になる (mokume#381 が名指しする
# 「毎回鳴る狼」)。一式を組み立ててログへ出すだけにすれば、発火の経路を端から端まで
# 確かめられて誤報は出ない
dry=0
[ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ] && dry=1

case "${JOB_STATUS:-}" in
  failure) report "$dry" ;;
  success) resolve "$dry" ;;
  # cancelled など。止まったとも戻ったとも言えないので何もしない
  *) echo "report-stall: 状態が「${JOB_STATUS:-空}」なので何もしない" ;;
esac
