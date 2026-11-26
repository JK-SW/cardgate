# CardGate – návod

CardGate připojí váš Mac ke vzdálené ploše pracovního počítače přes bránu (RD Gateway),
která vyžaduje přihlášení čipovou kartou nebo tokenem.
Tento návod otevřete i z aplikace: **Nápověda → Návod k CardGate**.

## Co budete potřebovat

- Mac s procesorem Apple (M1 a novější), macOS 15 nebo novější.
- Čipovou kartu se čtečkou nebo USB token.
- Software ke kartě s modulem PKCS#11, např. **ProID+** pro macOS.
- Adresu svého pracovního počítače a brány (dostanete od IT oddělení, případně jako soubor `.rdp`).

## Instalace

1. Stáhněte `CardGate-X.Y.Z.zip` ze stránky Releases a rozbalte ho (dvojklik).
2. Přetáhněte **CardGate** do složky **Aplikace**.
3. Při prvním spuštění macOS aplikaci zablokuje, protože není notarizovaná u Applu.
   Klikněte na **Hotovo**, otevřete **Nastavení systému → Soukromí a zabezpečení**, sjeďte dolů
   k hlášce o aplikaci CardGate a klikněte na **Přesto otevřít**. Potvrďte heslem a znovu **Otevřít**.
   Tento krok je potřeba jen jednou.

## Nastavení připojení

1. Spusťte CardGate a klikněte na **Nastavit připojení**
   (nebo **Importovat soubor .rdp…**, pokud vám ho IT oddělení poslalo). Připojujte se jen k adresám
   od IT oddělení: po dobu připojení může vzdálený počítač používat vaši kartu.
2. Vyplňte **Počítač** (např. `pc01.example.com`) a **Bránu**.
3. Volitelně zvolte zobrazení (výchozí je celá obrazovka, nebo okno), u celé obrazovky s více displeji také
   displej (**Hlavní displej** = ten s řádkem nabídek; když zvolený displej není připojený, otevře se na hlavním),
   počáteční velikost okna
   (**Automaticky** = 80 % obrazovky), měřítko (velikost textu a aplikací ve Windows; **Automaticky** = 200 %
   na displeji Retina, jinak 100 %), schránku, zvuk a směr posouvání myší. Klikněte na **Uložit**.

Připojení můžete mít i více: jsou v seznamu vlevo. Každé upravíte tlačítkem vedle jeho názvu, nové
přidáte tlačítkem **Nové připojení…** pod seznamem.

Méně používané volby jsou v části **Pokročilé** (otevře se kliknutím; certifikát karty, zabezpečení,
přihlášení do Windows a modul karty). **Zabezpečení** nechte na **Automaticky**: CardGate použije
nejsilnější zabezpečení, které počítač přijme (NLA, TLS, nebo Zabezpečení RDP), zapamatuje si ho a zhruba po
měsíci zkusí, zda počítač nepřijme silnější. V závorce je vidět, co se právě používá, např. **Automaticky
(NLA)**. NLA, TLS nebo Zabezpečení RDP volte jen na pokyn IT oddělení.

**Přihlášení do Windows**: výchozí **Kartou** přihlásí do Windows kartou (s NLA bez dalšího PINu). Pokud
Windows na počítači přihlášení kartou nepřijme (např. před přihlašovací obrazovkou ukáže chybu), zvolte
**Jménem a heslem**: k bráně vás karta přihlásí dál, Windows ale ukáže svou přihlašovací obrazovku a zeptá
se na heslo. Pokud Windows nabídne PIN karty, zvolte **Možnosti přihlášení** a heslo; příště obvykle nabídne
rovnou heslo. Karta zůstane ve Windows k dispozici (např. pro podpisy).

<img src="images/cs/welcome.png" width="560" alt="Uvítací obrazovka CardGate">
<img src="images/cs/connection-settings.png" width="560" alt="Nastavení připojení">

## Připojení

1. Vložte kartu nebo token.
2. Klikněte na **Připojit**. Dokud se plocha neotevře, můžete pokus ukončit tlačítkem **Zrušit**.
3. Zadejte **PIN** ke kartě. Pozor: po několika chybných pokusech se karta zablokuje.
   S NLA vás tento PIN přihlásí i do Windows. Bez NLA si Windows na přihlašovací obrazovce řekne o PIN
   ještě jednou (pokud nabídne heslo, zvolte přihlášení čipovou kartou).
