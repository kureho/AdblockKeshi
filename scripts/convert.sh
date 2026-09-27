#!/usr/bin/env bash
set -euo pipefail

# scripts/convert.sh
# 5本のフィルタを取得 → SafariConverterLib で Safari JSON 変換（上限なし）→
# 基本保護 / 2 本目の残り に振り分け（A-88 ①・build_split_rules.py）→ docs/cdn/ に出力
#
# 出力（docs/cdn/）:
#   blockerList.json   = 基本保護（広告だけオン）。旧版アプリの ad-rules.json もこれを取る
#   merged-rules.json  = 基本保護（広告＋セキュリティ）。旧版アプリも同じ名前で取る
#   second-ads.json / second-ads-sec.json = 2 本目に載せる広告の残り（4.4.0〜）
#   version.json / version-security.json の該当 sha
# ConverterTool は 15 万件で打ち切らない版を使う（monthly-filter-update.yml が上限を外してビルドする）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CDN_DIR="$PROJECT_DIR/docs/cdn"
CONVERTER="${SAFARI_CONVERTER_BIN:-$SCRIPT_DIR/converter-build/SafariConverterLib/.build/release/ConverterTool}"

if [ ! -x "$CONVERTER" ]; then
  echo "[ERROR] ConverterTool not found at $CONVERTER" >&2
  echo "  Build with: cd $SCRIPT_DIR/converter-build/SafariConverterLib && swift build -c release" >&2
  exit 1
fi

mkdir -p "$CDN_DIR"

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# filters.yml から URL を抽出
parse_filters() {
  python3 -c "
import yaml
with open('$SCRIPT_DIR/filters.yml') as f:
    data = yaml.safe_load(f)
for f in data['filters']:
    print(f\"{f['name']}\t{f['url']}\t{f['license']}\")
"
}

# 各フィルタを取得
echo "[fetch] downloading filters..."
declare -a FILES=()
declare -a NAMES=()
declare -a LICENSES=()
while IFS=$'\t' read -r name url license; do
  echo "  - $name ($license): $url"
  out="$TMP_DIR/${name}.txt"
  if curl -fsSL --max-time 60 "$url" -o "$out"; then
    FILES+=("$out")
    NAMES+=("$name")
    LICENSES+=("$license")
  else
    echo "[WARN] $name fetch failed, skipping"
  fi
done < <(parse_filters)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "[ERROR] no filters fetched" >&2
  exit 1
fi

echo "[merge] concatenating ${#FILES[@]} filters..."
cat "${FILES[@]}" > "$TMP_DIR/combined.txt"
COMBINED_LINES=$(wc -l < "$TMP_DIR/combined.txt")
echo "  combined lines: $COMBINED_LINES"

echo "[convert] running SafariConverterLib (no rule limit)..."
"$CONVERTER" convert \
  --input-path "$TMP_DIR/combined.txt" \
  --safari-rules-json-path "$TMP_DIR/full.json" \
  --safari-version 17

FULL_COUNT=$(jq 'length' "$TMP_DIR/full.json")
echo "  converted rules (all): $FULL_COUNT"
# 上限を外し損ねた ConverterTool はちょうど 150,000 件で打ち切る＝振り分けても例外が欠けたまま
if [ "$FULL_COUNT" -le 150000 ]; then
  echo "[ERROR] converted $FULL_COUNT rules: the converter still truncates at 150k (rule limit not removed?)" >&2
  exit 1
fi

# 全量を 2 本に振り分ける。セキュリティは週次（build-security-rules.yml）が docs/cdn に置いた最新版、
# ポップアップ対策は 2 本目で残りの後ろに並ぶ docs/cdn/popunder-rules.json
echo "[split] basic / second..."
python3 "$SCRIPT_DIR/build_split_rules.py" build \
  --full "$TMP_DIR/full.json" \
  --security "$CDN_DIR/security-rules.json" \
  --popunder "$CDN_DIR/popunder-rules.json" \
  --out-dir "$TMP_DIR/split"

for name in basic-ads-sec basic-ads second-ads-sec second-ads; do
  n=$(jq 'length' "$TMP_DIR/split/$name.json")
  if [ "$n" -gt 149000 ]; then
    echo "[ERROR] $name has $n rules (over 149,000)" >&2
    exit 1
  fi
done

# 出力
mv "$TMP_DIR/split/basic-ads.json" "$CDN_DIR/blockerList.json"
mv "$TMP_DIR/split/basic-ads-sec.json" "$CDN_DIR/merged-rules.json"
mv "$TMP_DIR/split/second-ads.json" "$CDN_DIR/second-ads.json"
mv "$TMP_DIR/split/second-ads-sec.json" "$CDN_DIR/second-ads-sec.json"

RULE_COUNT=$(jq 'length' "$CDN_DIR/blockerList.json")
JSON_BYTES=$(wc -c < "$CDN_DIR/blockerList.json" | tr -d ' ')

# version.json 生成（jq で構築）
SHA256=$(shasum -a 256 "$CDN_DIR/blockerList.json" | awk '{print $1}')
SECOND_ADS_SHA256=$(shasum -a 256 "$CDN_DIR/second-ads.json" | awk '{print $1}')
SECOND_ADS_SEC_SHA256=$(shasum -a 256 "$CDN_DIR/second-ads-sec.json" | awk '{print $1}')
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# filters 配列を jq で組み立て
FILTERS_JSON="[]"
for i in "${!NAMES[@]}"; do
  FILTERS_JSON=$(jq -c \
    --arg name "${NAMES[$i]}" \
    --arg license "${LICENSES[$i]}" \
    '. + [{name: $name, license: $license}]' <<< "$FILTERS_JSON")
done

# Plan C Chunk 5: weekly-cdn-sync.yml が書き込んだ既存 reported セクション
# (= moat 行用の rule_count / added_last_month) を preserve する。
EXISTING_REPORTED="null"
if [ -f "$CDN_DIR/version.json" ]; then
  EXISTING_REPORTED=$(jq -c '.reported // null' "$CDN_DIR/version.json")
fi

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --argjson rule_count "$RULE_COUNT" \
  --argjson size_bytes "$JSON_BYTES" \
  --arg sha256 "$SHA256" \
  --argjson filters "$FILTERS_JSON" \
  --argjson reported "$EXISTING_REPORTED" \
  --arg second_ads_sha256 "$SECOND_ADS_SHA256" \
  --arg second_ads_sec_sha256 "$SECOND_ADS_SEC_SHA256" \
  '{generated_at: $generated_at, rule_count: $rule_count, size_bytes: $size_bytes, blocker_list_sha256: $sha256, filters: $filters,
    second_ads_sha256: $second_ads_sha256, second_ads_sec_sha256: $second_ads_sec_sha256}
   + (if $reported != null then {reported: $reported} else {} end)' \
  > "$CDN_DIR/version.json"

