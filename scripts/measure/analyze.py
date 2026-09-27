#!/usr/bin/env python3
"""
scripts/measure/analyze.py

measure.swift の run 出力（A0/A1/A2/A3 の JSON、各サイト×repeat）を読み、
scripts/measure/extract-block-domains.py の出力（広告・トラッキングドメイン集合）と突き合わせて
「漏れ」「崩れの疑い」「バラつき（2回の測定差）」を判定する。JSON と Markdown の両方を出す。

使い方:
  python3 scripts/measure/analyze.py \
    --domains out/ad-domains.txt \
    --a0 out/A0.json --a1 out/A1.json --a2 out/A2.json --a3 out/A3.json \
    --out-json out/summary.json --out-md out/summary.md

判定基準（このスクリプトが機械的に決める部分）:
  - 漏れ = そのサイトで観測された resources のホスト名のうち、ドメイン集合の要素と
    「完全一致 または そのドメインのサブドメインである」もの（例: ad.example.com は
    example.com のサブドメインなので一致とみなす）。A0（無規則）でも同じ判定を通し、
    「A0でも出るなら参考記事等への被リンクや広告以外の一致の可能性がある」ことが分かるよう
    A0のカウントも常に一緒に出す。
  - 崩れの疑い = 同一サイトで A0 の textLen or imgCount に対し、規則ありconfigの値が
    ★両repeatとも★ 30%以上下回っている場合。片方のrepeatだけ下回る場合は「不安定」扱いにして
    崩れ判定に使わない（バラつきの節で別途警告）。
  - バラつき = 同一サイト・同一configの2 repeat間で resourceCount の差が
    max(1, 大きい方の30%) を超える場合、そのサイト×configの数値は「変動大＝判断に使わない」
    フラグを立てる（タスク仕様の「2回開いて再現性を見る」に対応）。
"""
import argparse
import json
import sys
from urllib.parse import urlparse


def load_domains(path):
    with open(path, encoding="utf-8") as f:
        return set(line.strip() for line in f if line.strip())


def host_matches_domain_set(host, domains):
    if not host:
        return False
    host = host.lower()
    if host in domains:
        return True
    # サブドメイン一致（例: ad.doubleclick.net -> doubleclick.net）
    parts = host.split(".")
    for i in range(1, len(parts) - 1):
        cand = ".".join(parts[i:])
        if cand in domains:
            return True
    return False


