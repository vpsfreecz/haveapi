<h1 id="typed-input-validation">Validace typovaných vstupů</h1>

<h2 id="overview">Přehled</h2>

Parametry HaveAPI deklarují `type` (String, Text, Integer, Float, Boolean, Datetime nebo Resource).
Servery i klienti MUSÍ typované vstupní parametry přísně validovat.
Neplatné hodnoty se NESMÍ tiše převádět na výchozí hodnoty jako `0`, `0.0` nebo `false`.

<h2 id="general-rules">Obecná pravidla</h2>

- Skalární typy přijímají pouze skalární hodnoty. Pole, seznamy, objekty a hashe jsou neplatné.
- Pro účely validace znamená `null`/`nil` „hodnota vynechána“ (server může použít výchozí hodnotu),
  ale explicitní `null` je platný pouze u parametrů označených jako `nullable` (obvykle nepovinných).
  Klienti MUSÍ explicitní `null` zachovat a odeslat jako JSON `null`, aby akce rozlišily
  vynechanou hodnotu od výslovně vymazané.
- Prázdné řetězce (`""` nebo řetězce obsahující jen bílé znaky) jsou pro Integer, Float, Boolean a Datetime neplatné.
  U typovaných parametrů s `nullable` (včetně ID zdrojů) se prázdný řetězec nebo bílé znaky považují
  za `null`/vynechanou hodnotu. To umožňuje vyjádřit explicitní `null` v query stringu.
- Validace na straně klienta se doporučuje; rozhodující je validace serveru.

Příklad query stringu (explicitní `null` pro typovaný parametr s `nullable`):

    GET /resource/action?resource[dt]=

Prázdná hodnota se u typovaných parametrů s `nullable` považuje za `null`.

<h2 id="per-type-rules-with-examples">Pravidla a příklady pro jednotlivé typy</h2>

<h3 id="integer">Integer</h3>

Přijímá:
- celé číslo v JSON (např. `12`, `-7`)
- řetězec odpovídající celému číslu v desítkové soustavě `^[+-]?\d+$` po odstranění krajních bílých znaků (např. `"42"`, `"+5"`)
- konečné číslo s plovoucí řádovou čárkou, které má celočíselnou hodnotu (např. `12.0`)

Odmítá:
- nečíselné řetězce (`"abc"`, `"12abc"`)
- desetinné řetězce (`"12.0"`) a čísla s nenulovou desetinnou částí (`12.3`)
- prázdný řetězec nebo řetězec obsahující jen bílé znaky

<h3 id="float">Float</h3>

Přijímá:
- celé číslo nebo číslo s plovoucí řádovou čárkou v JSON (pouze konečné)
- řetězec obsahující po odstranění krajních bílých znaků úplný zápis čísla, včetně exponentu (např. `"1e3"`, `"-0.5"`)

Odmítá:
- nečíselné řetězce
- prázdný řetězec nebo řetězec obsahující jen bílé znaky
- nekonečné hodnoty a hodnoty, které nejsou číslem (`NaN`, `Infinity`)

Poznámka: celá čísla se pro Float přijímají a převádějí na čísla s plovoucí řádovou čárkou.

<h3 id="boolean">Boolean</h3>

Přijímá:
- logickou hodnotu v JSON
- celé číslo `0`/`1`
- následující řetězce (bez rozlišení velikosti písmen, po odstranění krajních bílých znaků):
  - pravda: `true`, `t`, `yes`, `y`, `1`
  - nepravda: `false`, `f`, `no`, `n`, `0`

Odmítá:
- prázdný řetězec nebo řetězec obsahující jen bílé znaky
- neznámé řetězce (`"maybe"`)
- čísla jiná než 0/1

<h3 id="datetime">Datetime</h3>

Přijímá (přenášený formát): řetězce s datem nebo datem a časem podle ISO 8601:
- `YYYY-MM-DD`
- `YYYY-MM-DDTHH:MM(:SS(.sss)?)?(Z|+HH:MM|-HH:MM|+HHMM|-HHMM)`

Příklady: `"2020-01-31"`, `"2020-01-31T10:20Z"`, `"2020-01-31T10:20:30.123-0500"`.

Odmítá:
- prázdný řetězec nebo řetězec obsahující jen bílé znaky
- jiné formáty než ISO (`2020/01/01`)
- neplatná kalendářní data (`2020-02-30`)

Poznámka: někteří klienti mohou přijímat nativní objekty Date/Time a serializovat je do ISO 8601.

<h3 id="string-text-rule-6-b">String / Text (pravidlo 6.B)</h3>

Přijímá:
- skalární hodnoty (řetězec, číslo, logická hodnota) a převádí je na řetězec

Odmítá:
- pole a seznamy
- objekty a hashe

<h3 id="resource">Resource</h3>

V přenášených datech jsou vstupem identifikátory zdrojů.

Přijímá:
- celočíselné ID
- ID jako řetězec číslic po odstranění krajních bílých znaků
- u některých klientů ResourceInstance, ze které použije `id`
- prázdný řetězec nebo řetězec obsahující jen bílé znaky jako `null`/vynechanou hodnotu, pokud má parametr `nullable`

Odmítá:
- prázdný řetězec nebo řetězec obsahující jen bílé znaky u povinných parametrů
- řetězce obsahující jiné znaky než číslice
- záporná ID

Pokud se server pokusí zdroj dohledat a zdroj neexistuje, MUSÍ vrátit validační chybu
("resource not found"), nikoli chybu 500.

<h2 id="error-reporting-expectations">Očekávané hlášení chyb</h2>

- Server hlásí neplatné typované hodnoty jako chyby validace parametrů ("input parameters are not valid").
- Klienti by měli pokud možno chybu zachytit ihned lokálně a hlásit ji pro jednotlivé parametry.

Doporučené jednotné zprávy používané klienty:
- `not a valid integer`
- `not a valid float`
- `not a valid boolean`
- `not in ISO 8601 format`
- `not a valid string`
- `not a valid resource ID`
- `cannot be null`
