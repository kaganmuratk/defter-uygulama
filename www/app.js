/* Fizyoloji defteri — yerel uygulama. Sunucu yok; veri bu cihazda (Depo) tutulur.
   Depo, ileride senkron katmanı eklenebilsin diye tek yerde toplandı.
   2026-10-29 Kağan geri bildirimleri: tam ekran yazım, çizgilerin içerik öğelerine
   çapalanması (döndürmede kaymaz), piksel tabanlı pürüzsüz çizim, alta sabit sayfalama,
   ağ isteklerinde otomatik tekrar deneme, iç içe kütüphane (kitap→bölüm→part),
   Apple Pencil Pro çift dokunuş → silgi. */
'use strict';

const bekle = (ms) => new Promise((r) => setTimeout(r, ms));

/* ---------- Depo ---------- */
const Depo = {
  oku(anahtar, varsayilan) {
    try { const v = localStorage.getItem('fz:' + anahtar); return v ? JSON.parse(v) : varsayilan; }
    catch { return varsayilan; }
  },
  yaz(anahtar, deger) {
    try { localStorage.setItem('fz:' + anahtar, JSON.stringify(deger)); } catch { /* dolu ya da kapalı */ }
  },
  ilerleme() { return this.oku('ilerleme', {}); },
  ilerlemeYaz(partId, alanlar) {
    const hepsi = this.ilerleme();
    hepsi[partId] = { ...(hepsi[partId] || {}), ...alanlar, guncelleme: Date.now() };
    this.yaz('ilerleme', hepsi);
    Esle.kirli('ilerleme');
  },
  cizim(partId) { return this.oku('cizim:' + partId, { kaydedilen: [], taslak: [], silinen: [], mezar: [] }); },
  cizimYaz(partId, veri) { this.yaz('cizim:' + partId, veri); },
};

/* ---------- Tanı kaydı: cihazda olan hataları sonradan görmek için (Ayarlar → Tanı kaydı) ---------- */
const Tani = {
  yaz(olay, ayrinti = {}) {
    const k = Depo.oku('tani', []);
    k.push({ z: new Date().toISOString().slice(5, 19).replace('T', ' '), olay, ...ayrinti });
    Depo.yaz('tani', k.slice(-40));
  },
};