4. Otevře se okno se vzdálenou plochou a okno CardGate se schová. V Docku je stále jen ikona
   CardGate: kliknutím na ni (nebo přes ⌘Tab) se vrátíte ke vzdálené ploše. Zelené tlačítko
   v záhlaví okna přepíná celou obrazovku. Pravým tlačítkem na ikoně v Docku zvolíte **Odpojit**.
   Vpravo v záhlaví je měřítko vzdálené plochy (např. 150 %): lupami ho zmenšíte nebo zvětšíte,
   kliknutím na číslo vyberete ze seznamu (i měřítko při připojení). Windows změní velikost textu
   a aplikací hned, bez odpojení; při dalším připojení platí zase měřítko z nastavení připojení.
   Tlačítko vedle otevře log připojení. Na celé obrazovce se záhlaví ukáže po najetí myší k hornímu okraji.
5. Po odpojení nebo zavření vzdálené plochy se okno CardGate zase zobrazí.

V **CardGate → Nastavení…** (⌘,) jsou tři volby, všechny výchozí zapnuté:
- **Udržovat připojení a po výpadku ho obnovit** – při krátkém výpadku sítě se CardGate připojí
  znovu sám, bez nového PINu. Plocha mezitím ukazuje poslední obraz a nereaguje; nad ní je okénko
  „Připojení se přerušilo. Obnovuji…“ s tlačítkem Odpojit. Po 2,5–5 minutách to vzdá. Karta musí být
  ve čtečce: bez ní se obnova nepovede (CardGate ukáže, že na kartě nenašel certifikát).
- **Během připojení nenechat Mac usnout** – Mac při nečinnosti neusne a připojení vydrží; displej může
  zhasnout podle nastavení macOS. Zavření víka nebo ruční uspání Mac uspí i tak.
- **Ptát se před odpojením** – zavření okna vzdálené plochy (nebo ⌘Q v něm) se nejdřív zeptá.
  **Odpojit** v CardGate nebo v Docku se neptá.

<img src="images/cs/main-window.png" width="560" alt="Hlavní okno s připravenou kartou">
<img src="images/cs/pin.png" width="290" alt="Okno pro zadání PINu">

Klávesové zkratky klienta (celá obrazovka, odpojení…) se používají s klávesami
**levý Control + levý Option + levý Shift** a písmenem (např. **Enter** = celá obrazovka).

## Aktualizace

Při druhém spuštění se CardGate zeptá, zda má nové verze hledat automaticky (jednou denně).
Volbu změníte v **CardGate → Nastavení…** (⌘,).
Ručně: menu **CardGate → Zkontrolovat aktualizace…**. Nová verze se nainstaluje jedním kliknutím;
aplikace přijme jen aktualizaci podepsanou klíčem autora. Kontrola jen stáhne seznam verzí
z GitHubu a nic o vás neodesílá.

<img src="images/cs/settings.png" width="420" alt="Nastavení aplikace">

## Bezpečnost

- PIN se nikde neukládá. Dialog pro PIN přijme jen PIN v délce, jakou karta povoluje, a upozorní,
  když už byl dříve zadán chybný PIN nebo jde o poslední pokus. Po dobu připojení zůstává PIN jen
  v paměti klienta (pro přihlášení do Windows a obnovení po výpadku); PIN, který karta odmítne,
  se už nikdy znovu nepoužije.
- Po dobu připojení je karta zpřístupněna vzdálenému počítači (kvůli přihlášení do Windows).
  Programy ve vzdálené relaci ji mohou používat stejně, jako by byla vložená přímo v něm.
  Po skončení práce se odpojte, případně kartu vytáhněte.
- Aplikace se připojí jen k bráně s důvěryhodným certifikátem. Pokud ohlásí nedůvěryhodný
  certifikát, nepokračujte a kontaktujte IT oddělení.
- Certifikát brány musí vydat veřejně důvěryhodná certifikační autorita. Certifikát vnitřní
  (firemní) autority aplikace nepřijme, i když mu Mac důvěřuje (např. v Klíčence nebo přes
  správu zařízení) – ohlásí, že certifikát brány není veřejně důvěryhodný.
