#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# 設定のずれを Issue で名乗り、戻ったら畳む (#11)。settings-drift.yml から呼ぶ。
#
#   report-settings-drift.sh <check-settings.sh のログ>   (STATUS に照合の終了コード)
#
# 形は report-stall.sh に倣う: 題を固定して 1 本だけ立て (検索の索引を引かず一覧を
# 完全一致で絞る)、緑に戻れば自動で閉じる。こちらの緑は「定義と実設定が一致した」で、
# 退化した緑への経路が無いので閉じてよい。
#
# **push 契機では起票しない。** 定義を変える PR を merge した直後に「まだ適用していない」の
# は正常で、そのたびに Issue が立つと処理すべきものが積み増される。push 契機は run の赤で
# 催促し、放置されれば次の定期実行が起票する (本体 mokume#381 と同じ段階の上げ方)。
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-mokume-metal/homebrew-tap}"
readonly TITLE="chore(ci): リポジトリ設定が .github/ の定義とずれている"
log="${1:?使い方: report-settings-drift.sh <ログ>}"
status="${STATUS:?STATUS に照合の終了コードを渡す}"

run_url="${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/${GITHUB_RUN_ID:-}"
sig='<sub>🤖 .github/workflows/settings-drift.yml (#11)</sub>'

# **`| head -1` で絞らない** (pipefail の下で落ちる。report-stall.sh の find_open を参照)
find_open() {
  gh issue list -R "$REPO" --state open --limit 100 --json number,title \
    --jq "[.[] | select(.title == \"$TITLE\")] | .[].number"
}

if [ "$status" = 0 ]; then
  while read -r n; do
    [ -n "$n" ] || continue
    gh issue close "$n" -R "$REPO" --comment "$(printf '定義と実設定が一致した。\n\n- この run: %s\n\n---\n%s\n' "$run_url" "$sig")" >/dev/null
    echo "resolve: #$n を閉じた"
  done < <(find_open)
  exit 0
fi

if [ "${GITHUB_EVENT_NAME:-}" != schedule ]; then
  echo "report: ${GITHUB_EVENT_NAME:-手元} の契機では起票しない (赤で知らせる)"
  exit 0
fi

existing="$(find_open)"
existing="${existing%%$'\n'*}"
if [ -n "$existing" ]; then
  # 日次でコメントを積むと意味を失うので、開いているあいだは足さない (本文は初日のまま)
  echo "report: #$existing が開いている。足さない"
  exit 0
fi

body="$(cat <<BODY
リポジトリ設定かルールセットが、\`.github/repo-settings.json\` / \`.github/rulesets/\` の定義とずれている。

**main の守り (必須チェック・auto-merge) が外れていると、\`gh pr merge --auto\` は CI を待たずに即マージする** — しかもエラーにならない (#11)。

\`\`\`
$(cat "$log")
\`\`\`

## 直し方

- 管理画面で意図して変えたのなら、定義を同じ形に直す PR を出す
- そうでなければ、main を最新にして \`bash scripts/apply-settings.sh\` で定義へ戻す

定義と実設定が一致すれば、次の定期実行でこの Issue は自動で閉じる。

- 落ちた run: $run_url

---
$sig
BODY
)"
url="$(gh issue create -R "$REPO" --title "$TITLE" --body "$body")"
echo "report: $url を立てた"
gh issue edit "${url##*/}" -R "$REPO" --type Task >/dev/null 2>&1 ||
  echo "report: 型 Task を付けられなかった (起票はできている)" >&2