/* ---------- Yardımcılar ---------- */
const $ = (s, k = document) => k.querySelector(s);
const el = (etiket, ozellik = {}, ...cocuklar) => {
  const e = document.createElement(etiket);
  for (const [k, v] of Object.entries(ozellik)) {
    if (k === 'html') e.innerHTML = v; else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (v === true) e.setAttribute(k, ''); else if (v !== false && v != null) e.setAttribute(k, v);
  }
  for (const c of cocuklar.flat()) if (c != null) e.append(c);
  return e;
};
const SVG = 'http://www.w3.org/2000/svg';
const ikon = (d, boyut = 22) =>
  `<svg viewBox="0 0 24 24" width="${boyut}" height="${boyut}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
const IKON = {
  liste: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  sag: '<path d="M9 6l6 6-6 6"/>', sol: '<path d="M15 6l-6 6 6 6"/>', tik: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  kalem: '<path d="M4 20l1-4L16.5 4.5a2 2 0 0 1 3 3L8 19l-4 1z"/><path d="M14 7l3 3"/>',
  fosforlu: '<path d="M9 4l11 11-5 5-4-1-4 1 1-4-1-4z"/><path d="M5 20h6"/>',
  silgi: '<path d="M8 20h12"/><path d="M5 15l8-8a2 2 0 0 1 3 0l3 3a2 2 0 0 1 0 3l-5 5H9z"/>',
  geri: '<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
};

/* ---------- Ayar: sunucu adresi ve anahtar ---------- */
const VARSAYILAN_SUNUCU = 'https://defter-api.revela-site.workers.dev';
const Ayar = {
  get sunucu() { return Depo.oku('sunucu', VARSAYILAN_SUNUCU); },
  get anahtar() { return Depo.oku('anahtar', ''); },
  kaydet(anahtar) { Depo.yaz('anahtar', String(anahtar).trim()); },
};
const sunucuUrl = (yol) => `${Ayar.sunucu}${yol}${yol.includes('?') ? '&' : '?'}k=${encodeURIComponent(Ayar.anahtar)}`;

/* ---------- İçerik: sunucudan çek, cihazda (IndexedDB) sakla, internetsiz de çalış ----------
   2026-10-29 düzeltme: tek deneme + 4 sn zaman aşımı, uykudan uyanan iPad'de ağı henüz
   hazır değilken "İçerik yüklenemedi" hatası veriyordu (Kağan'ın bildirdiği hata).
   Artık 10 sn + 3 deneme (0 / 1,2 / 2,4 sn arayla); başarısızsa yine cihaz önbelleği deneniyor. */
const Icerik = {
  _db: null,
  db() {
    if (!this._db) this._db = new Promise((coz, red) => {
      const i = indexedDB.open('fz-icerik', 1);
      i.onupgradeneeded = () => i.result.createObjectStore('dosya');
      i.onsuccess = () => coz(i.result); i.onerror = () => red(i.error);
    });
    return this._db;
  },
  async al(anahtar) {
    const db = await this.db();
    return new Promise((coz) => { const r = db.transaction('dosya').objectStore('dosya').get(anahtar); r.onsuccess = () => coz(r.result); r.onerror = () => coz(undefined); });
  },
  async koy(anahtar, deger) {
    const db = await this.db();
    return new Promise((coz) => { const t = db.transaction('dosya', 'readwrite'); t.objectStore('dosya').put(deger, anahtar); t.oncomplete = () => coz(); t.onerror = () => coz(); });
  },
  async ag(yol, ms = 10000, deneme = 3) {
    let sonHata = new Error('çevrimdışı');
    for (let i = 0; i < deneme; i++) {
      if (navigator.onLine === false) break;   // çevrimdışıysa boşuna bekleme; önbellek hemen devreye girsin
      const k = new AbortController(); const z = setTimeout(() => k.abort(), ms);
      try {
        const r = await fetch(sunucuUrl('/icerik/' + yol), { signal: k.signal });
        if (r.status === 401) throw Object.assign(new Error('yetkisiz'), { yetkisiz: true });
        if (!r.ok) {
          const hata = new Error('sunucu ' + r.status);
          // Yalnız geçici sunucu/ağ hatalarını tekrar dene; 404 gibi kalıcı hatayı 30 sn bekletme.
          hata.yeniden = r.status >= 500 || r.status === 408 || r.status === 429;
          throw hata;
        }
        return r;
      } catch (e) {
        Tani.yaz('içerik isteği', { yol, deneme: i + 1, hata: e.name === 'AbortError' ? 'zaman aşımı' : e.message, cevrimici: navigator.onLine });
        if (e.yetkisiz || e.yeniden === false) throw e;
        sonHata = e;
      } finally { clearTimeout(z); }
      if (i + 1 < deneme) await bekle(1200 * (i + 1));
    }
    throw sonHata;
  },
  async json(yol) {
    try { const v = await (await this.ag(yol)).json(); await this.koy('json:' + yol, v); return v; }
    catch (e) { if (e.yetkisiz) throw e; const eski = await this.al('json:' + yol); if (eski) return eski; throw e; }
  },
  async gorsel(yol) {   // 'gorseller/x.png' → blob adresi
    const eski = await this.al('gorsel:' + yol);
    if (eski) return URL.createObjectURL(eski);
    const b = await (await this.ag(yol, 20000)).blob(); await this.koy('gorsel:' + yol, b);
    return URL.createObjectURL(b);
  },
};

/* ---------- Eşitleme: ilerleme ve çizimler cihazlar arası (Cloudflare Worker) ---------- */
const Esle = {
  durum: 'bekliyor', yenile: null, _zaman: 0, _calisiyor: false,
  kirli(anahtar) {
    const k = Depo.oku('kirli', []);
    if (!k.includes(anahtar)) { k.push(anahtar); Depo.yaz('kirli', k); }
    this.planla();
  },
  planla() { clearTimeout(this._zaman); this._zaman = setTimeout(() => this.hepsi(), 2500); },
  async istek(yol, yontem = 'GET', govde) {
    const r = await fetch(sunucuUrl(yol), { method: yontem, headers: govde ? { 'content-type': 'application/json' } : undefined, body: govde ? JSON.stringify(govde) : undefined });
    if (!r.ok) throw new Error('sunucu ' + r.status);
    return r.json();
  },
  async hepsi() {
    if (this._calisiyor || !Ayar.anahtar || navigator.onLine === false) return;
    this._calisiyor = true;
    try {
      const kalan = [];
      for (const a of Depo.oku('kirli', [])) {   // önce yerel değişiklikleri gönder
        try {
          if (a === 'ilerleme') this.ilerlemeUygula(await this.istek('/sync/ilerleme', 'PUT', Depo.ilerleme()));
          else { const y = Depo.cizim(a); this.cizimUygula(a, await this.istek('/sync/cizim/' + encodeURIComponent(a), 'PUT', { kaydedilen: y.kaydedilen, silinen: y.mezar || [] })); }
        } catch { kalan.push(a); }
      }
      Depo.yaz('kirli', kalan);
      const u = await this.istek('/sync');   // sonra uzaktakini al
      this.ilerlemeUygula(u.ilerleme || {});
      for (const [a, v] of Object.entries(u.cizim || {})) this.cizimUygula(a, v);
      this.durum = kalan.length ? 'bekliyor' : 'tamam';
    } catch { this.durum = 'hata'; } finally { this._calisiyor = false; }
  },
  ilerlemeUygula(uzak) {   // part başına son yazan kazanır
    const yerel = Depo.ilerleme(); let degisti = false;
    for (const [id, v] of Object.entries(uzak)) if (!yerel[id] || (v.guncelleme || 0) > (yerel[id].guncelleme || 0)) { yerel[id] = v; degisti = true; }
    if (degisti) Depo.yaz('ilerleme', yerel);
  },
  cizimUygula(anahtar, uzak) {   // çizgi kimliğiyle birleşim; silinenler (mezar) geri gelmez
    const y = Depo.cizim(anahtar);
    const mezar = new Set([...(y.mezar || []), ...(uzak.silinen || [])]);
    const harita = new Map();
    for (const c of [...y.kaydedilen, ...(uzak.kaydedilen || [])]) if (c && c.id && !mezar.has(c.id)) harita.set(c.id, c);
    const yeni = [...harita.values()];
    if (yeni.length !== y.kaydedilen.length || mezar.size !== (y.mezar || []).length) {
      y.kaydedilen = yeni; y.mezar = [...mezar]; Depo.cizimYaz(anahtar, y);
      if (typeof this.yenile === 'function') this.yenile(anahtar);
    }
  },
  baslat() {
    this.hepsi();
    setInterval(() => this.hepsi(), 60000);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') this.hepsi(); });
    addEventListener('online', () => this.hepsi());
  },
};
const json = (yol) => Icerik.json(yol.replace(/^icerik\//, ''));
const uygulama = $('#uygulama');

/* ---------- Tema: sistem / açık / koyu ---------- */
const TEMALAR = ['sistem', 'acik', 'koyu'];
function temaUygula() {
  const t = Depo.oku('tema', 'sistem');
  if (t === 'sistem') document.documentElement.removeAttribute('data-tema');
  else document.documentElement.dataset.tema = t;
}
function temaDugmesi() {
  const t = Depo.oku('tema', 'sistem');
  const yazi = { sistem: 'Tema: sistem', acik: 'Tema: açık', koyu: 'Tema: koyu' }[t];
  const gun = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>';
  const ay = '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>';
  const yari = '<circle cx="12" cy="12" r="9"/><path d="M12 3v18" /><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/>';
  return el('button', { class: 'dugme-yuvarlak tema', 'aria-label': yazi, title: yazi, html: ikon(t === 'acik' ? gun : t === 'koyu' ? ay : yari, 20),
    onclick: () => { Depo.yaz('tema', TEMALAR[(TEMALAR.indexOf(t) + 1) % 3]); temaUygula(); yonlendir(); } });
}
temaUygula();

/* ---------- Yönlendirme: kitaplar → kitap → bölüm → part ---------- */
let aktifTemizle = null;
let hataBekci = null;
async function yonlendir() {
  if (aktifTemizle) { aktifTemizle(); aktifTemizle = null; }
  clearTimeout(hataBekci); hataBekci = null;
  const parca = location.hash.split('/');
  const [, ekran, a, b] = parca;
  window.scrollTo(0, 0);
  if (!Ayar.anahtar) return ayarEkrani();
  try {
    if (ekran === 'ayar') return ayarEkrani();
    if (ekran === 'kitap' && a) return await kitapEkrani(a);
    if (ekran === 'bolum' && a && b) return await bolumEkrani(a, b);
    if (ekran === 'part' && a) return await partEkrani(a);
    return await anaEkran();
  } catch (e) {
    if (e.yetkisiz) return ayarEkrani('Anahtar kabul edilmedi.');
    uygulama.replaceChildren(el('div', { class: 'ana' },
      temaDugmesi(),
      el('h1', {}, 'Açılamadı'),
      el('p', { class: 'alt' }, 'İçerik yüklenemedi. Bağlantın varsa birkaç saniye içinde kendisi yeniden deneyecek.'),
      el('button', { class: 'devam', onclick: () => yonlendir() }, el('span', {}, 'Şimdi dene'))));
    console.error(e);
    hataBekci = setTimeout(() => { if (document.visibilityState === 'visible') yonlendir(); }, 6000);   // uyku→uyanış yarışında kendi toparlasın
  }
}
window.addEventListener('hashchange', yonlendir);

/* ---------- Ayar ekranı ---------- */
function ayarEkrani(mesaj) {
  const alan = el('input', { class: 'ayar-alan', type: 'password', placeholder: 'Anahtar', autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false', value: '' });
  const durumYazi = { tamam: 'Eşitlendi', bekliyor: 'Eşitleme bekliyor', hata: 'Sunucuya ulaşılamadı' }[Esle.durum];
  const kok = el('div', { class: 'ana ayar' },
    temaDugmesi(),
    el('h1', {}, Ayar.anahtar ? 'Ayarlar' : 'Anahtar'),
    mesaj ? el('p', { class: 'alt hata' }, mesaj) : null,
    Ayar.anahtar ? el('p', { class: 'alt' }, durumYazi) : el('p', { class: 'alt' }, 'İçeriği indirmek için anahtarını gir. Bir kez girmen yeter.'),
    alan,
    el('button', { class: 'devam', onclick: async () => {
      if (!alan.value.trim()) return;
      Ayar.kaydet(alan.value); Esle.durum = 'bekliyor';
      try { await Icerik.ag('plan.json'); location.hash = '#/'; yonlendir(); Esle.hepsi(); }
      catch (e) { ayarEkrani(e.yetkisiz ? 'Anahtar kabul edilmedi.' : 'Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.'); }
    } }, el('span', {}, 'Kaydet')),
    Ayar.anahtar ? el('button', { class: 'ikincil', onclick: () => { Esle.hepsi().then(() => ayarEkrani()); } }, 'Şimdi eşitle') : null,
    Ayar.anahtar ? el('button', { class: 'ikincil', onclick: () => { location.hash = '#/'; } }, 'Geri') : null,
    taniKutusu());
  uygulama.replaceChildren(kok);
}

function taniKutusu() {
  const k = Depo.oku('tani', []);
  if (!k.length) return null;
  const satir = (x) => `${x.z}  ${x.olay}  ` + Object.entries(x).filter(([a]) => a !== 'z' && a !== 'olay').map(([a, v]) => `${a}=${v}`).join(' ');
  return el('details', { class: 'cevaplar tani' }, el('summary', {}, `Tanı kaydı (${k.length})`),
    el('pre', {}, k.slice().reverse().map(satir).join('\n')),
    el('button', { class: 'ikincil', onclick: () => { Depo.yaz('tani', []); ayarEkrani(); } }, 'Kaydı temizle'));
}

/* ---------- Ana ekran: kitaplar (iç içe kütüphanenin ilk katmanı) ---------- */
async function anaEkran() {
  const plan = await json('icerik/plan.json');
  const ilerleme = Depo.ilerleme();
  const tum = plan.dersler.flatMap((d) => d.bolumler.flatMap((b) => b.partlar.map((p) => ({ ...p, bolum: b, ders: d }))));
  const son = tum.filter((p) => ilerleme[p.id] && ilerleme[p.id].durum !== 'bitti')
    .sort((a, b) => (ilerleme[b.id].guncelleme || 0) - (ilerleme[a.id].guncelleme || 0))[0];
  const siradaki = son || tum.find((p) => p.hazir && !(ilerleme[p.id] && ilerleme[p.id].durum === 'bitti'));

  const kok = el('div', { class: 'ana' }, temaDugmesi(),
    el('button', { class: 'dugme-yuvarlak ayar-dugme', 'aria-label': 'Ayarlar', onclick: () => { location.hash = '#/ayar'; }, html: ikon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1-.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>', 20) }),
    el('h1', {}, 'Defter'));

  if (siradaki && siradaki.hazir) {
    const yarim = son && son.id === siradaki.id;
    kok.append(el('button', { class: 'devam', onclick: () => (location.hash = '#/part/' + siradaki.id) },
      el('span', {}, yarim ? 'Kaldığın yerden devam' : 'Başla',
        el('small', {}, `${siradaki.ders.baslik}, Bölüm ${siradaki.bolum.no}, Part ${siradaki.no}`)),
      el('span', { html: ikon(IKON.sag, 26) })));
  }

  for (const ders of plan.dersler) {
    const partlar = ders.bolumler.flatMap((b) => b.partlar);
    const biten = partlar.filter((p) => (ilerleme[p.id] || {}).durum === 'bitti').length;
    kok.append(el('button', { class: 'kitap', onclick: () => (location.hash = '#/kitap/' + ders.id) },
      el('span', {}, el('h2', {}, ders.baslik), el('p', {}, `${ders.bolumler.length} bölüm · ${partlar.length} part${ders.kaynak ? ' · ' + ders.kaynak : ''}`)),
      el('span', { class: 'ozet' }, `${biten}/${partlar.length}`, el('i', { class: 'ok', html: ikon(IKON.sag, 22) }))));
  }
  kok.append(el('p', { class: 'sonra' }, 'Yeni kitaplar hazır oldukça buraya eklenecek.'));
  uygulama.replaceChildren(kok);
  document.title = 'Defter';
}

/* ---------- Kitap ekranı: bölümler ---------- */
async function kitapEkrani(kitapId) {
  const plan = await json('icerik/plan.json');
  const ders = plan.dersler.find((d) => d.id === kitapId);
  if (!ders) { location.hash = '#/'; return; }
  const ilerleme = Depo.ilerleme();
  const kok = el('div', { class: 'ana' }, temaDugmesi(),
    el('button', { class: 'ust-geri', onclick: () => (location.hash = '#/') }, el('span', { html: ikon(IKON.sol, 20) }), 'Kitaplar'),
    el('h1', {}, ders.baslik),
    ders.kaynak ? el('p', { class: 'alt' }, 'Kaynak: ' + ders.kaynak) : null);
  for (const bolum of ders.bolumler) {
    const biten = bolum.partlar.filter((p) => (ilerleme[p.id] || {}).durum === 'bitti').length;
    kok.append(el('button', { class: 'kitap', onclick: () => (location.hash = `#/bolum/${ders.id}/${bolum.no}`) },
      el('span', {}, el('h2', {}, `Bölüm ${bolum.no}: ${bolum.baslik}`), el('p', {}, `${bolum.partlar.length} part`)),
      el('span', { class: 'ozet' }, `${biten}/${bolum.partlar.length}`, el('i', { class: 'ok', html: ikon(IKON.sag, 22) }))));
  }
  uygulama.replaceChildren(kok);
  document.title = ders.baslik + ' — Defter';
}

