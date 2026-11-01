<h1 id="client-examples-in-api-documentation">Klientské příklady v dokumentaci API</h1>

Přihlášení do dokumentace v prohlížeči popisuje [Přihlášení přes OAuth](../en/documentation-oauth.md).

Ruby server vykresluje příklady z popisu API dostupného aktuálnímu uživateli.
Příklady pro JavaScript a TypeScript zahrnují callbackové i asynchronní klienty;
Python zahrnuje synchronní i asynchronní klienty. Tyto klienty není potřeba
na serveru konfigurovat. Dostupné jsou také příklady pro Ruby, PHP, CLI, curl
a HTTP. Pokud klient nedokáže příklad vyjádřit, zobrazí omezení. Nevynechává
vstup ani nevytváří zdání úspěšného výsledku.

Výchozí příklady jsou **Jednoduché**. Příklady akcí předpokládají inicializované
a případně přihlášené `api`; inicializace a autentizace mají samostatné stránky.
Volba Příklady zůstává viditelná a nabízí **S ošetřením chyb**, pokud aktuální
stránka obsahuje pro daného klienta příklady s dodatečným ošetřením chyb.
Příklady bez odlišné podoby ošetření chyb zůstávají jednoduché. Obě úrovně
zachovávají stejné ukázkové hodnoty, argumenty cesty i sémantiku operací.
Samotná dodatečná příprava nevytváří další volbu; vestavěná omezení mají
jeden jednoduchý panel. Navigaci a ukládání nastavení zobrazení popisuje
[průvodce dokumentačním rozhraním](../en/documentation-ui.md).

Příklady používají zástupné přihlašovací údaje: `user` / `secret`,
`example-token` a `example-access-token`. Nahraď je hodnotami své aplikace.
Renderery používají tyto veřejné literály; nečtou přihlašovací údaje
z prostředí, aktuálního uživatele, nastavení profilu ani soukromých výchozích hodnot.

Vstupy přihlášení tokenem a dalších ověřovacích kroků používají názvy polí,
typy a konečné množiny strojově čitelných voleb z popisu dostupného danému
uživateli. Povinné vstupy zůstávají přítomné a doba platnosti je explicitně
pevně daná. Vlastní validace může vyžadovat jiné hodnoty; povinné pole,
které nelze vyjádřit, vede k zobrazení omezení. Názvy a vstupy dalších kroků
odpovídají zveřejněným akcím, zatímco běhová knihovna dodává a předává průběžné tokeny.

API klienti pro Go, Rust a TypeScript vyžadují nastavený profil. Verze jejich
balíčků jsou nezávislé na HaveAPI i na verzi API. Bez profilu server tyto
klienty nezobrazuje v přehledu ani v panelech příkladů. Při nastavování profilu
nainstaluj odpovídající gem generátoru; běžné servery na těchto generátorech nezávisí.

<h2 id="configure-an-api-client">Nastavení API klienta</h2>

Profily zaregistruj před připojením serveru pomocí mount. Pro API klienta,
který odpovídá aktuálnímu API, nastav identitu jeho balíčku:

```ruby
api.documentation_clients('1.0',
  go: {
    import_path: 'example.org/widget/client'
  },
  rust: {
    crate_name: 'widget-client'
  },
  typescript: {
    package_name: '@example/widget-client'
  }
)
api.mount('/api/')
```

Výchozí `generator_version` je `HaveAPI::VERSION` serveru. Do Ruby prostředí
serveru nainstaluj odpovídající generátor: `haveapi-go-client`,
`haveapi-rust-client` nebo zdrojově distribuovaný `haveapi-typescript-client`.
Nastavení popisuje [průvodce generátorem TypeScriptu](../../clients/typescript/README.md).
Explicitní `generator_version` vyžaduje, aby nainstalovaný generátor hlásil
danou verzi; server žádný nestahuje. Tato verze je nezávislá na verzích API klienta i API.

Na konci mount server sestaví jeden soukromý strukturální model pro každou
nastavenou verzi API. Model zahrnuje autentizační zdroje, cesty a změny
z hooků po mount, takže kanonické názvy a argumenty rodičů vycházejí z celé
deklarace API. Soukromá kopie neobsahuje příklady, textové popisy ani výchozí
hodnoty parametrů. HTML požadavky používají popis, pole a příklady dostupné
aktuálnímu uživateli; nikdy nezpřístupňují soukromý model ani diagnostiku
jeho inicializace. Bez nastaveného profilu server nenačítá žádný volitelný
generátor a skrývá panely API klientů pro Go, Rust a TypeScript. Callbackové
a asynchronní příklady TypeScriptu zůstávají samostatné a profil nepotřebují.