- Spojení mezi bránou a počítačem je u NLA a TLS šifrované protokolem TLS. Zabezpečení RDP používá
  starší šifru RC4; automatika ho použije jen u počítače, který nic jiného nepřijme. S NLA navíc
  počítač ověří vaši kartu ještě před zobrazením přihlašovací obrazovky.
- Certifikát počítače si CardGate zapamatuje při prvním připojení. Když se později změní, připojení
  zastaví (**Certifikát počítače se změnil**). Tlačítkem **Důvěřovat novému certifikátu** ho přijměte,
  jen když správce počítače potvrdí, že byl obnoven, a jeho otisk SHA-256 souhlasí s otiskem v hlášce.
  S NLA přijme CardGate obnovený certifikát sám: počítač při přihlášení kartou (Kerberos) prokáže, že je
  to stále on, ještě než mu CardGate pošle vaše přihlašovací údaje.
- Automatické zabezpečení nikdy potichu nepřejde na slabší. Když počítač dřív přijímal TLS nebo NLA
  a teď nabízí jen slabší zabezpečení, CardGate se nepřipojí, dokud nekliknete na **Připojit se
  slabším zabezpečením**; bez potvrzení správce to nedělejte.

## Když něco nefunguje

| Hlášení | Co dělat |
|---|---|
| Na kartě nebyl nalezen certifikát | Vytáhněte kartu/token, znovu zasuňte a zkuste znovu. |
| Software pro čipovou kartu nebyl nalezen | Nainstalujte software ke kartě (např. ProID+). |
| Chybný PIN | Zadejte správný PIN – opakované chyby kartu zablokují. |
| Karta přihlášení odmítla | PIN mohl být chybný, nebo selhala karta či čtečka. Vytáhněte kartu, vložte ji znovu a připojte se. Opakované chybné PINy kartu zablokují. |
| Typ klíče na kartě není podporován | K bráně se lze přihlásit jen kartou s klíčem RSA. Kontaktujte IT oddělení. |
| Bránu nelze kontaktovat | Zkontrolujte připojení k internetu a adresu brány. |
| Připojení nemá zadanou bránu | CardGate se připojuje jen přes bránu. Klikněte na **Upravit připojení** a doplňte adresu brány. |
| Spojení bylo přerušeno | Síť vypadla a obnovení se nepodařilo (nebo je v Nastavení vypnuté). Zkontrolujte připojení k internetu a připojte se znovu. |
| Modul čipové karty není od ověřeného vydavatele | Modul ke kartě nepochází od ověřeného výrobce. Použijte ho (**Použít tento modul…**), jen pokud víte, odkud je (např. od IT oddělení). |
| Modul čipové karty nastavený pro toto připojení nebyl nalezen | Opravte cestu v **Upravit připojení** (část Pokročilé), nebo ji nechte prázdnou. |
| Počítač vyžaduje silnější zabezpečení připojení | V nastavení připojení zvolte **Zabezpečení: Automaticky**. Pokud už je zvolené, počítač vyžaduje NLA, které se nepodařilo použít – postupujte podle hlášky, případně kontaktujte IT oddělení. |
| Počítač nabízí jen slabší zabezpečení připojení | Pokud to správce počítače změnil záměrně, klikněte na **Připojit se slabším zabezpečením**. Jinak se nepřipojujte a kontaktujte IT oddělení. |
| Certifikát počítače se změnil | Novému certifikátu důvěřujte, jen když správce potvrdí jeho obnovení a otisk (viz Bezpečnost). |
| Váš účet se k tomuto počítači nesmí připojit | Požádejte správce počítače o přidání do skupiny Uživatelé vzdálené plochy. |
| Čas na Macu se liší od času v doméně | Zkontrolujte datum a čas v Nastavení systému → Obecné → Datum a čas a připojte se znovu. |
| Doména tento počítač nezná | V nastavení připojení zadejte celé jméno počítače s doménou (např. `pc01.example.com`). |
| Brána nepovoluje připojení k tomuto počítači | Zkontrolujte celé jméno počítače; pokud je správné, kontaktujte IT oddělení. |
| Brána je dočasně nedostupná | Brána je přetížená nebo v údržbě. Zkuste to za chvíli znovu. |
| Váš účet je zakázaný / zablokovaný, Platnost vašeho účtu skončila | Kontaktujte IT oddělení. |
| Počítač nemá licenci pro vzdálenou plochu | Kontaktujte IT oddělení. |
| Program vzdálené plochy neočekávaně skončil | Připojte se znovu. Pokud se to opakuje, nahlaste chybu v Issues a přiložte archiv z **Uložit log…** (viz níže). |
| Windows při přihlášení kartou ukáže chybu (např. „Hash generation … is not enabled on the server“) | Windows na tomto počítači přihlášení kartou nepřijímá. V nastavení připojení zvolte **Přihlášení do Windows: Jménem a heslem**. |
| Přihlášení k počítači kartou se nepovedlo | Připojte se znovu, CardGate se pak připojí bez NLA. Pokud počítač NLA vyžaduje, kontaktujte IT oddělení (brána potřebuje KDC proxy). |
| U tohoto připojení nelze použít NLA | Zadejte celé jméno počítače s doménou (např. `pc01.example.com`) a zkontrolujte připojení k internetu, případně k síti organizace (kvůli stažení certifikační autority karty). |

