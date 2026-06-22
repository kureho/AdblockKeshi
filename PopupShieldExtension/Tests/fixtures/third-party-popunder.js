'use strict';
// fixture 用「第三者スクリプト」シミュレーション。
// 実際の third-party 広告 script が document クリックで popunder を撃つ挙動を再現する。
// cross-site 判定は registrable で行うため、別 registrable 文字列の URL を使う（ネットワーク不要）。
(function () {
  document.getElementById('vThird').addEventListener('click', function () {
    var w = window.open('https://thirdparty-ad.test/pop?ref=fixture', '_blank');
    window.__fixtureResults = window.__fixtureResults || {};
    window.__fixtureResults.thirdParty = (w === null || w === undefined) ? 'BLOCKED' : (w.__popupShieldStub ? 'STUB' : 'OPENED');
  });
})();
