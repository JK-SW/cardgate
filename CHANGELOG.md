# Změny

Všechny podstatné změny aplikace. Formát vychází z [Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verze se číslují podle [Semantic Versioning](https://semver.org/lang/cs/). Aktuální verze je v souboru `VERSION`.

## [Unreleased]

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