/* ---------- Bölüm ekranı: part listesi ---------- */
async function bolumEkrani(kitapId, bolumNo) {
  const plan = await json('icerik/plan.json');
  const ders = plan.dersler.find((d) => d.id === kitapId);
  const bolum = ders && ders.bolumler.find((b) => String(b.no) === String(bolumNo));
  if (!bolum) { location.hash = '#/kitap/' + kitapId; return; }
  const ilerleme = Depo.ilerleme();
  const kok = el('div', { class: 'ana' }, temaDugmesi(),
    el('button', { class: 'ust-geri', onclick: () => (location.hash = '#/kitap/' + ders.id) }, el('span', { html: ikon(IKON.sol, 20) }), ders.baslik),
    el('h1', {}, `Bölüm ${bolum.no}: ${bolum.baslik}`));
  const bitenler = bolum.partlar.filter((p) => (ilerleme[p.id] || {}).durum === 'bitti').length;
  kok.append(el('p', { class: 'alt' }, `${bitenler} / ${bolum.partlar.length} part bitti`));
  const hat = el('ol', { class: 'hat' });
  for (const p of bolum.partlar) {
    const d = ilerleme[p.id] && ilerleme[p.id].durum;
    const durum = !p.hazir ? 'yok' : d === 'bitti' ? 'bitti' : d === 'yarim' ? 'yarim' : 'hazir';
    const durumYazi = { bitti: 'Bitti', yarim: 'Yarım', hazir: 'Başlamadı', yok: 'Yazılıyor' }[durum];
    const icerik = [
      el('h2', {}, `Part ${p.no}: ${p.baslik}`),
      el('p', {}, el('span', { class: durum === 'yarim' || durum === 'bitti' ? 'durum' : '' }, durumYazi), ` · ${p.kitap}`),
    ];
    const dugum = el('span', { class: 'dugum', html: durum === 'bitti' ? ikon(IKON.tik, 13) : '' });
    const satir = p.hazir
      ? el('button', { onclick: () => (location.hash = '#/part/' + p.id) }, dugum, icerik)
      : el('div', {}, dugum, icerik);
    hat.append(el('li', { class: 'durak', 'data-durum': durum }, satir));
  }
  kok.append(hat);
  uygulama.replaceChildren(kok);
  document.title = `Bölüm ${bolum.no} — Defter`;
}

