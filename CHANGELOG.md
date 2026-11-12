# Změny

Všechny podstatné změny aplikace. Formát vychází z [Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verze se číslují podle [Semantic Versioning](https://semver.org/lang/cs/). Aktuální verze je v souboru `VERSION`.

## [Unreleased]

## [0.5.0] - 2026-11-12

Měřítko vzdálené plochy v nastavení, správné rozložení a měřítko na více monitorech, návrat
minimalizovaného okna a předvyplněné jméno ve tvaru UPN při přihlášení heslem.

### Přidáno
- Měřítko vzdálené plochy v nastavení připojení (velikost textu a aplikací ve Windows): automaticky
  podle displeje, nebo pevně 100–300 %. Měřítko platí už na přihlašovací obrazovce Windows.

### Opraveno
- Připojení nastavené rovnou na celou obrazovku mělo na displeji Retina vše drobné (měřítko 100 %).
  Teď dostane stejné měřítko jako okno, a po přepnutí z celé obrazovky do okna se plocha přizpůsobí oknu.
- Připojení na všech monitorech se přizpůsobí, když se během něj monitor připojí, odpojí nebo přesune.
- Celá obrazovka na všech monitorech: Windows dostane každý monitor zvlášť. Dřív dostal jeden obdélník
  přes všechny, takže u monitorů různé velikosti (např. jeden na výšku) byla část plochy mimo obraz.
- Minimalizované okno připojení vrátí kliknutí na ikonu CardGate v Docku nebo přepnutí přes ⌘Tab.
- Po přepnutí z karty na jméno a heslo na přihlašovací obrazovce Windows je předvyplněné jméno
  ve tvaru UPN (jmeno@domena.example.com) z certifikátu na kartě, ne neplatné domena.example.com\jmeno.

## [0.4.2] - 2026-11-11

Srozumitelnější hlášky při konci a selhání připojení, kontrola dostupnosti brány, spolehlivější
zadávání PINu.

### Přidáno
- Přerušené spojení (výpadek sítě, brána) se hlásí jako „Spojení bylo přerušeno“; dřív se okno
  vzdálené plochy jen zavřelo. Vlastní hlášky má i převzetí relace jiným připojením, odpojení
  kvůli nečinnosti a odpojení správcem nebo počítačem; neznámý důvod od Windows se zobrazí jako
  chyba s kódem. Zavření okna, Odpojit a odhlášení ve Windows dál končí bez hlášky.
- Aplikace zkouší, zda je port brány dostupný (při spuštění, změně sítě, přepnutí připojení,
  po neúspěšném připojení a při návratu do aplikace nejvýš jednou za 5 minut), a ještě před
  připojením upozorní na chybějící internet, chybnou adresu nebo firewall. Jde jen o otevření
  a zavření spojení, bránu to nezatěžuje.

### Změněno
- Okno pro PIN zahodí jen znaky napsané v prvních 0,3 s po zobrazení (psaní určené jiné aplikaci)
  a to, co na ně plynule navazuje, dřív 0,7 s – při rychlém psaní se tak ztrácely první číslice
  a mohl odejít neúplný (a tedy chybný) PIN. Enter je dál v prvním okamžiku ignorován.
- Hned po vložení karty do čtečky se zobrazí „Načítám kartu…“; dřív se několik sekund, než
  software ke kartě načetl certifikáty, nedělo nic.

### Opraveno
- Rychle napsaný a hned potvrzený PIN občas ukončil připojování, jako by bylo zrušeno: okno se
  zavíralo ve chvíli, kdy software karty ještě četl počet pokusů, a jeho ovladač spadl. Okno se teď
  ukončí bez čekání na něj.
- Počítač, který vyžaduje jiné zabezpečení připojení (TLS nebo NLA), se hlásí srozumitelně
  a nezaměňuje se s nedostupným počítačem.
- Neexistující nebo nedostupný počítač za bránou (překlep v názvu, vypnutý počítač) se hlásí jako
  „Počítač není dostupný“ s radou zkontrolovat název, místo obecného „Připojení se nezdařilo“.

## [0.4.1] - 2026-11-11

Návod přímo z aplikace a se snímky obrazovky, drobné opravy.

### Přidáno
- Nabídka Nápověda → Návod k CardGate otevře návod na GitHubu v jazyce aplikace.
- Návody (cs, sk, en) obsahují snímky obrazovky.

### Opraveno
- Po změně modulu PKCS#11 v nastavení připojení nebo po přepnutí na jiné připojení se stav karty
  hned přepočítá; dřív mohl do další aktivace aplikace ukazovat „Karta připravena“ podle
  předchozího modulu.
- Okno Klávesové zkratky už nemá zkratku ⌘⇧/, kterou macOS používá pro hledání v nabídce
  Nápověda (nikdy nefungovala); okno je dál v nabídce Nápověda.
- Okno Nastavení zobrazovalo zbytečný posuvník.

### Změněno
- Automatické testy uživatelského rozhraní (bez karty a PINu) běží s každou změnou.

## [0.4.0] - 2026-11-10

Jedna ikona v Docku pro aplikaci i vzdálenou plochu, nastavení aktualizací.

### Přidáno
- Okno **CardGate → Nastavení…** s volbou automatického vyhledávání aktualizací.

### Změněno
- Vzdálená plocha už nemá v Docku vlastní ikonu („exec“) ani název „sdl-freerdp“: v Docku
  a v přepínání ⌘Tab je jen CardGate a kliknutím na něj se vrátíte ke vzdálené ploše. Vždy je
  vidět jedno okno: během připojení vzdálená plocha, po odpojení zase CardGate. Pravé tlačítko
  na ikoně v Docku nabízí Odpojit.
- Okno vzdálené plochy se jmenuje podle připojení („Kancelář – CardGate“).

### Opraveno
- S více připojeními se tlačítka v liště okna schovala do nabídky „»“; přepínač připojení teď
  nahradí název okna a dlouhý název připojení se zkrátí.

## [0.3.0] - 2026-11-10

První veřejná verze: aktualizace jedním kliknutím, oprava přihlášení kartou na Macu s více čtečkami,
dokumentace v češtině.

### Přidáno
- Aktualizace jedním kliknutím (Sparkle): aplikace se při druhém spuštění zeptá, zda hledat nové
  verze automaticky; ručně v menu CardGate → Zkontrolovat aktualizace…. Aktualizace jsou podepsané
  klíčem autora a jiné se nenainstalují.
- Okno O aplikaci odkazuje na zdrojový kód a na možnost podpořit autora (Ko-fi).
- Po delším používání (20 úspěšných připojení, nejdřív za týden) aplikace jednou nenápadně nabídne
  podporu autora; po zavření se už neukáže. Správci ji mohou vypnout (viz návod).

### Opraveno
- Přihlášení kartou ve Windows nefungovalo na Macu s více čtečkami karet (např. se čtečkou
  v klávesnici): do vzdáleného počítače se dostala jen první čtečka. Převod textu ve FreeRDP
  na macOS seznam čteček usekl za prvním názvem.
- Když nejde určit čtečku s kartou, přesměrují se všechny čtečky místo žádné.

### Změněno
- README, změny a poznámky k vydání jsou v češtině (README pro vývojáře v angličtině).

## [0.2.1] - 2026-11-10

Opravy z testování na dalším Macu.

### Opraveno
- Zrušení okna pro PIN (nebo vypršení času) ukončí pokus o připojení; místo něj se už neobjeví
  vlastní okno klienta pro přihlašovací údaje.
- S více čtečkami karet (např. čtečka v klávesnici) chtělo přihlášení do Windows vložit kartu.
  Do vzdáleného počítače se teď přesměruje jen čtečka s kartou.

### Změněno
- Záznam připojení obsahuje operace s přesměrovanou kartou a jejich výsledky (nikdy data posílaná
  kartě) pro řešení potíží s přihlášením.
- Uchovávají se záznamy posledních pěti připojení (`last-session.log`, `last-session.1.log`, …),
  takže neúspěšný pokus jde prohlédnout i po dalším připojení.

## [0.2.0] - 2026-11-10

Zabezpečení po auditu, karty s více certifikáty, rychlejší kontrola karty.

### Zabezpečení
- PIN, který karta odmítla, se jí v rámci stejného připojení už nikdy znovu nenabídne (opětovné
  připojení, změna protokolu) a smaže se z paměti.
- Okno pro PIN v prvním okamžiku po zobrazení ignoruje psaní (určené jiné aplikaci), odešle jen PIN
  délky, kterou karta přijímá, a zobrazí varování karty: dříve zadaný chybný PIN, poslední pokus,
  zablokovaná karta.
- Certifikát brány se před spuštěním klienta ověří systémem macOS (klíčenka, odvolání); přihlášení
  kartou navíc vyžaduje, aby brána uvnitř tunelu předložila stejný certifikát.
- Načítají se jen platně podepsané moduly PKCS#11.
- Soubory ke stažení mají kontrolní součty SHA-256; akce CI jsou připnuté na konkrétní commity.

### Přidáno
- Karty s více certifikáty: prošlé a ještě neplatné certifikáty se ignorují (patch FreeRDP),
  automaticky se použije nejnovější platný přihlašovací certifikát a v nastavení připojení jde
  zvolit konkrétní; okno ukazuje datum konce platnosti a varuje, když certifikát vypršel.
- Upozornění v hlavním okně, když nejnovějšímu přihlašovacímu certifikátu zbývá méně než 14 dní.
- Okno Klávesové zkratky (menu Nápověda) s popisem zkratek vzdálené plochy.
- Adresy IPv6 (v hranatých závorkách) pro počítač i bránu.
- Srozumitelné hlášky, když PIN nebyl zadán včas (okno to po 2 minutách vzdá) nebo má karta více
  přihlašovacích certifikátů; zrušení okna pro PIN jednoduše ukončí pokus.
- Ukončení CardGate při otevřeném připojení se nejdřív zeptá a pak odpojí.

### Změněno
- Kontrola karty trvá asi 2–3 s místo 6 s a neblokuje tlačítko Připojit; kliknutí během kontroly
  na ni počká.

### Opraveno
- Okno pro PIN se zavře, když jeho připojení skončí.
- Připojit je aktivní až po první kontrole nově vložené karty.

## [0.1.0] - 2026-11-09

První verze k testování. Apple Silicon, macOS 15 nebo novější; vyžaduje software ke kartě s modulem
PKCS#11 (např. ProID+). Aplikace není notarizovaná – postup při prvním spuštění je v návodu.

### Přidáno
- Připojení k počítači s Windows přes RD Gateway s přihlášením čipovou kartou (schéma
  `HTTP_EXTENDED_AUTH_SC` klienta Microsoftu), s přesměrováním karty do relace kvůli přihlášení
  do Windows.
- Průvodce prvním spuštěním, nastavení připojení (počítač, brána, okno nebo celá obrazovka,
  počáteční velikost okna, schránka, zvuk, směr posouvání, modul PKCS#11), více připojení a import
  souborů `.rdp`.
- Rozpoznání karty: ukazuje držitele a Připojit povolí jen s použitelnou kartou; vložení a vytažení
  pozná hned a kartu, kterou software ke kartě ztratil (např. po spánku), ohlásí s žádostí o nové
  vložení.
- Vlastní okno pro PIN na monitoru, kde jste klikli na Připojit; PIN se nikdy neukládá, nezapisuje
  do záznamu ani nepředává na příkazové řádce a chybný PIN se nikdy neopakuje.
- Průběžný stav připojení a srozumitelné chybové hlášky s doporučením; okno se záznamem připojení
  a soubor `~/Library/Logs/CardGate/last-session.log` pro podporu.
- Certifikát brány musí být důvěryhodný podle systémových certifikačních autorit.
- Bezpečné klávesové zkratky klienta (levý Control + levý Option + levý Shift), takže psaní nemůže
  odpojit.
- Velikost okna v bodech obrazovky s ostrým vykreslením na Retina; automatická velikost je 80 %
  obrazovky.
- Okno O aplikaci s autorem a licencemi třetích stran.
- Uživatelské rozhraní a návod v angličtině, češtině a slovenštině.
- Samostatná aplikace: FreeRDP 3.33.0 s úpravami CardGate, OpenSSL, SDL, SDL_ttf, FreeType a cJSON
  sestavené z připnutých zdrojů s ověřeným kontrolním součtem.