Automatické profily předpokládají, že nainstalovaný API klient odpovídá
aktuálnímu kontraktu generování serveru. Název ani verze balíčku nedokládají
jeho obsah. Starší API klient může postrádat nové akce nebo po kolizi či změně
cesty používat jiné názvy. Před nabídnutím klienta ověř kompatibilitu;
pro starší nebo omezené API použij profil s uloženým schématem.

<h3 id="optional-api-client-versions-and-sources">Volitelné verze a zdroje API klientů</h3>

Pokud potřebuješ konkrétní verzi balíčku, nastav `module_version: 'v1.2.3'`
pro Go, `crate_version: '1.2.3'` pro Rust nebo `package_version: '1.2.3'`
pro TypeScript. Vynecháním pole nebo použitím nil necháš výběr vydání
na správci balíčků uživatele. Server se nedotazuje registru ani netvrdí,
že verzi vybral. Při vynechané verzi zobrazí tyto instalační příkazy:

```sh
go get example.org/widget/client@latest
cargo add widget-client
# Blokující varianta Rustu:
cargo add widget-client --features blocking
npm install @example/widget-client haveapi-client@0.30.2
```

Go vyhodnocuje `@latest` podle svých běžných pravidel. Cargo vybírá
kompatibilní vydání podle svého resolveru, manifestu a toolchainu; existující
lockfily zůstávají v platnosti. Explicitní verze pro Cargo jsou nadále
požadavky na verzi bez přidaného přesného připnutí pomocí `=`. Výběr
nejnovějšího vydání se může časem měnit; pokud ho chceš řídit, zadej verzi.
Cargo nikdy nedostává doslovné `version = "latest"`. Příklady pro Rust také
uvádějí požadavky na Tokio a serde_json.

TypeScript přijímá běžné názvy npm balíčků malými písmeny, včetně názvů se
scope, a volitelnou konkrétní verzi SemVer. Tagy, rozsahy verzí, Git URL,
lokální cesty ani vlastní tovární funkce nejsou volbami profilu. Nastav balíček,
který uživatelé mohou nainstalovat; server neověřuje jeho dostupnost ani ho
nepublikuje. Příklady TypeScriptu volají typované vlastnosti balíčku přes jeho
veřejný export `createClient`. Profil nezjišťuje ani nevybírá běhovou knihovnu
`haveapi-client` nainstalovanou v aplikaci. Instalační příkaz výše používá
verzi podporovanou [generátorem TypeScriptu](../../clients/typescript/README.md);
příklady ji neuvádějí jako nakonfigurovanou verzi běhové knihovny.

Pro nepublikovaného API klienta v Rustu zadej HTTPS Git URL a úplné SHA commitu:

```ruby
api.documentation_clients('7.0',
  rust: {
    crate_name: 'vpsadmin-client',
    source: {
      git: 'https://github.com/vpsfreecz/vpsadmin-rust-client',
      rev: 'ff876abe17e3301da62c1b6afbda055ec89db9d2'
    }
  }
)
```

Doporučená závislost pak místo vydání z registru používá tento zdroj:

```toml
# Cargo.toml
vpsadmin-client = { git = "https://github.com/vpsfreecz/vpsadmin-rust-client", rev = "ff876abe17e3301da62c1b6afbda055ec89db9d2" }
# Blokující varianta navíc nastavuje features = ["blocking"].
```

`source` přijímá pouze `git` a `rev`. URL musí být absolutní HTTPS bez
přihlašovacích údajů, query stringu, fragmentů a řídicích znaků; revize musí
mít 40 hexadecimálních znaků. Větve, tagy, lokální cesty ani vlastní registry
nejsou podporované. Explicitní verze crate dále omezuje vybraný zdrojový
balíček. Server nikdy nestahuje repozitář ani nespouští tyto uživatelské
instalační příkazy. Nastavení nepřegeneruje ani nepublikuje API klienta
a nedokládá, že odpovídá konkrétnímu rozhraní API.

<h3 id="saved-schema-overrides">Profily s uloženým schématem</h3>

Stávající profily založené na souborech jsou nadále podporované:

```ruby
api.documentation_clients('1.0',
  go: {
    import_path: 'example.org/widget/client',
    module_version: 'v1.2.3',
    description_path: '/srv/widget-sdk/api-1.0.json',
    generator_version: '0.30.0'
  },
  rust: {
    snapshot_path: '/srv/widget-sdk/api-1.0.snapshot.json',
    generator_config_path: '/srv/widget-sdk/generator.toml',
    generator_version: '0.30.0'
  },
  typescript: {
    package_name: '@example/widget-client',
    package_version: '1.2.3',
    snapshot_path: '/srv/widget-sdk/api-1.0.snapshot.json',
    generator_version: '0.30.0'
  }
)
```

Cesty označují důvěryhodné absolutní lokální soubory. `description_path`
je uložený strojově čitelný popis pro Go, nikoli HTML. U Rustu a TypeScriptu
vybírá `snapshot_path` uložené schéma a metadata jeho pořízení. Tyto soubory
určují přesnou podobu API klienta místo aktuální deklarace serveru. Uchovávej
je soukromě spolu s vydáním API klienta.

Starší volba Rustu `generator_config_path` poskytuje název a verzi crate
i úplnou konfiguraci balíčku. Nelze ji kombinovat s přímo zadanými `crate_name`
a `crate_version`; lze ji spojit s uloženým snapshotem i automatickým
schématem. Uložený snapshot může místo ní používat přímo zadanou identitu
crate. `source` funguje s oběma podobami identity. Server validuje celý starší
TOML; běžná dokumentace s přímým nastavením nepotřebuje volby licence,
kompilátoru ani formátovače.

Uložené soubory se načítají a validují při registraci. Automatické modely se
inicializují na konci mount. Chybějící soubory či generátory, skutečná neshoda
verze generátoru, neznámá pole, konfliktní identity a neplatná schémata způsobí
selhání startu. Mount odmítá také nedostupné verze API a neshodné verze snapshotů
Rustu a TypeScriptu. Při selhání mount se nezveřejní žádné profily a nezůstane
použitelná serverová aplikace. Starší explicitně připnutý generátor může
obsluhovat vhodný starší souborový profil, ale automatický režim Rustu
s přímým nastavením vyžaduje nové tovární rozhraní a neodhaduje náhradní řešení.

Uložený API klient může nadále poskytovat příklady po nesouvisejících rozšířeních
živého API. Každý příklad musí odpovídat uložené cestě, rozložení a kontraktům
předaných parametrů; nedostupné nebo zastaralé příklady zobrazí omezení.
Skryté akce, pole, výchozí hodnoty a příklady zůstávají pro aktuálního uživatele
skryté. Server při HTML požadavku nikdy nestahuje popisy, nepřegenerovává balíčky
ani nespouští kompilátor nebo formátovač.

Staré nastavení profilů funguje na novém serveru. Přímé nastavení vyžaduje
nový kód serveru; návrat ke staršímu kódu vyžaduje i obnovení kompatibilního
nastavení. Kombinace různých verzí serverových workerů může zobrazovat odlišné
příklady, aniž by se měnily přenášené požadavky nebo uložená data.

<h2 id="renderer-extensions">Rozšíření rendererů</h2>

Stávající poziční konstruktory rendererů a metody `init`, `auth(method, desc)`
a `example(sample)` nebo `request(sample)`/`response(sample)` nadále fungují.
Registr pomocí `with_context` připojuje `HaveAPI::ClientExample::Context`
platný pro daný požadavek. Obsahuje vybranou verzi, URL včetně mount cesty API,
filtrovaný popis a aktuální zdroj, akci a příklad. Jeho čtečka `detail` vrací
právě `:simple` nebo `:thorough`, výchozí je `:simple`. Konstruktor
i `context.with(detail: ...)` odmítají jiné hodnoty včetně řetězců a nil.
Změna podrobnosti sdílí již vlastněná data stejně jako jiné odvozené kontexty.
Pomocná metoda základního rendereru `thorough?` čte tuto hodnotu; starší instance
s pozičními argumenty používají jednoduchou podobu. Konstrukce kopíruje
a zmrazuje data Hash, Array a String, aniž by zmrazila kontejnery volajícího.
Každý požadavek vlastní svůj snapshot popisu. `context.with(...)` vytváří
samostatný zmrazený kontext, sdílí nezměněná pole identitou a normalizuje pouze
explicitně předaná pole. I mělce zmrazený vstupní kontejner se musí kopírovat;
explicitní předání již vlastněného Hash, Array nebo String jej také zkopíruje.
Renderery musí s daty vlastněnými kontextem pracovat pouze pro čtení.

