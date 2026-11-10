# CardGate – návod

CardGate připojí váš Mac ke vzdálené ploše pracovního počítače přes bránu (RD Gateway),
která vyžaduje přihlášení čipovou kartou nebo tokenem.

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
   Tento krok je potřeba jen jednou (a po každé aktualizaci).

## Nastavení připojení

1. Spusťte CardGate a klikněte na **Nastavit připojení**
   (nebo **Importovat soubor .rdp…**, pokud vám ho IT oddělení poslalo).
2. Vyplňte **Počítač** (např. `pc01.example.com`) a **Bránu**.
3. Volitelně zvolte zobrazení (okno / celá obrazovka), počáteční velikost okna, schránku,
   zvuk a směr posouvání myší. Klikněte na **Uložit**.

Připojení můžete mít i více – přepínáte je v horní liště okna.

## Připojení

1. Vložte kartu nebo token.
2. Klikněte na **Připojit**.
3. Zadejte **PIN** ke kartě. Pozor: po několika chybných pokusech se karta zablokuje.
4. Otevře se okno se vzdálenou plochou a okno CardGate se schová. V Docku je stále jen ikona
   CardGate: kliknutím na ni (nebo přes ⌘Tab) se vrátíte ke vzdálené ploše. Zelené tlačítko
   v záhlaví okna přepíná celou obrazovku. Pravým tlačítkem na ikoně v Docku zvolíte **Odpojit**.
5. Po odpojení nebo zavření vzdálené plochy se okno CardGate zase zobrazí.

Klávesové zkratky klienta (celá obrazovka, odpojení…) se používají s klávesami
**levý Control + levý Option + levý Shift** a písmenem (např. **Enter** = celá obrazovka).

## Aktualizace

Při druhém spuštění se CardGate zeptá, zda má nové verze hledat automaticky (jednou denně).
Volbu změníte v **CardGate → Nastavení…** (⌘,).
Ručně: menu **CardGate → Zkontrolovat aktualizace…**. Nová verze se nainstaluje jedním kliknutím;
aplikace přijme jen aktualizaci podepsanou klíčem autora. Kontrola jen stáhne seznam verzí
z GitHubu a nic o vás neodesílá.

## Bezpečnost

- PIN se nikde neukládá. Dialog pro PIN přijme jen PIN v délce, jakou karta povoluje, a upozorní,
  když už byl dříve zadán chybný PIN nebo jde o poslední pokus.
- Po dobu připojení je karta zpřístupněna vzdálenému počítači (kvůli přihlášení do Windows).
  Programy ve vzdálené relaci ji mohou používat stejně, jako by byla vložená přímo v něm.
  Po skončení práce se odpojte, případně kartu vytáhněte.
- Aplikace se připojí jen k bráně s důvěryhodným certifikátem. Pokud ohlásí nedůvěryhodný
  certifikát, nepokračujte a kontaktujte IT oddělení.

## Když něco nefunguje

| Hlášení | Co dělat |
|---|---|
| Na kartě nebyl nalezen certifikát | Vytáhněte kartu/token, znovu zasuňte a zkuste znovu. |
| Software pro čipovou kartu nebyl nalezen | Nainstalujte software ke kartě (např. ProID+). |
| Chybný PIN | Zadejte správný PIN – opakované chyby kartu zablokují. |
| Bránu nelze kontaktovat | Zkontrolujte připojení k internetu a adresu brány. |

Podrobnosti najdete v menu **Okno → Záznam připojení**; tlačítkem **Kopírovat záznam** ho můžete
poslat IT oddělení. Záznam neobsahuje PIN.
Záznamy posledních pěti připojení jsou také ve složce `~/Library/Logs/CardGate`.

## Pro správce IT

Po delším používání (20 úspěšných připojení, nejdřív za týden) aplikace jednou nenápadně nabídne
podporu autora; po zavření se už nikdy neukáže. Nabídku lze plošně vypnout:

```sh
defaults write io.github.jk-sw.cardgate DonationPromptDisabled -bool true
```

(nebo konfiguračním profilem pro doménu `io.github.jk-sw.cardgate`).
