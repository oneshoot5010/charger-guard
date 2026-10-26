#!/data/data/com.termux/files/usr/bin/bash
# يرفع المشروع على جيت هوب، يستنى البناء، ينزّل الـAPK أو يجيب الأخطاء
REPO="oneshoot5010/charger-guard"
cd "$(dirname "$0")" || exit 1
command -v gh >/dev/null || pkg install -y gh git
gh auth status >/dev/null 2>&1 || gh auth login
[ -d .git ] || git init -b main >/dev/null
git add -A
git commit -m "build $(date +%H:%M:%S)" >/dev/null 2>&1
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" --public --source=. --remote=origin || exit 1
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git"
if [ -f signing.b64 ]; then
  gh secret set DEBUG_KEYSTORE_B64 --repo "$REPO" < signing.b64 && echo "🔑 مفتاح التوقيع اتثبّت"
fi
git push -u origin main || exit 1
SHA=$(git rev-parse HEAD)
echo "⏳ بستنى GitHub يبدأ البناء..."
RUN=""
for i in $(seq 1 30); do
  RUN=$(gh run list --repo "$REPO" --commit "$SHA" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
  [ -n "$RUN" ] && break
  sleep 4
done
[ -z "$RUN" ] && { echo "❌ مفيش بناء ظهر"; exit 1; }
if gh run watch "$RUN" --repo "$REPO" --exit-status >/dev/null 2>&1; then
  OUT="$HOME/storage/downloads"; [ -d "$OUT" ] || OUT="$HOME"
  rm -rf $HOME/cg_apk
  gh run download "$RUN" --repo "$REPO" -n charger-guard-apk -D $HOME/cg_apk
  cp $HOME/cg_apk/app-release.apk "$OUT/charger-guard.apk"
  echo "✅ نجح البناء. الـAPK: $OUT/charger-guard.apk"
else
  gh run view "$RUN" --repo "$REPO" --log-failed > errors_full.txt 2>&1
  grep -iE "error|e: |FAILURE|exception|what went wrong" errors_full.txt | head -60 > errors.txt
  [ -s errors.txt ] || tail -60 errors_full.txt > errors.txt
  command -v termux-clipboard-set >/dev/null && termux-clipboard-set < errors.txt && echo "📋 الأخطاء اتنسخت"
  echo "❌ البناء فشل. الأخطاء:"; cat errors.txt
fi