Profil je sdílený odkaz; registrované profily a jejich adaptéry se zmrazují
samostatně. Ostatní typy objektů zachovávají dosavadní chování odkazů,
takže konstrukce kontextu neslibuje hluboké zmrazení libovolných objektů.
Podtřídy `Context` se nadále odvozují přes své konstruktory a zachovávají vlastní
inicializaci i další klíčová slova. Optimalizace sdílení platí pouze pro přesnou
základní třídu.

Renderery mohou ze stávajících metod vracet String nebo nil. Nové renderery
vracejí buď `{status: :code, code: source}`, nebo
`{status: :limitation, reason: text}`. Zdrojový text i text omezení jsou obyčejné
řetězce, které šablony jednou escapují. Stabilní třídní `id` označuje variantu;
`code` vybírá jazyk syntaxe. `available?(context)` řídí přehled i každý panel
před vykreslením.

Třídy rendererů deklarují zobrazení pomocí `language 'python'`,
`language_label 'Python'` a u varianty klienta `variant 'Async'`. Tyto třídní
metody metadata také čtou. Jazyk je stabilní ID skupiny malými písmeny,
nezávislé na lexeru syntaxe i přesném ID klienta. Pokud jazyk není určený,
použije se vlastní `id` rendereru, popisek jazyka vychází z `label` a varianta
je nil. Metadata se deklarují na každé třídě; podtřída bez vlastních metadat
dostane tyto výchozí hodnoty. Zachovej ID klientů a pořadí v registru.

Třídní dotaz `detail_levels_for(kind, context:, result:, auth_method: nil,
auth_description: nil)` vybírá smysluplné úrovně pro každou skupinu příkladů.
`result` je již vykreslený jednoduchý výsledek. Vracej zmrazené `[:simple]`
nebo `[:simple, :thorough]`; jiné hodnoty jsou chyba. Základní implementace
vrací zděděnou deklaraci `detail_levels`, která u vlastních rendererů standardně
obsahuje obě úrovně. Vlastní omezení v jednoduché podobě nepotlačí odlišnou
implementaci s ošetřením chyb. Přímé vykreslení s oběma hodnotami podrobnosti
kontextu zůstává podporované nezávisle na volbách nabízených v HTML.

Ruby a PHP nabízejí obě úrovně pro vyjádřitelnou inicializaci, autentizaci
a akce. Ruby OAuth zůstává nepodporovaný. Jejich konstruktory jsou odložené,
takže podoba S ošetřením chyb provádí přípravu explicitně a zpracovává chyby
validace, API, autentizace i protokolu. Ruby zachytává `ValidationError` před
rodičovskou `ActionFailed` a chyby odpovědi čte pouze ze skutečného `Response`.
PHP používá výjimky frameworku a tam, kde je dostupné, `getErrors()`;
neznámé výjimky závislostí vyhazuje znovu. Součástí příkladu zůstávají OAuth
session, state, PKCE, přesměrování i výměna tokenu.

Callbackový JavaScript a TypeScript nabízejí obě úrovně pro akce.
Inicializace a autentizace již kontrolují výsledek připravenosti a nabízejí
jen jednoduchou podobu. Asynchronní JavaScript, asynchronní TypeScript
a Python nabízejí obě úrovně pro vyjádřitelné příklady.

Jednoduché akce v Go již kontrolují chyby přenosu a API. Obě úrovně jsou dostupné
pouze pro úspěšné blokující akce s dostupnou oprávněnou pomocnou akcí pro stav
operace. Inicializace a metody nastavující přihlašovací údaje neposílají žádný
požadavek a nabízejí pouze jednoduchou podobu. Rust nabízí obě úrovně pro
vyjádřitelný kód a explicitně zpracovává výsledky konstrukce a odesílání,
které mohou selhat. Jeho metody pro autentizaci nastavují přihlašovací údaje,
aniž by je ověřovaly přes síť.

Inicializace typovaného TypeScriptu má pouze jednoduchou podobu. Podporovaná
Basic autentizace, autentizace tokenem a akce nabízejí obě úrovně se zpracováním
`AsyncError` pomocí await; OAuth zůstává omezením. CLI, curl a HTTP nabízejí
pouze jednoduchou podobu: CLI hlásí chyby a končí s nenulovým stavem, zatímco
přepisy komunikace ukazují odpovědi protokolu. Všechna vestavěná omezení mají
pouze jednoduchou podobu.

