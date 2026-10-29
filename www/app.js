/* Fizyoloji defteri — yerel uygulama. Sunucu yok; veri bu cihazda (Depo) tutulur.
   Depo, ileride senkron katmanı eklenebilsin diye tek yerde toplandı. */
'use strict';

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

/* ---------- İçerik: sunucudan çek, cihazda (IndexedDB) sakla, internetsiz de çalış ---------- */
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
  async ag(yol, ms = 4000) {
    if (navigator.onLine === false) throw new Error('çevrimdışı');
    const k = new AbortController(); const z = setTimeout(() => k.abort(), ms);
    try {
      const r = await fetch(sunucuUrl('/icerik/' + yol), { signal: k.signal });
      if (r.status === 401) throw Object.assign(new Error('yetkisiz'), { yetkisiz: true });
      if (!r.ok) throw new Error('sunucu ' + r.status);
      return r;
    } finally { clearTimeout(z); }
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

/* ---------- Yönlendirme ---------- */
let aktifTemizle = null;
async function yonlendir() {
  if (aktifTemizle) { aktifTemizle(); aktifTemizle = null; }
  const [, ekran, id] = location.hash.split('/');
  window.scrollTo(0, 0);
  if (!Ayar.anahtar) return ayarEkrani();
  try {
    if (ekran === 'ayar') return ayarEkrani();
    if (ekran === 'part' && id) await partEkrani(id);
    else await anaEkran();
  } catch (e) {
    if (e.yetkisiz) return ayarEkrani('Anahtar kabul edilmedi.');
    uygulama.replaceChildren(el('div', { class: 'ana' },
      temaDugmesi(),
      el('h1', {}, 'Açılamadı'),
      el('p', { class: 'alt' }, 'İçerik yüklenemedi. İlk açılışta internet gerekir.'),
      el('button', { class: 'devam', onclick: () => yonlendir() }, el('span', {}, 'Tekrar dene'))));
    console.error(e);
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
    Ayar.anahtar ? el('button', { class: 'ikincil', onclick: () => { location.hash = '#/'; } }, 'Geri') : null);
  uygulama.replaceChildren(kok);
}

/* ---------- Ana ekran: ders > bölüm > part ---------- */
async function anaEkran() {
  const plan = await json('icerik/plan.json');
  const ilerleme = Depo.ilerleme();
  const tum = plan.dersler.flatMap((d) => d.bolumler.flatMap((b) => b.partlar.map((p) => ({ ...p, bolum: b, ders: d }))));
  const son = tum.filter((p) => ilerleme[p.id] && ilerleme[p.id].durum !== 'bitti')
    .sort((a, b) => (ilerleme[b.id].guncelleme || 0) - (ilerleme[a.id].guncelleme || 0))[0];
  const siradaki = son || tum.find((p) => p.hazir && !(ilerleme[p.id] && ilerleme[p.id].durum === 'bitti'));

  const kok = el('div', { class: 'ana' }, temaDugmesi(),
    el('button', { class: 'dugme-yuvarlak ayar-dugme', 'aria-label': 'Ayarlar', onclick: () => { location.hash = '#/ayar'; }, html: ikon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>', 20) }),
    el('h1', {}, 'Antrenör defteri'));

  if (siradaki && siradaki.hazir) {
    const yarim = son && son.id === siradaki.id;
    kok.append(el('button', { class: 'devam', onclick: () => (location.hash = '#/part/' + siradaki.id) },
      el('span', {}, yarim ? 'Kaldığın yerden devam' : 'Başla',
        el('small', {}, `${siradaki.ders.baslik}, Bölüm ${siradaki.bolum.no}, Part ${siradaki.no}`)),
      el('span', { html: ikon(IKON.sag, 26) })));
  }

  for (const ders of plan.dersler) {
    for (const bolum of ders.bolumler) {
      const bitenler = bolum.partlar.filter((p) => (ilerleme[p.id] || {}).durum === 'bitti').length;
      kok.append(el('div', { class: 'bolum' },
        el('h2', {}, `${ders.baslik}, Bölüm ${bolum.no}: ${bolum.baslik}`),
        el('span', {}, `${bitenler} / ${bolum.partlar.length}`)));
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
    }
  }
  kok.append(el('p', { class: 'sonra' }, 'Sonraki bölümler hazır oldukça eklenecek.'));
  uygulama.replaceChildren(kok);
  document.title = 'Antrenör defteri';
}

/* ---------- Part ekranı: her bölüm ayrı sayfa ---------- */
async function partEkrani(id) {
  const part = await json(`icerik/${id}.json`);
  const bolumler = part.bolumler, N = bolumler.length;
  const kayit = Depo.ilerleme()[id] || {};
  let sayfa = Math.min(Math.max(kayit.sayfa || 0, 0), N - 1);
  const ziyaret = new Set(kayit.ziyaret || [sayfa]);
  const genis = matchMedia('(min-width: 62rem)');
  let kalem = null;

  const ilerlemeCubuk = el('div', { class: 'ilerleme', 'aria-hidden': 'true' }, el('i'));
  const ust = el('header', { class: 'ust' },
    el('button', { class: 'geri', onclick: () => cikis() }, el('span', { html: ikon(IKON.sol, 20) }), 'Partlar'),
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
    sayfaKutu.replaceChildren(
      el('p', { class: 'no' }, `${sayfa + 1} / ${N}`), metin,
      el('div', { class: 'sayfalama' }, geri, ileri));
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
    kalem = kalemKatmani(`${id}#${sayfa}`, metin);
  }
  async function cikis() {
    if (kalem && !(await kalem.cikisKontrol())) return;
    location.hash = '#/';
  }
  kaydet(); sayfaCiz();
  aktifTemizle = () => { if (kalem) kalem.kaldir(); $('#buyutec').hidden = true; };
}

/* ---------- Kalem katmanı ---------- */
const RENKLER = {
  kalem: [['murekkep', 'var(--murekkep)'], ['ven', '#3b5bdb'], ['arter', '#e03131']],
  fosforlu: [['sari', '#f3d44a'], ['yesil', '#8fd694'], ['pembe', '#f4a6c0']],
};
const KALINLIK = { kalem: 2.2, fosforlu: 16 };

function kalemKatmani(partId, metin) {
  const VB = 1000; // x ekseni 0..1000 (sütun genişliği)
  let veri = Depo.cizim(partId);
  let arac = 'kalem';
  let renk = { kalem: 'murekkep', fosforlu: 'sari' };
  let aktifCizgi = null;
  const fareIle = location.search.includes('fare');

  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('class', 'cizim');
  svg.setAttribute('aria-hidden', 'true');
  metin.append(svg);
  const katman = document.createElementNS(SVG, 'g');
  svg.append(katman);

  function boyutla() {
    const w = metin.clientWidth || 1, h = metin.scrollHeight || 1;
    svg.setAttribute('viewBox', `0 0 ${VB} ${(h / w) * VB}`);
    svg.setAttribute('preserveAspectRatio', 'none');
    svg.style.height = h + 'px';
  }
  const ro = new ResizeObserver(boyutla); ro.observe(metin); boyutla();
  metin.querySelectorAll('img').forEach((i) => i.addEventListener('load', boyutla));

  const renkDeger = (ad) => (Object.values(RENKLER).flat().find((r) => r[0] === ad) || [0, 'currentColor'])[1];
  function yolMetni(noktalar) {
    if (noktalar.length === 1) { const [x, y] = noktalar[0]; return `M${x} ${y}l0.01 0`; }
    let d = `M${noktalar[0][0]} ${noktalar[0][1]}`;
    for (let i = 1; i < noktalar.length - 1; i++) {
      const [x, y] = noktalar[i], [nx, ny] = noktalar[i + 1];
      d += `Q${x} ${y} ${(x + nx) / 2} ${(y + ny) / 2}`;
    }
    const son = noktalar[noktalar.length - 1];
    return d + `L${son[0]} ${son[1]}`;
  }
  function yolEl(c) {
    const p = document.createElementNS(SVG, 'path');
    p.setAttribute('d', yolMetni(c.noktalar));
    p.setAttribute('class', c.arac === 'fosforlu' ? 'fosforlu' : 'kalem');
    p.style.stroke = renkDeger(c.renk);
    p.style.strokeWidth = c.kalinlik;
    p.dataset.id = c.id;
    return p;
  }
  function ciz() {
    katman.replaceChildren();
    const silinen = new Set(veri.silinen);
    // Fosforlu altta, kalem üstte
    const hepsi = [...veri.kaydedilen.filter((c) => !silinen.has(c.id)), ...veri.taslak];
    hepsi.filter((c) => c.arac === 'fosforlu').forEach((c) => katman.append(yolEl(c)));
    hepsi.filter((c) => c.arac !== 'fosforlu').forEach((c) => katman.append(yolEl(c)));
  }
  const taslakVar = () => veri.taslak.length > 0 || veri.silinen.length > 0;
  const kaydetAyar = () => Depo.cizimYaz(partId, veri);

  /* Araç çubuğu */
  const cubuk = el('div', { class: 'arac', role: 'toolbar', 'aria-label': 'Çizim araçları' });
  const kaydetBar = el('div', { class: 'arac', style: 'bottom:calc(env(safe-area-inset-bottom) + 5rem);gap:.6rem;padding:.55rem .8rem', hidden: true },
    el('span', { style: 'font:600 .95rem var(--yazi-arayuz);padding:0 .3rem' }, 'Çizimler kaydedilsin mi?'),
    el('button', { style: 'width:auto;border-radius:1rem;padding:0 1rem;font:700 .95rem var(--yazi-arayuz);border:1.5px solid var(--murekkep)', onclick: () => vazgec() }, 'Vazgeç'),
    el('button', { style: 'width:auto;border-radius:1rem;padding:0 1.1rem;font:700 .95rem var(--yazi-arayuz);background:var(--arter);color:#fff', onclick: () => kaydet() }, 'Kaydet'));
  function cubukCiz() {
    const dugmeler = [];
    for (const [ad, yazi, i] of [['kalem', 'Kalem', IKON.kalem], ['fosforlu', 'Fosforlu kalem', IKON.fosforlu], ['silgi', 'Silgi', IKON.silgi]]) {
      dugmeler.push(el('button', { 'aria-label': yazi, 'aria-pressed': String(arac === ad), html: ikon(i), onclick: () => { arac = ad; cubukCiz(); } }));
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
    cubuk.replaceChildren(...dugmeler);
    kaydetBar.hidden = !taslakVar();
  }
  document.body.append(kaydetBar, cubuk);
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
  const nokta = (e) => {
    const r = metin.getBoundingClientRect();
    return [Math.round(((e.clientX - r.left) / r.width) * VB * 10) / 10, Math.round(((e.clientY - r.top) / r.width) * VB * 10) / 10];
  };
  const cizebilir = (e) => e.pointerType === 'pen' || (fareIle && e.pointerType === 'mouse');
  function siliciGec(e) {
    const [x, y] = nokta(e);
    const silinen = new Set(veri.silinen);
    veri.taslak = veri.taslak.filter((c) => !c.noktalar.some(([px, py]) => Math.hypot(px - x, py - y) < 14));
    for (const c of veri.kaydedilen) {
      if (!silinen.has(c.id) && c.noktalar.some(([px, py]) => Math.hypot(px - x, py - y) < 14)) veri.silinen.push(c.id);
    }
    ciz();
  }
  function basla(e) {
    if (!cizebilir(e)) return;
    e.preventDefault();
    metin.setPointerCapture(e.pointerId);
    if (arac === 'silgi') { aktifCizgi = 'silgi'; siliciGec(e); return; }
    aktifCizgi = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), arac, renk: renk[arac], kalinlik: KALINLIK[arac], noktalar: [nokta(e)] };
    veri.taslak.push(aktifCizgi); ciz();
  }
  function hareket(e) {
    if (!aktifCizgi || !cizebilir(e)) return;
    e.preventDefault();
    const olaylar = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    if (aktifCizgi === 'silgi') { olaylar.forEach(siliciGec); return; }
    for (const o of olaylar.length ? olaylar : [e]) aktifCizgi.noktalar.push(nokta(o));
    ciz();
  }
  function bitis(e) {
    if (!aktifCizgi) return;
    aktifCizgi = null; kaydetAyar(); cubukCiz();
  }
  metin.addEventListener('pointerdown', basla);
  metin.addEventListener('pointermove', hareket);
  metin.addEventListener('pointerup', bitis);
  metin.addEventListener('pointercancel', bitis);
  // Kalem dokunuşları sayfayı kaydırmasın; parmak kaydırmaya devam etsin
  const kalemTouch = (e) => { const t = e.touches[0]; if (t && t.touchType === 'stylus') e.preventDefault(); };
  metin.addEventListener('touchstart', kalemTouch, { passive: false });
  metin.addEventListener('touchmove', kalemTouch, { passive: false });

  /* Dışarı çıkarken taslak varsa sor */
  function sor() {
    return new Promise((coz) => {
      const arka = el('div', { style: 'position:fixed;inset:0;z-index:60;background:rgba(8,16,22,.55);display:grid;place-items:center;padding:1.5rem' });
      const dugme = (yazi, deger, stil) => el('button', { style: `min-height:48px;border-radius:1rem;padding:0 1.2rem;font:700 1rem var(--yazi-arayuz);${stil}`, onclick: () => { arka.remove(); coz(deger); } }, yazi);
      arka.append(el('div', { style: 'background:var(--kemik);color:var(--murekkep);border-radius:1.2rem;padding:1.4rem;max-width:22rem;width:100%;font-family:var(--yazi-arayuz)' },
        el('h2', { style: 'font:700 1.25rem var(--yazi-baslik);margin:0 0 .5rem' }, 'Çizimler kaydedilsin mi?'),
        el('p', { style: 'margin:0 0 1.2rem;color:var(--soluk);line-height:1.45' }, 'Kaydetmezsen bu oturumdaki çizimler silinir, part eski hâline döner.'),
        el('div', { style: 'display:flex;gap:.6rem;justify-content:flex-end' },
          dugme('Vazgeç, sil', 'sil', 'border:1.5px solid var(--murekkep);background:none;color:inherit'),
          dugme('Kaydet', 'kaydet', 'border:0;background:var(--arter);color:#fff'))));
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
    kaldir() { ro.disconnect(); cubuk.remove(); kaydetBar.remove(); if (Esle.yenile === yenileFn) Esle.yenile = null; },
  };
}

/* ---------- Tema (ayarlardan bağımsız, sistemle uyumlu) ---------- */
Esle.baslat();
yonlendir();