# merged-rules.json もここで作り直したので、アプリが見る version-security.json の sha と日時を合わせる
# （security / empty の sha は週次の担当なのでそのまま残す）
MERGED_SHA256=$(shasum -a 256 "$CDN_DIR/merged-rules.json" | awk '{print $1}')
MERGED_BYTES=$(wc -c < "$CDN_DIR/merged-rules.json" | tr -d ' ')
jq --arg sha "$MERGED_SHA256" --argjson bytes "$MERGED_BYTES" --arg at "$GENERATED_AT" \
  '."merged-rules_sha256" = $sha | ."merged-rules_bytes" = $bytes | .generated_at = $at' \
  "$CDN_DIR/version-security.json" > "$TMP_DIR/version-security.json"
mv "$TMP_DIR/version-security.json" "$CDN_DIR/version-security.json"

# bundle 同梱: CDN DL 失敗時の初回起動でも「最終更新日」を表示できるよう App/Resources に同期
cp "$CDN_DIR/version.json" "$PROJECT_DIR/App/Resources/version.json"

echo "[done]"
echo "  $CDN_DIR/blockerList.json ($RULE_COUNT rules, $JSON_BYTES bytes)"
echo "  $CDN_DIR/merged-rules.json / second-ads.json / second-ads-sec.json"
echo "  $CDN_DIR/version.json / version-security.json"
echo "  $PROJECT_DIR/App/Resources/version.json (bundle copy)"
cat "$CDN_DIR/version.json"