Obalové renderery Go, Rustu a TypeScriptu předávají dotaz
`detail_levels_for(kind:, context:, result:, mode:, auth_method: nil,
auth_description: nil)` svému nastavenému adaptéru, pokud ho implementuje.
Starší adaptéry zachovávají úrovně deklarované obalovým rendererem včetně
odlišného výsledku s ošetřením chyb po omezení jednoduché podoby. Tyto adaptéry
mohou stále nabízet stejný kód na obou úrovních. Pokud dotaz vrátí neplatné
úrovně nebo vyvolá chybu, tato náhrada se nepoužije. Dotazy na schopnosti
nesmí znovu vykreslovat ani procházet nesouvisející zdroje. Producent HTML
vykreslí každou nabízenou podrobnost jednou a zveřejní volby v mapě
`data-example-details` skupiny příkladů. Metadata klienta obsahují uspořádané
sjednocení pro aktuální stránku; klienti bez skupin příkladů dostanou jednoduchou
podobu. Volby skupiny ani stránky nemění uložené nastavení podrobnosti.

Renderery jednoduchých akcí používají připravené `api` a zobrazují skutečné
volání i příslušný výsledek. Inicializuj ho a přihlas pomocí samostatných
příkladů. Asynchronní fragmenty Pythonu patří do asynchronní funkce;
jejich komentář to výslovně uvádí. Příklady přípravy Pythonu používají minimální
asynchronní funkci a `asyncio.run`, zatímco synchronní příklady běží na nejvyšší
úrovni. Ani jedna úroveň nemá podmínku `__main__`. Synchronní příklady
s ošetřením chyb používají `try`/`except` na nejvyšší úrovni.

Zkompiluj a ověř příklady před výběrem podrobnosti zobrazení. Zachovej přesné
názvy, argumenty rodičů, false, nulu, prázdné řetězce, hodnoty s povoleným null
a chování blokujících operací. Příklady nezkracuj vynecháním nepodporovaného
vstupu ani odstraňováním řádků z již vykresleného programu.

Adaptéry generovaných klientů patří do gemů generátorů a používají čtečky
kontextu bez závislosti na serverovém gemu. Názvy určují z úplného soukromého
modelu generátoru a při HTML požadavku nikdy nespouštějí kompilátor, formátovač
ani generátor. Vykreslování adaptérů musí zůstat pouze pro čtení: nastavené
adaptéry jsou zmrazené a sdílené, zatímco snapshoty autorizovaného popisu
patří jednotlivým požadavkům. Adaptéry zachovávají stávající signaturu
`render(kind:, context:, mode:, ...)` a čtou přímo `context.detail`.
Testovací kontexty musí tuto čtečku poskytovat. Starší adaptér třetí strany
může toto přidané pole ignorovat a zachovat deklarované volby obalového rendereru
bez implementace nového dotazu na schopnosti. Odvozené kontexty v jednom
požadavku sdílejí nezměněná vlastněná data. Předání zdroje, akce nebo příkladu
stále kopíruje předaný podstrom, takže vykreslení zdroje s mnoha akcemi může
zůstat nákladné.

<h2 id="example-source-style">Styl zdrojového kódu příkladů</h2>

Generované příklady dodržují zvyklosti svého výstupního jazyka. Pravidla platí
pro inicializaci, autentizaci i akce včetně zděděných callbackových,
synchronních, asynchronních a blokujících variant. Tam, kde jsou podporované
obě úrovně, udržuj jednoduchou podobu i podobu s ošetřením chyb konzistentní.

| Jazyk | Zvyklosti zdrojového kódu |
| --- | --- |
| PHP | Bloky a vnoření polí odsazuj čtyřmi mezerami. Pro běžné statické řetězce bez interpolace používej jednoduché uvozovky a kolem spojování řetězců mezery. Escapované dvojité uvozovky zachovej tam, kde je vyžadují řídicí řetězce nebo výstup s novými řádky. |
| Ruby | Bloky odsazuj dvěma mezerami a pro běžné autorské řetězce používej jednoduché uvozovky. Pro ukázková data zachovej kódování pomocí `dump`, `inspect` a PP. |
| JavaScript / TypeScript | Bloky odsazuj dvěma mezerami, řetězce a specifikátory importů piš do dvojitých uvozovek. Používej středníky a obvyklé mezery po čárkách, dvojtečkách i uvnitř importů a objektových závorek. Zachovej bezpečné vypočítané klíče a typovaný přístup k vlastnostem. |
| Python | Bloky odsazuj čtyřmi mezerami a zachovej stávající kódování dat s dvojitými uvozovkami. Vynechávej prázdná místa pro volitelné importy; před spustitelným kódem na úrovni modulu nech jeden prázdný řádek a kolem asynchronních definic na nejvyšší úrovni dva. |
| Go | Používej tabulátory, mezery kompatibilní s gofmt a oddělené skupiny importů standardní knihovny a klienta. Zachovej nativní kódování řetězců s dvojitými uvozovkami. |
| Rust | Bloky odsazuj čtyřmi mezerami, používej obvyklé mezery a importy Rustu a stávající kodér řetězců v asynchronních i blokujících příkladech. |
| CLI / curl | Zachovej pokračování řádků shellu. Nejprve serializuj data a pak zakóduj každý úplný dynamický argument pomocí `Shellwords.escape`, včetně URL, hlaviček, názvů voleb i hodnot. |
| HTTP | Zachovej přepis protokolu/JSON, zejména oddělení hlaviček od těla. Pravidla shellových uvozovek se neuplatňují. |