Podrobnosti najdete v menu **Okno → Log připojení**. Ve výchozím zobrazení **Důležité** ukazuje
srozumitelně průběh připojení: varování oranžově (např. slabší zabezpečení RDP, výpadek sítě nebo
vyjmutí karty ze čtečky), chyby červeně. V zobrazení **Podrobnosti** uvidíte všechny řádky logu;
známé neškodné zprávy jsou šedé.
Tlačítko **Kopírovat log** zkopíruje to, co okno právě ukazuje (důležité zprávy, nebo celý log).
**Uložit log…** uloží archiv ZIP se třemi soubory – důležité zprávy (`important.txt`), celý log se všemi
podrobnostmi (`connection.log`) a anonymní diagnostické údaje (`diagnostics.txt`: verze aplikace a macOS,
model Macu, displeje, software a typ karty, nastavení připojení bez adres) – abyste ho mohli poslat IT
oddělení. Jména počítače a brány, název připojení a účet Windows jsou v archivu nahrazené `***`, takže ho
můžete poslat bez úprav. Log nikdy neobsahuje PIN.
Logy posledních pěti připojení jsou také ve složce `~/Library/Logs/CardGate`.

Chybu aplikace nebo námět nahlaste v [Issues](https://github.com/JK-SW/cardgate/issues) a přiložte archiv
z **Uložit log…** (zkopírovaný log jména počítače a brány obsahuje). Bezpečnostní problém hlaste neveřejně
([Report a vulnerability](https://github.com/JK-SW/cardgate/security/advisories/new)).

## Pro správce IT

Po delším používání (20 úspěšných připojení, nejdřív za týden) aplikace jednou nenápadně nabídne
podporu autora; po zavření se už nikdy neukáže. Nabídku lze plošně vypnout:

```sh
defaults write io.github.jk-sw.cardgate DonationPromptDisabled -bool true
```

(nebo konfiguračním profilem pro doménu `io.github.jk-sw.cardgate`).

**Zabezpečení připojení k počítači.** CardGate umí NLA, TLS i Zabezpečení RDP; automatika použije
nejsilnější, které počítač přijme. Doporučujeme NLA (jeden PIN, počítač ověří kartu před přihlášením).
NLA s kartou potřebuje:
- na bráně RD Gateway zveřejněnou službu KDC proxy (`https://<brána>/KdcProxy`), přes kterou CardGate
  ověří kartu u řadiče domény (Kerberos PKINIT),
- jméno počítače v DNS doméně Active Directory: realm je přípona jména velkými písmeny
  (`pc01.example.com` → `EXAMPLE.COM`); u počítače v jiné DNS zóně NLA selže a CardGate se připojí bez něj,
- certifikáty řadičů domény vydané pod stejnou kořenovou certifikační autoritou jako certifikáty karet
  (CardGate ji stáhne podle adres v certifikátu karty a uloží),
- uživatele s oprávněním přihlásit se přes Vzdálenou plochu,
- čas na Macu shodný s časem v doméně (Kerberos; jinak CardGate ohlásí rozdíl času a připojí se bez NLA).

Na počítači se zabezpečení nastavuje zásadami skupiny v **Konfigurace počítače → Šablony pro správu →
Součásti systému Windows → Služba Vzdálená plocha → Hostitel relace vzdálené plochy → Zabezpečení**:
„Require use of specific security layer for remote (RDP) connections“ = **SSL** a „Require user
authentication for remote connections by using Network Level Authentication“ = **Povoleno**.
