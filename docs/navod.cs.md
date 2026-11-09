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
4. Otevře se okno se vzdálenou plochou.

Klávesové zkratky klienta (celá obrazovka, odpojení…) se používají s klávesami
**levý Control + levý Option + levý Shift** a písmenem (např. **Enter** = celá obrazovka).

## Když něco nefunguje

| Hlášení | Co dělat |
|---|---|
| Na kartě nebyl nalezen certifikát | Vytáhněte kartu/token, znovu zasuňte a zkuste znovu. |
| Software pro čipovou kartu nebyl nalezen | Nainstalujte software ke kartě (např. ProID+). |
| Chybný PIN | Zadejte správný PIN – opakované chyby kartu zablokují. |
| Bránu nelze kontaktovat | Zkontrolujte připojení k internetu a adresu brány. |

Podrobnosti najdete v menu **Okno → Záznam připojení**; tlačítkem **Kopírovat záznam** ho můžete
poslat IT oddělení. Záznam neobsahuje PIN.
