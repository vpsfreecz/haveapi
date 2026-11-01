<h1 id="client-definition">Definice klienta</h1>

Je potřeba rozlišovat mezi klientskou knihovnou pro API založená na HaveAPI
a klientem pro konkrétní instanci API. Tento dokument popisuje knihovnu.
Pokud chceš API jen používat, vyber si ze seznamu dostupných klientů knihovnu
v požadovaném jazyce. Pokračuj, pokud pro něj klient ještě neexistuje.

<h1 id="design-rules">Pravidla návrhu</h1>

Klient musí zcela vycházet z popisu API:

 - nesmí obsahovat předpoklady ani kód specifický pro konkrétní API,
 - předem nezná žádné zdroje, akce ani parametry,
 - vše, co o API ví, musí zjistit z jeho popisu.

Všichni klienti by měli používat podobný přístup, aby se s nimi v různých
jazycích dalo pracovat stejně, pokud to syntaxe jazyka umožňuje. Jako vzor
mohou posloužit klienti dodávaní s HaveAPI. Klient by měl využívat možnosti
a zvyklosti svého jazyka, například objekty v objektově orientovaných jazycích.

Vzorový přístup (bez vazby na konkrétní jazyk):

    // Vytvoření instance klienta
    api = new HaveAPI.Client("https://your.api.tld")

    // Autentizace
    api.authenticate("basic", {"user": "yourname", "password": "yourpassword"})

    // Přístup ke zdrojům a akcím
    api.<resource>.<action>( { <parameters> } )
    api.user.new({"name": "Very Name", "password": "donottellanyone"})
    api.user.list()
    api.nested.resource.deep.list()

    // Předání ID zdrojům
    api.nested(1).resource(2).deep.list()

    // Objektový přístup
    user = api.user.show(1)
    user.id
    user.name
    user.destroy()

    // Odhlášení
    api.logout()

<h1 id="necessary-features-to-implement">Nezbytné funkce</h1>

Aby byl klient použitelný, měl by implementovat všechny následující funkce.

<h2 id="resource-tree">Strom zdrojů</h2>

Klient zpřístupňuje všechny uvedené zdroje a jejich akce.

Ve skriptovacích jazycích jsou zdroje a akce obvykle definovány jako dynamické
vlastnosti, objekty nebo metody podle možností daného jazyka.

<h2 id="input-output-parameters">Vstupní a výstupní parametry</h2>

Umožni odesílat vstupní parametry a přistupovat k odpovědi.

<h2 id="input-output-formats">Vstupní a výstupní formáty</h2>

Klient musí posílat odpovídající HTTP hlavičku `Accept`. HaveAPI má vestavěnou
podporu pouze pro JSON, takže by měl posílat `application/json`.

<h2 id="authentication">Autentizace</h2>

Klient by měl pokud možno podporovat všechny autentizační metody vestavěné
v HaveAPI. Měl by zvolit metodu vhodnou pro své použití a umožnit vývojáři
její výběr tam, kde to dává smysl.

Autentizační metody je vhodné implementovat jako pluginy, aby vývojáři mohli
snadno přidávat vlastní poskytovatele autentizace.

<h2 id="object-like-access">Objektový přístup</h2>

Klient musí interpretovat odpověď API podle rozložení výstupu akce.
Rozložení `object` a `object_list` by měl zpracovávat jako instance objektů,
pokud to jazyk umožňuje.

Instance představují objekty načtené z databáze. Přijaté parametry jsou dostupné
jako atributy nebo vlastnosti objektu. Akce jsou definovány jako metody instance.
Objekty mohou mít vazby na jiné zdroje, které musí být dostupné a snadno přístupné.

<h1 id="supplemental-features">Doplňkové funkce</h1>

Následující funkce je vhodné podporovat, ale nejsou nutné.

<h2 id="client-side-validations">Validace na straně klienta</h2>

Klient může pomocí popsaných validátorů ověřit vstup před odesláním do API,
snížit tak zátěž API a usnadnit práci uživateli.

Tato funkce není povinná, protože vstup se vždy validuje i na serveru.

Validace datových typů parametrů je od validace pomocí validátorů oddělená
a doporučuje se vždy. Před odesláním požadavku by měl klient vynutit pravidla
z dokumentu [Validace typovaných vstupů](typed-input-validation.md).
I v silně typovaných jazycích je potřeba za běhu ověřit hodnoty jako NaN/Inf
a formát řetězců s datem a časem.

<h2 id="metadata-channel">Kanál metadat</h2>

Kanál metadat se používá k určení, které související zdroje se mají předem
načíst a zda má seznam objektů obsahovat celkový počet položek.

Metadata jsou hash ve vstupních parametrech pod klíčem `_meta`.

<h2 id="blocking-actions">Blokující akce</h2>

Blokující akce jsou užitečné pro API s dlouho běžícími operacemi. Klienti
mohou jejich stav kontrolovat pomocí zdroje `ActionState`. Tento zdroj je
automaticky přítomný ve všech API, která blokující akce používají, a klientské
knihovny jej vývojáři zpřístupňují stejně jako ostatní zdroje API.

Můžeš ho ale také začlenit přímo do klienta a umožnit, aby volání akce čekalo
na dokončení nebo přijímalo callbacky.
