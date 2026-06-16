// (a)型シミュレーション: 分離可能な「第三者広告スクリプト」。
// このファイルが読み込まれると、サムネのクリックを乗っ取って遷移させる。
// → Content Blocker で resource-type:script ブロックされると、この読込が中止され
//    addEventListener が実行されず、クリック乗っ取りが起きない（＝飛ばされない・黒画面も出ない）。
document.addEventListener('DOMContentLoaded', function () {
  var thumb = document.getElementById('thumb');
  if (thumb) {
    thumb.addEventListener('click', function (e) {
      e.preventDefault();
      // 実サイトの popunder/redirect 相当
      window.location.href = './dest.html?hijacked=external-script';
    });
    document.getElementById('status').textContent =
      '⚠️ hijack.js が読み込まれた（ブロック失敗）→ タップで飛ばされる';
  }
});