Na známých hranicích fragmentů vynechávej nepřítomné části a odděluj logické
bloky jedním účelným prázdným řádkem podle pravidel jazyka výše. Nepřidávej
prázdné řádky na začátek ani konec, duplicitní oddělovače ani bílé znaky na
prázdných řádcích. Formátování patří do rendereru či adaptéru daného jazyka.
Nenormalizuj celé vykreslené programy ani výstup vlastního rendereru společným
regulárním výrazem nebo formátovačem a nepřidávej závislost na formátovači
za běhu. Testy mohou používat nativní formátovače.

U CLI a curl odděluj autorskou syntaxi shellu od dat argumentů. Každý argument
zakóduj jednou po serializaci jeho hodnoty; obalit surová data jednoduchými
nebo dvojitými uvozovkami nestačí. Generované příkazy ověřuj pomocí dočasných
falešných spustitelných souborů: vyžaduj úspěšné provedení, přesné zachycené
hodnoty a pořadí argumentů a žádné nezamýšlené spuštění příkazů. Parsováním
zachyceného JSON z curl ověř, že shellové kódování zachovává celé tělo požadavku.

Příklady CLI a curl mohou za spustitelným příkazem zobrazovat výstup odpovědi.
Každý fyzický řádek odpovědi musí při vložení celého bloku do shellu zůstat
nespustitelný. Normalizuj CRLF a samotné CR na LF pouze v částech odpovědi
určených k zobrazení a každý výsledný řádek uvoď `# `. Nenormalizuj ani
nekomentuj příkaz požadavku a nenahrazuj komentování každého fyzického řádku
shellovým escapováním. Regresní testy musí spustit celý zobrazený blok
s dočasnými falešnými spustitelnými soubory, zachovat přesné argumenty požadavku
a JSON curl a doložit, že nebezpečné víceřádkové hodnoty odpovědi zůstanou
viditelné bez vyhodnocení.

Kódovaná data odděluj od autorské syntaxe. Zachovej skutečné hodnoty, Unicode,
apostrofy, zpětná lomítka, znaky dolaru, řídicí bajty, prázdné hodnoty, false,
nulu i null. Řídicí řetězce PHP mohou vyžadovat dvojité uvozovky s escapovanými
dolary, zpětnými lomítky a uvozovkami a řídicí sekvence platné v PHP;
JSON `\u` není kodér řetězců PHP. Nikdy neměň nový řádek na doslovné
zpětné lomítko s n a nedovol, aby odsazení obalového kódu změnilo bajty literálů.

Změny formátování musí zachovat veřejné ukázkové přihlašovací údaje, vstupy
požadavků, obsluhu chyb a tok řízení, kompatibilitu přímého volání a vlastních
adaptérů i smysluplné volby podrobnosti. Nepřidávej panely jen kvůli odlišnému
formátování.

Při změně rendereru:

- Zkontroluj příslušný výstup inicializace, autentizace a akcí pro dotčené
  varianty a obě přímé hodnoty podrobnosti. Pokryj chybějící volitelné části
  a krajní případy literálů, pokud je změna může ovlivnit.
- Použij stávající [serverové testy příkladů](../../servers/ruby/spec/client_examples/)
  pro ověření zachování literálů PHP a skutečných handlerů, syntaxe Ruby,
  AST a oddělení bloků Pythonu, podrobnosti i vlastních bílých znaků. Podle
  dotčené části použij [dokumentační testy Go](../../clients/go/spec/unit/documentation_spec.rb),
  [dokumentační testy TypeScriptu](../../clients/typescript/spec/unit/) a
  [vývojové kontroly Rustu](../../clients/rust/docs/development.md).
  Pokrytí TypeScriptu zahrnuje zdrojový kód, přísnou kompilaci a výkonnostní testy.
