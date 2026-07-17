#!/usr/bin/env bash
#
# cloudfront-usage.sh — Keith Long Archive traffic + CloudFront Pro-plan gauge
#
# The photos distribution (art-photos, E11XZPTTZY29I9) is on a CloudFront
# flat-rate **Pro plan ($15/month)**. This script shows daily requests/egress
# for both distributions, then gauges the photos distribution's month-to-date
# usage against the Pro-plan allowances:
#
#     Data transfer out : 50 TB / month
#     Requests          : 10 M  / month
#
# NOTE: Pro is a FLAT $15/month with NO overage charges. Exceeding the
# allowance never costs extra — AWS forgives the first 3x spike, evaluates
# sustained excess over 2-3 months, and (only if you persistently exceed) may
# slow delivery. So this gauge is about headroom/performance, not a $ cliff.
#
# Usage:   bash cloudfront-usage.sh [DAYS]      (daily detail, default 7)
# Requires: AWS CLI v2 (configured), bash 4+, gawk. Run from Git Bash.

set -euo pipefail
export TZ=UTC   # force UTC so CloudWatch daily buckets align to calendar days

# --- config ----------------------------------------------------------------
PHOTOS_DIST="E11XZPTTZY29I9"    # art-photos, dd6nj5ah4a2eh.cloudfront.net  (Pro plan)
WEBSITE_DIST="E1WA80M7F42SVB"   # archive.keithlong.com                      (HTML)
REGION="us-east-1"

PRO_TRANSFER_TB=50              # Pro plan monthly data-transfer allowance
PRO_REQUESTS_M=10               # Pro plan monthly request allowance (millions)

GB=1073741824                   # bytes / GiB
TB=1099511627776                # bytes / TiB

DAYS="${1:-7}"

# --- helper: emit "YYYY-MM-DD<TAB>sum" per UTC day for one metric -----------
daily() {   # args: distId  metric  startISO  endISO
  aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront --metric-name "$2" \
    --dimensions Name=DistributionId,Value="$1" Name=Region,Value=Global \
    --start-time "$3" --end-time "$4" --period 86400 --statistics Sum \
    --region "$REGION" \
    --query "sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]" \
    --output text 2>/dev/null \
  | awk '{ printf "%s\t%d\n", substr($1,1,10), $2 }'
}

# --- date bounds ------------------------------------------------------------
today=$(date +%Y-%m-%d)
month_start_d=$(date +%Y-%m-01)
tbl_start_d=$(date -d "$((DAYS-1)) days ago" +%Y-%m-%d)   # inclusive of today => exactly DAYS rows
end=$(date -d "tomorrow" +%Y-%m-%dT00:00:00Z)          # include today's partial
day_of_month=$(date +%-d)
days_in_month=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%-d)

# pull from whichever is earlier so both the table and the MTD sum are covered
data_start_d=$tbl_start_d
[[ "$month_start_d" < "$data_start_d" ]] && data_start_d=$month_start_d
data_start="${data_start_d}T00:00:00Z"

# --- pull daily series into maps -------------------------------------------
declare -A wReq wByte pReq pByte
while IFS=$'\t' read -r d v; do wReq[$d]=$v;  done < <(daily "$WEBSITE_DIST" Requests        "$data_start" "$end")
while IFS=$'\t' read -r d v; do wByte[$d]=$v; done < <(daily "$WEBSITE_DIST" BytesDownloaded "$data_start" "$end")
while IFS=$'\t' read -r d v; do pReq[$d]=$v;  done < <(daily "$PHOTOS_DIST"  Requests        "$data_start" "$end")
while IFS=$'\t' read -r d v; do pByte[$d]=$v; done < <(daily "$PHOTOS_DIST"  BytesDownloaded "$data_start" "$end")

# --- build one per-day stream and let awk do the table + gauge -------------
stream() {
  local d="$data_start_d"
  while [[ "$d" < "$today" || "$d" == "$today" ]]; do
    printf "%s\t%s\t%s\t%s\t%s\n" "$d" "${wReq[$d]:-0}" "${wByte[$d]:-0}" "${pReq[$d]:-0}" "${pByte[$d]:-0}"
    d=$(date -d "$d +1 day" +%Y-%m-%d)
  done
}