/* ---------- Part ekranı: her bölüm ayrı sayfa ---------- */
async function partEkrani(id) {
  const [plan, part] = await Promise.all([json('icerik/plan.json'), json(`icerik/${id}.json`)]);
  let geriYol = '#/';
  for (const d of plan.dersler) for (const b of d.bolumler) if (b.partlar.some((p) => p.id === id)) geriYol = `#/bolum/${d.id}/${b.no}`;
  const bolumler = part.bolumler, N = bolumler.length;
  const kayit = Depo.ilerleme()[id] || {};
  let sayfa = Math.min(Math.max(kayit.sayfa || 0, 0), N - 1);
  const ziyaret = new Set(kayit.ziyaret || [sayfa]);
  const genis = matchMedia('(min-width: 62rem)');
  let kalem = null;

  const ilerlemeCubuk = el('div', { class: 'ilerleme', 'aria-hidden': 'true' }, el('i'));
  const ust = el('header', { class: 'ust' },
    el('button', { class: 'geri', onclick: () => cikis() }, el('span', { html: ikon(IKON.sol, 20) }), 'Geri'),
    el('span', { class: 'ad' }, `Part ${part.no}: ${part.baslik}`),
    el('button', { class: 'dugme-yuvarlak', 'aria-label': 'Bölüm listesini aç ya da kapat', onclick: () => listeDegis(), html: ikon(IKON.liste, 20) }),
    temaDugmesi(), ilerlemeCubuk);
  const liste = el('ol');
  bolumler.forEach((b, i) => liste.append(el('li', {}, el('button', { onclick: () => git(i) }, b.kisa || b.baslik))));
  const ray = el('nav', { class: 'ray', 'aria-label': 'Bölümler' },
    el('h2', {}, `Part ${part.no}: ${part.baslik}`), el('p', { class: 'alt-baslik' }, `Bölüm ${part.bolumNo || 1}`), liste);
  const perde = el('div', { class: 'perde', onclick: () => listeDegis(false) });
  const sayfaKutu = el('main', { class: 'sayfa' });
  const duzen = el('div', { class: 'duzen' + (Depo.oku('railKapali', false) ? ' kapali' : '') }, ray, sayfaKutu);
  uygulama.replaceChildren(ust, duzen, perde);
  document.title = `Part ${part.no}: ${part.baslik}`;

  function listeDegis(zorla) {
    if (genis.matches) {
      const kapali = zorla === undefined ? !duzen.classList.contains('kapali') : !zorla;
      duzen.classList.toggle('kapali', kapali); Depo.yaz('railKapali', kapali);
    } else {
      const ac = zorla === undefined ? !ray.classList.contains('acik') : zorla;
      ray.classList.toggle('acik', ac); perde.classList.toggle('acik', ac);
    }
  }
  function kaydet() {
    const mevcut = Depo.ilerleme()[id] || {};
    Depo.ilerlemeYaz(id, { sayfa, ziyaret: [...ziyaret], durum: mevcut.durum === 'bitti' ? 'bitti' : 'yarim' });
  }
  async function git(i) {
    if (i < 0 || i >= N) return;
    if (kalem && !(await kalem.cikisKontrol())) return;
    if (kalem) kalem.kaldir();
    sayfa = i; ziyaret.add(i); kaydet(); sayfaCiz(); if (!genis.matches) listeDegis(false); scrollTo(0, 0);
  }
  function bitirDegis() {
    const bitti = (Depo.ilerleme()[id] || {}).durum === 'bitti';
    Depo.ilerlemeYaz(id, { durum: bitti ? 'yarim' : 'bitti' });
    // Eski kalem örneğini bırakıp yeniden kur; aksi hâlde her basışta dinleyici/observer birikir.
    if (kalem) { kalem.kaldir(); kalem = null; }
    sayfaCiz();
  }
  function sayfaCiz() {
    const b = bolumler[sayfa];
    const metin = el('div', { class: 'metin' }, el('h1', {}, b.baslik));
    metin.insertAdjacentHTML('beforeend', (sayfa === 0 && part.giris ? part.giris : '') + b.html);
    metin.querySelectorAll('img').forEach((g) => {   // görseller sunucudan gelir, cihazda saklanır
      const yol = (g.getAttribute('src') || '').replace(/^icerik\//, '');
      g.removeAttribute('src');
      Icerik.gorsel(yol).then((u) => { g.src = u; }).catch(() => { g.alt = 'Görsel yüklenemedi'; });
    });
    const bitti = (Depo.ilerleme()[id] || {}).durum === 'bitti';
    const son = sayfa === N - 1;
    const ileri = son
      ? el('button', { class: 'bitir', 'aria-pressed': String(bitti), onclick: bitirDegis }, bitti ? 'Bitti, geri almak için dokun' : 'Bitirdim')
      : el('button', { class: 'ileri', onclick: () => git(sayfa + 1) }, 'Sonraki', el('span', { html: ikon(IKON.sag, 20) }));
    const geri = el('button', { disabled: sayfa === 0, onclick: () => git(sayfa - 1) }, el('span', { html: ikon(IKON.sol, 20) }), 'Önceki');
    // Sabit genişlikli kâğıt (Kağan 2026-10-30): metin her yönde aynı genişlikte dizilir, ekrana yalnız
    // ölçeklenir. Böylece dikey↔yatay geçişte yazı yeniden akmaz, çizimler aynı yerde kalır (GoodNotes/Notability yolu).
    // Kalem katmanı tüm sayfa yüzeyinde (Kağan 2026-10-29: "ekranın her yerine yazayım").
    const kagit = el('div', { class: 'kagit' }, metin, el('div', { class: 'sayfalama' }, geri, ileri));
    sayfaKutu.replaceChildren(el('div', { class: 'sahne' }, kagit));
    $('i', ilerlemeCubuk).style.width = ((sayfa + 1) / N * 100) + '%';
    [...liste.children].forEach((li, i) => {
      li.classList.toggle('simdi', i === sayfa);
      li.classList.toggle('tamam', i !== sayfa && ziyaret.has(i));
    });
    // Görsel büyüteç
    const buyutec = $('#buyutec'); const bImg = $('img', buyutec);
    metin.addEventListener('click', (e) => {
      const g = e.target.closest('img'); if (!g) return;
      bImg.src = g.src; bImg.alt = g.alt; buyutec.classList.remove('yakin'); buyutec.hidden = false;
    });
    buyutec.onclick = () => { if (buyutec.classList.contains('yakin')) buyutec.hidden = true; else buyutec.classList.add('yakin'); };
    kalem = kalemKatmani(`${id}#${sayfa}`, sayfaKutu, kagit);
  }
  async function cikis() {
    if (kalem && !(await kalem.cikisKontrol())) return;
    location.hash = geriYol;
  }
  kaydet(); sayfaCiz();
  aktifTemizle = () => { if (kalem) kalem.kaldir(); $('#buyutec').hidden = true; };
}

/* ---------- Kâğıt ölçeği ----------
   2026-10-30 (Kağan: "dikeyde boşluğa yazdığım not yataya çevirince başka yere geliyor"):
   Metin sabit mantıksal genişlikte (KAGIT_GENISLIK) dizilir ve ekrana yalnız ölçeklenir. Yazı hiç
   yeniden akmadığı için çizimler tek bir koordinat uzayında (kâğıt pikseli) saklanır ve hiç kaymaz.
   Genişlik cihazın KISA kenarından seçilir; döndürmede değişmez. Telefonda daha dar kâğıt kullanılır
   ki yazı okunur kalsın (çizimler cihaz düzenine bağlıdır; iPad ↔ telefon arası birebir eşleşmez). */
const KISA_KENAR = Math.min(screen.width, screen.height);
const KAGIT_GENISLIK = KISA_KENAR < 600 ? 400 : 800;
const KAGIT_EN_BUYUK = 1.35;   // geniş yatay ekranda yazı aşırı büyümesin
function kagitOlcegi(genislik) { return Math.min(Math.max(genislik, 200) / KAGIT_GENISLIK, KAGIT_EN_BUYUK); }
// Kısa sayfada da Önceki/Sonraki en altta: kâğıdın en az yüksekliği dikey ekrandan hesaplanır ve
// döndürmede DEĞİŞMEZ (yoksa altta boşluğa yazılan not yatayda düğmelerin altında kalırdı).
// 240 px: üst çubuk, sayfa boşlukları ve alttaki araç çubuğu payı (dikeyde düğmeler kaydırmadan görünsün).
const KAGIT_EN_AZ = Math.round((Math.max(screen.width, screen.height) - 240) / kagitOlcegi(KISA_KENAR - 32));

/* ---------- Kalem katmanı ----------
   2026-10-29/30 (Kağan'ın geri bildirimleri):
   - Yüzey tüm sayfa: ekranın her yerine yazılır; kâğıdın dışındaki kenar boşluğu da sayılır.
   - Çizgiler kâğıt pikselinde saklanır (sürüm 3); eski sürümler ilk açılışta dönüştürülür.
   - Çizgi şekli perfect-freehand ile (tldraw/Excalidraw'ın kullandığı yöntem): girdi yumuşatılır,
     kalem basıncıyla kalınlık değişir, kenarlar pürüzsüz dolgu olarak çizilir ("piksel piksel" sorunu).
   - Apple Pencil Pro/2: çift dokunuş ya da sıkıştırma → silgi; kalem ekrandan kalkınca → kalem. */
const RENKLER = {
  kalem: [['mürekkep', 'var(--murekkep)'], ['lacivert', '#1c7ed6'], ['yeşil', '#2f9e44'], ['turuncu', '#e8590c'], ['bordo', '#c2255c'], ['mor', '#6741d9']],
  fosforlu: [['sarı', '#f3d44a'], ['yeşil', '#8fd694'], ['pembe', '#f4a6c0'], ['turuncu', '#f9a825'], ['mavi', '#74c0fc']],
};
const KALINLIK = { kalem: 3.2, fosforlu: 20 };
const SILGI_YARI_CAP = 26;   // kâğıt pikseli
const CIZGI_SURUM = 3;

const CAPA_SELC = 'h1,h2,h3,h4,p,li,img,blockquote,hr,table,.tablo,ol,ul,.sayfalama,.cevaplar,figure';

function kalemKatmani(partId, yuzey, kagit) {
  let veri = Depo.cizim(partId);
  const sahne = kagit.parentElement;
  let olcek = 1;
  function yerlestir() {
    const stil = getComputedStyle(yuzey);
    const genislik = yuzey.clientWidth - parseFloat(stil.paddingLeft) - parseFloat(stil.paddingRight);
    olcek = kagitOlcegi(genislik);
    kagit.style.transform = `translateX(-50%) scale(${olcek})`;
    sahne.style.height = (kagit.offsetHeight * olcek) + 'px';
  }
  kagit.style.width = KAGIT_GENISLIK + 'px';
  kagit.style.minHeight = KAGIT_EN_AZ + 'px';
  if (KAGIT_GENISLIK < 800) kagit.classList.add('dar');
  yerlestir();

  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('class', 'cizim');
  svg.setAttribute('aria-hidden', 'true');
  kagit.append(svg);
  // Fosforlu kalem, kaydedildikten sonra metnin ALTINA geçsin (okunabilirlik).
  const zemin = document.createElementNS(SVG, 'svg');
  zemin.setAttribute('class', 'cizim cizim-zemin');
  zemin.setAttribute('aria-hidden', 'true');
  kagit.prepend(zemin);
  const katman = document.createElementNS(SVG, 'g');
  svg.append(katman);
  const zeminKatman = document.createElementNS(SVG, 'g');
  zemin.append(zeminKatman);

  // Eski sürüm çizgileri kâğıt pikseline çevir (bir kez; sonra sürüm 3 olarak kaydedilir).
  // Sürüm 2: öğeye çapalı oranlar (onak = sayfa öğesi ya da 'y' = tüm yüzey). Sürüm 1: yüzey genişliğinin 1000'de biri.
  // Eski düzen artık yok; dönüşüm bugünkü yerleşimden yaklaşık yapılır.
  const onakEl = new Map();
  kagit.querySelectorAll(CAPA_SELC).forEach((e, i) => onakEl.set('c' + (i + 1), e));
  function kagitKutusu(e) {   // öğenin kâğıt pikselindeki kutusu (dönüşümden bağımsız)
    const kr = kagit.getBoundingClientRect(), r = e.getBoundingClientRect();
    return { x: (r.left - kr.left) / olcek, y: (r.top - kr.top) / olcek, w: r.width / olcek, h: r.height / olcek };
  }
  function eskiyiCevir(c) {
    if (c.k === CIZGI_SURUM) return c;
    const yk = kagitKutusu(yuzey);
    let donustur;
    if (!c.onak) donustur = ([x, y]) => [yk.x + x / 1000 * yk.w, yk.y + y / 1000 * yk.w];
    else if (c.onak === 'y') donustur = ([x, y]) => [yk.x + x * yk.w, yk.y + y * yk.h];
    else {
      const e = onakEl.get(c.onak), b = e ? kagitKutusu(e) : { x: 0, y: 0, w: KAGIT_GENISLIK, h: KAGIT_EN_AZ };
      donustur = ([x, y]) => [b.x + x * b.w, b.y + y * b.h];
    }
    const { onak, ax, ay, ...kalan } = c;
    return { ...kalan, k: CIZGI_SURUM, noktalar: c.noktalar.map((p) => [...donustur(p).map((v) => Math.round(v * 10) / 10), 0.5]) };
  }
  if ([...veri.kaydedilen, ...veri.taslak].some((c) => c.k !== CIZGI_SURUM)) {
    veri.kaydedilen = veri.kaydedilen.map(eskiyiCevir);
    veri.taslak = veri.taslak.map(eskiyiCevir);
    Depo.cizimYaz(partId, veri);
  }

  let arac = 'kalem';
  let renk = { kalem: 'mürekkep', fosforlu: 'sarı' };
  let aktifCizgi = null;
  let aktifYol = null;   // çizilmekte olan çizginin <path> öğesi
  const fareIle = location.search.includes('fare');

  const ro = new ResizeObserver(() => yerlestir());
  ro.observe(yuzey); ro.observe(kagit);
  const don = () => { yerlestir(); setTimeout(yerlestir, 350); };   // döndürme sonrası geç düzen
  addEventListener('orientationchange', don);

  const renkDeger = (ad) => (Object.values(RENKLER).flat().find((r) => r[0] === ad) || [0, 'currentColor'])[1];
  function sekil(c) {   // perfect-freehand: çizginin dolgu çokgeni → SVG yolu
    const fos = c.arac === 'fosforlu';
    const kontur = getStroke(c.noktalar, {
      size: c.kalinlik * (fos ? 1 : 2.2), thinning: fos ? 0 : 0.55, smoothing: 0.6, streamline: fos ? 0.6 : 0.45,
      simulatePressure: !!c.basincYok, last: c !== aktifCizgi,
      start: { cap: !fos }, end: { cap: !fos },
    });
    if (!kontur.length) return '';
    let d = `M${kontur[0][0].toFixed(1)} ${kontur[0][1].toFixed(1)}Q`;
    for (let i = 0; i < kontur.length; i++) {
      const [x0, y0] = kontur[i], [x1, y1] = kontur[(i + 1) % kontur.length];
      d += `${x0.toFixed(1)} ${y0.toFixed(1)} ${((x0 + x1) / 2).toFixed(1)} ${((y0 + y1) / 2).toFixed(1)} `;
    }
    return d + 'Z';
  }
  function yolEl(c) {
    if (!c.noktalar || !c.noktalar.length) return null;
    const t = document.createElementNS(SVG, 'path');
    t.setAttribute('d', sekil(c));
    t.setAttribute('class', c.arac === 'fosforlu' ? 'fosforlu' : 'kalem');
    t.style.fill = renkDeger(c.renk);
    t.dataset.id = c.id;
    return t;
  }
  function ciz() {
    const silinen = new Set(veri.silinen);
    const kayitli = veri.kaydedilen.filter((c) => !silinen.has(c.id));
    const taslak = veri.taslak;
    const fosforluKayit = kayitli.filter((c) => c.arac === 'fosforlu');
    const fosforluTaslak = taslak.filter((c) => c.arac === 'fosforlu');
    const digerleri = [...kayitli.filter((c) => c.arac !== 'fosforlu'), ...taslak.filter((c) => c.arac !== 'fosforlu')];
    // Kayıtlı fosforlu katman metnin altında; canlı taslak ve kalem metnin üstünde.
    zeminKatman.replaceChildren(...fosforluKayit.map(yolEl).filter(Boolean));
    katman.replaceChildren(...fosforluTaslak.map(yolEl).filter(Boolean), ...digerleri.map(yolEl).filter(Boolean));
  }
  const taslakVar = () => veri.taslak.length > 0 || veri.silinen.length > 0;
  const kaydetAyar = () => Depo.cizimYaz(partId, veri);

  /* Araç çubuğu */
  const cubuk = el('div', { class: 'arac', role: 'toolbar', 'aria-label': 'Çizim araçları' });
  function cubukCiz() {
    const dugmeler = [];
    for (const [ad, yazi, i] of [['kalem', 'Kalem', IKON.kalem], ['fosforlu', 'Fosforlu kalem', IKON.fosforlu], ['silgi', 'Silgi', IKON.silgi]]) {
      dugmeler.push(el('button', { 'aria-label': yazi, 'aria-pressed': String(arac === ad), html: ikon(i), onclick: () => { arac = ad; pencilSilgi = false; cubukCiz(); } }));
    }
    if (arac !== 'silgi') {
      dugmeler.push(el('span', { class: 'ayirac' }));
      for (const [ad, deger] of RENKLER[arac]) {
        dugmeler.push(el('button', { class: 'renk', 'aria-label': 'Renk ' + ad, 'aria-pressed': String(renk[arac] === ad),
          html: `<i style="background:${deger}"></i>`, onclick: () => { renk[arac] = ad; cubukCiz(); } }));
      }
    }
    dugmeler.push(el('span', { class: 'ayirac' }),
      el('button', { 'aria-label': 'Geri al', html: ikon(IKON.geri), onclick: () => geriAl() }));
    // Kaydet/Vazgeç ayrı bir çubuk değil, aynı çubuğun sonunda (2026-10-30: ayrı çubuk Önceki/Sonraki'yi örtüyordu).
    if (taslakVar()) dugmeler.push(el('span', { class: 'ayirac' }),
      el('button', { class: 'vazgec-d', onclick: () => vazgec() }, 'Vazgeç'),
      el('button', { class: 'kaydet-d', onclick: () => kaydet() }, 'Kaydet'));
    cubuk.replaceChildren(...dugmeler);
  }
  document.body.append(cubuk);
  cubukCiz(); ciz();
  const yenileFn = (anahtar) => { if (anahtar === partId) { veri = Depo.cizim(partId); ciz(); cubukCiz(); } };   // başka cihazdan gelen çizim
  Esle.yenile = yenileFn;

  function geriAl() {
    if (veri.taslak.length) veri.taslak.pop(); else if (veri.silinen.length) veri.silinen.pop();
    kaydetAyar(); ciz(); cubukCiz();
  }
  function kaydet() {
    veri.kaydedilen.push(...veri.taslak);
    const silinen = new Set(veri.silinen);
    veri.kaydedilen = veri.kaydedilen.filter((c) => !silinen.has(c.id));
    veri.mezar = [...new Set([...(veri.mezar || []), ...veri.silinen])];   // silinenler cihazlar arası geri gelmesin
    veri.taslak = []; veri.silinen = [];
    kaydetAyar(); ciz(); cubukCiz();
    Esle.kirli(partId);
  }
  function vazgec() { veri.taslak = []; veri.silinen = []; kaydetAyar(); ciz(); cubukCiz(); }

  /* Çizim girdisi: yalnız kalem (ya da ?fare ile fare). Parmak kaydırır. */
  function nokta(e) {   // kâğıt pikseli + basınç
    const kr = kagit.getBoundingClientRect();
    const p = e.pointerType === 'pen' && e.pressure > 0 ? e.pressure : 0.5;
    return [Math.round((e.clientX - kr.left) / olcek * 10) / 10, Math.round((e.clientY - kr.top) / olcek * 10) / 10, Math.round(p * 100) / 100];
  }
  const cizebilir = (e) => (e.isPrimary !== false) && (e.pointerType === 'pen' || (fareIle && e.pointerType === 'mouse'));
  function siliciGec(e) {
    const [x, y] = nokta(e);
    const silinen = new Set(veri.silinen);
    const deg = (c) => c.noktalar.some((p) => Math.hypot(p[0] - x, p[1] - y) < SILGI_YARI_CAP + c.kalinlik);
    veri.taslak = veri.taslak.filter((c) => !deg(c));
    for (const c of veri.kaydedilen) if (!silinen.has(c.id) && deg(c)) veri.silinen.push(c.id);
    ciz();
  }
  function basla(e) {
    if (!cizebilir(e)) return;
    // Kalemle düğmeye/bağlantıya dokunmak çizim değil, tıklamadır (Sonraki, cevaplar, görsel büyüteci).
    if (e.target.closest && e.target.closest('button, a, summary, input, .sayfalama')) return;
    e.preventDefault();
    try { yuzey.setPointerCapture(e.pointerId); } catch {}
    if (arac === 'silgi') { aktifCizgi = 'silgi'; siliciGec(e); return; }
    aktifCizgi = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), k: CIZGI_SURUM, arac, renk: renk[arac], kalinlik: KALINLIK[arac],
      basincYok: e.pointerType !== 'pen' || undefined, noktalar: [nokta(e)] };
    veri.taslak.push(aktifCizgi); ciz();
    aktifYol = katman.querySelector(`[data-id="${aktifCizgi.id}"]`);
  }
  // Kalem hareketinde yalnız çizilen çizgi güncellenir; tüm çizgileri her harekette baştan kurmak
  // çizgi sayısı arttıkça gecikme yapıyordu (2026-10-30 denetimi).
  function aktifGuncelle() {
    // Boyut değişimi çizgi sürerken yolları yeniden kurmuş olabilir.
    if (!aktifYol || !aktifYol.isConnected) aktifYol = katman.querySelector(`[data-id="${aktifCizgi.id}"]`);
    if (!aktifYol) { ciz(); return; }
    aktifYol.setAttribute('d', sekil(aktifCizgi));
  }
  function hareket(e) {
    if (!aktifCizgi || !cizebilir(e)) return;
    e.preventDefault();
    let olaylar = [];
    try { olaylar = e.getCoalescedEvents ? e.getCoalescedEvents() : []; } catch { olaylar = []; }
    if (!olaylar.length) olaylar = [e];
    if (aktifCizgi === 'silgi') { olaylar.forEach(siliciGec); return; }
    for (const o of olaylar) aktifCizgi.noktalar.push(nokta(o));
    aktifGuncelle();
  }
  function bitis() {
    if (!aktifCizgi) return;
    const biten = aktifCizgi;
    aktifCizgi = null; aktifYol = null; kaydetAyar(); cubukCiz();
    if (biten !== 'silgi') ciz();   // son hâl: uç kapanışı (last: true) ile yeniden şekillenir
  }
  yuzey.addEventListener('pointerdown', basla);
  yuzey.addEventListener('pointermove', hareket);
  yuzey.addEventListener('pointerup', bitis);
  // Tanı: çizgi iptal olursa (iPad kaydırmaya geçti, avuç vb.) kalem açısıyla kaydet (Ayarlar → Tanı kaydı).
  const iptal = (e) => {
    if (aktifCizgi && aktifCizgi !== 'silgi') Tani.yaz('kalem iptal', { tur: e.pointerType, yukseklikAcisi: e.altitudeAngle != null ? Math.round(e.altitudeAngle * 57.3) + '°' : '?', nokta: aktifCizgi.noktalar.length });
    bitis();
  };
  yuzey.addEventListener('pointercancel', iptal);
  // Kalem dokunuşları sayfayı kaydırmasın; parmak kaydırmaya devam etsin.
  // Eğik tutulan kalemde avuç çoğu zaman ekrana önce değer: touches[0] avuç olur ve kalem sayfayı
  // kaydırmaya başlar (pointercancel → çizgi kopar). Bu yüzden dokunuşların HERHANGİ biri kalemse engelle.
  const kalemTouch = (e) => { if ([...e.touches].some((t) => t.touchType === 'stylus')) e.preventDefault(); };
  yuzey.addEventListener('touchstart', kalemTouch, { passive: false });
  yuzey.addEventListener('touchmove', kalemTouch, { passive: false });

  /* Apple Pencil çift dokunuş / Pro sıkıştırma (yerli katmandan 'pencilCiftDokun' olayı) → silgi */
  let pencilSilgi = false;
  const pencilCb = () => {
    if (arac === 'silgi') { arac = 'kalem'; pencilSilgi = false; }
    else { arac = 'silgi'; pencilSilgi = true; }
    cubukCiz();
    const i = $('#arac-bilgi'); if (i) { i.textContent = arac === 'silgi' ? 'Silgi' : 'Kalem'; clearTimeout(i._t); i._t = setTimeout(() => { i.textContent = ''; }, 1600); }
  };
  addEventListener('pencilCiftDokun', pencilCb);
  const kalemBitti = (e) => {   // çift dokunuş silgisinden, kalem kalkınca kaleme dön
    if (!pencilSilgi || (e && e.pointerType && e.pointerType !== 'pen')) return;
    arac = 'kalem'; pencilSilgi = false; cubukCiz();
  };
  addEventListener('pointerup', kalemBitti);
  addEventListener('pointercancel', kalemBitti);
  const bilgi = el('span', { id: 'arac-bilgi', class: 'arac-bilgi' });
  document.body.append(bilgi);

  /* Dışarı çıkarken taslak varsa sor */
  function sor() {
    return new Promise((coz) => {
      const arka = el('div', { class: 'soru-arka' });
      arka.append(el('div', { class: 'soru-kut' },
        el('h2', {}, 'Çizimler kaydedilsin mi?'),
        el('p', {}, 'Kaydetmezsen bu oturumdaki çizimler silinir, part eski hâline döner.'),
        el('div', { class: 'soru-dug' },
          el('button', { class: 'ciz', onclick: () => { arka.remove(); coz('sil'); } }, 'Vazgeç, sil'),
          el('button', { class: 'kaydet-d', onclick: () => { arka.remove(); coz('kaydet'); } }, 'Kaydet'))));
      document.body.append(arka);
    });
  }
  return {
    async cikisKontrol() {
      if (!taslakVar()) return true;
      const c = await sor();
      if (c === 'kaydet') kaydet(); else vazgec();
      return true;
    },
    kaldir() {
      // yuzey (main.sayfa) sayfalar arasında AYNI öğe kalıyor: dinleyicileri kaldırmazsak eski sayfanın
      // kalem katmanı canlı kalır ve yeni çizgileri önceki sayfaların kaydına da yazar (2026-10-30 denetimi).
      yuzey.removeEventListener('pointerdown', basla);
      yuzey.removeEventListener('pointermove', hareket);
      yuzey.removeEventListener('pointerup', bitis);
      yuzey.removeEventListener('pointercancel', iptal);
      yuzey.removeEventListener('touchstart', kalemTouch, { passive: false });
      yuzey.removeEventListener('touchmove', kalemTouch, { passive: false });
      svg.remove(); zemin.remove();
      ro.disconnect(); removeEventListener('orientationchange', don); removeEventListener('pencilCiftDokun', pencilCb);
      removeEventListener('pointerup', kalemBitti); removeEventListener('pointercancel', kalemBitti);
      cubuk.remove(); bilgi.remove();
      if (Esle.yenile === yenileFn) Esle.yenile = null;
    },
  };
}

/* ---------- Başlat ---------- */
Esle.baslat();
yonlendir();