- V sousedních HTML testech, fixturách a výkonnostních asercích vyhledej přesné
  zápisy zdrojového kódu. Aktualizuj záměrně změněná očekávání uvozovek,
  importů a mezer, ale zachovej sémantické aserce, meze procházení a alokací
  i přísné kontroly kompilátoru.
- Dodržuj [vývojové příkazy](../agent-instructions/development.md) a stávající
  požadavky na ověření. Kontroly vybírej podle dotčeného jazyka a chování;
  nesouvisející změna nevyžaduje všechny jazykové toolchainy.

<h2 id="verification">Ověření</h2>

`make test-documentation` kontroluje renderery, kontexty, profily, vykreslené
HTML i lokální assety. Nejprve připrav bundly komponent a vývojové závislosti
JavaScriptu pomocí `make release-deps`. Cíl sestaví JavaScriptový balíček před
kompilací příkladů TypeScriptu proti jeho veřejným deklaracím; Ruby server CI
používá stejné pořadí.

`make test-documentation-python` navíc ověřuje omezení rendereru Pythonu proti
skutečnému kodéru požadavků. Vyžaduje uzamčené prostředí Pythonu připravené
pomocí `make release-deps` a je součástí `make test`. Běžné Ruby testy rendererů
prostředí balíčku Pythonu nepotřebují.

Deterministické regrese kontextů a HTML běží v běžné serverové sadě. Ověřují
sdílení popisu, růst alokací a oddělení uživatelů bez časového limitu běhu.
Sada adaptéru Rustu samostatně ověřuje, že normalizace neprochází nesouvisející
potomky popisu.