stream | awk -F'\t' \
  -v days="$DAYS" -v tbl_start="$tbl_start_d" -v month_start="$month_start_d" -v today="$today" \
  -v dom="$day_of_month" -v dim="$days_in_month" \
  -v ptb="$PRO_TRANSFER_TB" -v prm="$PRO_REQUESTS_M" -v GB="$GB" -v TB="$TB" '
{
  d=$1; wr=$2; wb=$3; pr=$4; pb=$5
  # table (last DAYS only)
  if (d >= tbl_start && d <= today) {
    rows[++n]=sprintf("%-12s %10d %8.2f %11d %8.2f %9.2f", d, wr, wb/GB, pr, pb/GB, (wb+pb)/GB)
  }
  # month-to-date for the Pro-plan (photos) distribution
  if (d >= month_start && d <= today) { mtdB += pb; mtdR += pr }
  # remember most recent COMPLETE day with real photos traffic (= current daily
  # rate). Exclude "today": the current UTC day is partial and would understate.
  if (pb > 0 && d < today) { lastD=d; lastB=pb; lastR=pr }
}
END {
  print ""
  print "CloudFront usage — Keith Long Archive   (last " days " days, UTC)"
  print "============================================================================="
  printf "%-12s %10s %8s %11s %8s %9s\n", "Day","Web req","Web GB","Photos req","Ph. GB","Total GB"
  print "-----------------------------------------------------------------------------"
  for (i=1;i<=n;i++) print rows[i]
  print "-----------------------------------------------------------------------------"

  # ---- Pro-plan gauge (photos distribution) ----
  mtdTB  = mtdB/TB
  mtdRM  = mtdR/1e6
  pctT   = 100*mtdTB/ptb
  pctR   = 100*mtdRM/prm

  # projection "at the most recent full-day rate" (honest for a mid-month start,
  # where dividing MTD by day-of-month would understate the post-repoint rate)
  projTB = (lastB*dim)/TB
  projRM = (lastR*dim)/1e6
  ppctT  = 100*projTB/ptb
  ppctR  = 100*projRM/prm

  printf "\nPro plan ($15/mo, art-photos) — month-to-date vs allowance\n"
  gauge("Data transfer", mtdTB, ptb, "TB", pctT)
  gauge("Requests     ", mtdRM, prm, "M ", pctR)

  if (lastD != "")
    printf "\nAt the most recent full day (%s: %.1f GB, %s req), a full month projects to:\n", \
           lastD, lastB/GB, commas(lastR)
  printf "   transfer ~%.1f TB (%.0f%% of 50 TB) , requests ~%.1f M (%.0f%% of 10 M)\n", projTB, ppctT, projRM, ppctR

  bind = (ppctR >= ppctT) ? "requests" : "data transfer"
  printf "   -> %s is the tighter constraint at this traffic mix.\n", bind

  print  ""
  worst = (ppctT>ppctR)?ppctT:ppctR
  if (worst < 60)
    print "  OK — well within Pro allowances. No overage charges regardless; nothing to do."
  else if (worst < 100)
    print "  ~ Trending toward the allowance. No charges even if exceeded, but watch the 80%/100% emails."
  else
    print "  ** Projected over allowance. Still NO overage $, but sustained 3+ mo excess could slow delivery — consider Business tier."
  print  "  (Reminder: first 3x spike/month is forgiven; excess is judged over 2-3 months, never billed.)"
  print  ""
}
# ASCII gauge bar
function gauge(label, used, cap, unit, pct,   nbar,bar,i) {
  nbar = int(pct/5); if (nbar>20) nbar=20; if (nbar<0) nbar=0
  bar=""; for (i=0;i<20;i++) bar = bar (i<nbar ? "#" : ".")
  printf "  %s [%s] %6.2f / %d %s  (%.1f%%)\n", label, bar, used, cap, unit, pct
}
# crude thousands separator for request counts
function commas(x,   s,r) {
  x=sprintf("%d",x); s=""
  while (length(x)>3){ s=","substr(x,length(x)-2)s; x=substr(x,1,length(x)-3) }
  return x s
}
'