def load_config(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    by_site = {}
    for rec in data.get("results", []):
        by_site.setdefault(rec["site"], []).append(rec)
    return data.get("config", "?"), data.get("rules", []), by_site


def leak_count(rec, domains):
    hosts = rec.get("resources", [])
    return sum(1 for h in hosts if host_matches_domain_set(h, domains))


def pct_drop(base, val):
    if base is None or base <= 0:
        return None
    if val is None or val < 0:
        return None
    return round((base - val) / base * 100, 1)


def variance_flag(reps, key):
    vals = [r.get(key) for r in reps if isinstance(r.get(key), (int, float)) and r.get(key, -1) >= 0]
    if len(vals) < 2:
        return True  # 片方しか値がない=判断に使わない
    lo, hi = min(vals), max(vals)
    if hi == 0:
        return False
    return (hi - lo) > max(1, hi * 0.3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--domains", required=True)
    ap.add_argument("--a0", required=True)
    ap.add_argument("--a1", required=True)
    ap.add_argument("--a2", required=True)
    ap.add_argument("--a3", required=True)
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--out-md", required=True)
    args = ap.parse_args()

    domains = load_domains(args.domains)
    configs = {}
    for key, path in (("A0", args.a0), ("A1", args.a1), ("A2", args.a2), ("A3", args.a3)):
        name, rules, by_site = load_config(path)
        configs[key] = {"name": name, "rules": rules, "by_site": by_site}

    all_sites = sorted(configs["A0"]["by_site"].keys())

    per_site = []
    for site in all_sites:
        row = {"site": site}
        a0_reps = configs["A0"]["by_site"].get(site, [])
        a0_text = [r.get("textLen", -1) for r in a0_reps if r.get("textLen", -1) >= 0]
        a0_img = [r.get("imgCount", -1) for r in a0_reps if r.get("imgCount", -1) >= 0]
        a0_text_avg = sum(a0_text) / len(a0_text) if a0_text else None
        a0_img_avg = sum(a0_img) / len(a0_img) if a0_img else None

        for cfg in ("A0", "A1", "A2", "A3"):
            reps = configs[cfg]["by_site"].get(site, [])
            leaks = [leak_count(r, domains) for r in reps]
            failed_any = any(r.get("failed") for r in reps)
            main_reported_all = all(r.get("mainReported") for r in reps) if reps else False
            text_drops = []
            img_drops = []
            for r in reps:
                if cfg != "A0":
                    text_drops.append(pct_drop(a0_text_avg, r.get("textLen", -1)))
                    img_drops.append(pct_drop(a0_img_avg, r.get("imgCount", -1)))
            leak_var = variance_flag(reps, "resourceCount") if reps else True
            row[cfg] = {
                "leaks": leaks,
                "leaksAvg": round(sum(leaks) / len(leaks), 1) if leaks else None,
                "resourceCounts": [r.get("resourceCount") for r in reps],
                "textLens": [r.get("textLen") for r in reps],
                "imgCounts": [r.get("imgCount") for r in reps],
                "textDropPct": text_drops,
                "imgDropPct": img_drops,
                "failed": failed_any,
                "mainReportedAll": main_reported_all,
                "highVariance": leak_var,
            }
        # 崩れの疑い: A1/A2/A3 いずれかで、両repeatとも text か img が30%以上ドロップ
        suspects = []
        for cfg in ("A1", "A2", "A3"):
            td = row[cfg]["textDropPct"]
            idrop = row[cfg]["imgDropPct"]
            text_all_drop = len(td) > 0 and all(d is not None and d >= 30 for d in td)
            img_all_drop = len(idrop) > 0 and all(d is not None and d >= 30 for d in idrop)
            if text_all_drop or img_all_drop:
                suspects.append(cfg)
        row["suspectedBreakage"] = suspects
        per_site.append(row)

    summary = {
        "domainSetSize": len(domains),
        "configs": {k: {"name": v["name"], "rules": v["rules"]} for k, v in configs.items()},
        "sites": per_site,
    }
    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    # Markdown
    lines = []
    lines.append("# AdblockKeshi 規則効果ベースライン測定（A0/A1/A2/A3）")
    lines.append("")
    lines.append(f"- 広告/トラッキングドメイン集合: {len(domains)} 件（226,877件の無制限変換から抽出）")
    lines.append(f"- A0={configs['A0']['rules']} / A1={configs['A1']['rules']} / A2={configs['A2']['rules']} / A3={configs['A3']['rules']}")
    lines.append("")
    lines.append("## サイト別 漏れ件数（平均・2回分）と崩れ疑い")
    lines.append("")
    lines.append("| サイト | A0漏れ | A1漏れ | A2漏れ | A3漏れ | 崩れ疑い | バラつき大 |")
    lines.append("|---|---|---|---|---|---|---|")
    for row in per_site:
        site = row["site"]
        a0 = row["A0"]["leaksAvg"]
        a1 = row["A1"]["leaksAvg"]
        a2 = row["A2"]["leaksAvg"]
        a3 = row["A3"]["leaksAvg"]
        susp = ",".join(row["suspectedBreakage"]) or "-"
        varflags = [cfg for cfg in ("A0", "A1", "A2", "A3") if row[cfg]["highVariance"]]
        varstr = ",".join(varflags) or "-"
        lines.append(f"| {site} | {a0} | {a1} | {a2} | {a3} | {susp} | {varstr} |")

    lines.append("")
    lines.append("## 集計")
    total_leaks = {cfg: sum((row[cfg]["leaksAvg"] or 0) for row in per_site) for cfg in ("A0", "A1", "A2", "A3")}
    for cfg in ("A0", "A1", "A2", "A3"):
        lines.append(f"- {cfg} 合計漏れ(平均): {round(total_leaks[cfg], 1)}")
    if total_leaks["A0"] > 0:
        for cfg in ("A1", "A2", "A3"):
            reduction = round((1 - total_leaks[cfg] / total_leaks["A0"]) * 100, 1) if total_leaks["A0"] else None
            lines.append(f"- {cfg} は A0 比で漏れ {reduction}% 削減")

    suspects_all = [row["site"] for row in per_site if row["suspectedBreakage"]]
    lines.append("")
    lines.append(f"## 崩れの疑いがあるサイト（{len(suspects_all)} 件）")
    for s in suspects_all:
        row = next(r for r in per_site if r["site"] == s)
        lines.append(f"- {s}: {row['suspectedBreakage']}")

    with open(args.out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"書き出し: {args.out_json} / {args.out_md}", file=sys.stderr)


if __name__ == "__main__":
    main()