Další povinný kontrakt `make test-performance-clients` kontroluje každý
registrovaný renderer a režim se skutečnými generovanými profily, omezenou
prací a alokacemi na vykreslení i škálováním alokací celé stránky. Běží
v uzamčeném benchmarkovém prostředí bez Bundleru, odděleně od běžného
serverového bundlu. Přípravu, přesné pokrytí a chování CI popisuje
[testování výkonu](../en/performance.md#all-client-documentation-contract).

<h3 id="documentation-benchmark">Benchmark dokumentace</h3>

Připrav serverový bundle v jeho deklarovaném Nix prostředí a pak spusť
volitelný měřicí nástroj z kořene repozitáře:

```sh
nix develop .#server-ruby --command bash -c \
  'make --no-print-directory benchmark-documentation > /tmp/documentation.json'
```

Cíl před spuštěním nástroje synchronizuje sdílenou dokumentaci. Standardní
výstup je JSON; příprava shellu a závislostí proběhne před přesměrovaným
příkazem. Nespouští se síťový server, databáze, kompilace API klienta ani
formátovač. Syntetická fixtura má uživatele `admin` a `member`. Přímé
vykreslování a měření popisu používají Basic autentizaci s lokálním heslem
`fixture-only`. HTML požadavky na podporovaných zdrojích používají skutečné
OAuth cookies dokumentace s ověřením tokenu při každém požadavku; historické
zdroje bez této funkce používají Basic.

Výchozí měření zahrnuje dvě podoby s osmi běžnými akcemi: osm zdrojů s jednou
akcí a jeden zdroj s osmi akcemi. Každá běžná akce má i privilegovaný příklad;
první zdroj má další akci pouze pro správce. Měření kontextu odvozuje
z připraveného rodiče kontext se změněným profilem nebo s pevným malým
příkladem. HTML měření při každém opakování provede jeden skutečný Rack
požadavek se všemi dostupnými dynamickými panely rendererů. Použij minimální
ověřovací běh nebo rozsáhlejší opakované měření:

```sh
make benchmark-documentation \
  BENCHMARK_DOCUMENTATION_ARGS='--shape resources --size 1 --warmup 0 --trials 1 --iterations 1'
make benchmark-documentation \
  BENCHMARK_DOCUMENTATION_ARGS='--shape both --size 64 --samples 2 --parameters 8 --warmup 2 --trials 7 --iterations 500' \
  > /tmp/documentation-large.json
```

Tyto příkazy `make` spouštěj v připraveném shellu. `--shape custom --resources
N --actions N` ovládá oba rozměry nezávisle; `--lanes context` omezuje měření
na odvozování a `--lanes html` na požadavky. `--user member` vybírá omezenou
dokumentaci. `--help` vypíše všechny volby. `--rust` zapne odpovídající Rust
profil fixtury, zahrne obě varianty Rustu do HTML a přidá samostatná měření
asynchronních i blokujících akcí a autentizačních adaptérů. Vyžaduje dostupné
Ruby závislosti volitelného generátoru; běžné benchmarky je nepotřebují.
Připrav obě prostředí pomocí `nix develop .#server-ruby` a
`nix develop .#client-rust`. Samotný serverový bundle neaktivuje závislosti
Rustu. V hlavním Nix shellu spoj připravená lokální úložiště gemů:

```sh
env -u RUBYOPT -u RUBYLIB -u BUNDLE_BIN_PATH -u BUNDLE_GEMFILE \
  -u BUNDLE_LOCKFILE -u BUNDLE_PATH -u BUNDLE_FROZEN -u BUNDLER_SETUP \
  GEM_PATH="$PWD/.gems:$PWD/clients/rust/.gems:$(ruby -e 'puts Gem.default_dir')" \
  make benchmark-documentation BENCHMARK_DOCUMENTATION_RUBY=ruby \
  BENCHMARK_DOCUMENTATION_ARGS='--rust --shape both --size 8 --warmup 1 --trials 3 --iterations 100' \
  > /tmp/documentation-rust.json
```

Příkaz běží mimo Bundler a zaznamenává skutečně aktivované verze gemů.
Uchovej jejich seznam spolu s lockfily obou komponent a pro obě revize použij
stejné připravené vstupy. Chybějící volitelné závislosti způsobí selhání;
měření Rustu se nikdy tiše nevynechává. Viz
[průvodce adaptérem Rustu](../../clients/rust/docs/documentation.md#verification).

Každé měření hlásí jednotlivá opakování i medián reálného času, procesorového
času procesu a alokovaných objektů spolu s počtem operací na opakování.
Reálný čas používá monotónní hodiny. Před každým opakováním proběhne úplný GC
mimo měřený interval; GC vyvolaný měřenou prací zůstává zahrnutý. Konstrukce
mount a profilů má samostatné metriky přípravy. Konstrukce vlastněných dat,
výběr popisu, zahřívání, validace výstupu, hashování a serializace JSON jsou
mimo měřený interval. Výstupy obsahují rozměry fixtury, ID rendererů, režim
profilu, běhové prostředí Ruby, hostitele, Git HEAD/status/digest diffu,
digesty načtených zdrojů, verze závislostí a dostupné digesty lockfilů,
měřicího nástroje i fixtury. HTML a Rust výstupy zahrnují stav, počet bajtů
a SHA-256; selhání nebo chybějící výstup vede k nenulovému návratovému kódu.

Pro porovnání před a po změně uchovej jeden přesný měřicí nástroj a fixturu
a pomocí `--source-root /absolute/checkout` je nasměruj na každou implementaci.
Nejprve připrav stejné závislosti a běhové prostředí. Explicitní
`--source-revision LABEL` může doplnit zjištěný HEAD a je povinné pro
exportovaný zdrojový strom. Uchovej přesné revize, příkazy, surové JSON
výstupy, identity lockfilů a vstupů i hostitele. Před porovnáním mediánů
porovnej rozměry, režimy rendererů, stavy, bajty a digesty těl. Kontextové
`description_shared` záměrně rozlišuje starou implementaci s kopírováním.
Každý rozdíl výstupu prošetři; případnou přesnou normalizaci proměnlivých polí
zaznamenej, místo abys neshody tiše vynechával.

Tato měření popisují syntetickou zátěž na zaznamenaném hostiteli. Nedokládají
latenci v produkci. Volitelný benchmark nemá časový limit;
[párová výkonnostní sada endpointů](../en/performance.md) poskytuje povinné rychlé
a týdenní CI kontroly času, alokací a dotazů včetně dokumentačního OPTIONS
a obou podob HTML. Zachovává šum baseline/self a blokuje neprůkazné výsledky.
Regrese vlastnictví, procházení a alokací pokrývají tento druh selhání;
náklady koncentrovaných zdrojů i jiné budoucí regrese nadále vyžadují
reprezentativní měření.

Každý klient má také příkazy pro akceptační testy, které ověřují spustitelné
ukázky proti nainstalovaným balíčkům nebo API klientovi. Spouštějí vykreslený
kód proti dočasným fixturám; samotná kontrola syntaxe nedokládá funkčnost
volání klienta ani autentizace. Testovací prostředí popisuje vývojová
dokumentace jednotlivých klientů. Sestavení highlighteru popisuje
[utils/highlight](../../utils/highlight/README.md).
