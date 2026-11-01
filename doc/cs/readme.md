<h1 id="haveapi">HaveAPI</h1>

Serverová implementace protokolu [HaveAPI](https://github.com/vpsfreecz/haveapi)
v Ruby má podobu frameworku pro tvorbu RESTful webových API, která poskytují
vlastní popis. Framework obsahuje DSL pro definici zdrojů, akcí a vstupních
i výstupních parametrů. HaveAPI zajišťuje HTTP komunikaci, autentizaci,
zpracování vstupních parametrů i formátování výstupu, takže se můžeš soustředit
na aplikační logiku.

<h2 id="server-framework-features">Funkce serverového frameworku</h2>

- Zajišťuje síťovou komunikaci, autentizaci, autorizaci, vstupní a výstupní
  formáty i parametry; stačí definovat zdroje a akce
- Dokumentace vzniká společně s kódem
- Automaticky generovaná online HTML dokumentace
- Integrace s ORM
  - ActiveRecord
    - propojení s řadičem
    - načítání a dokumentování validátorů z modelů
    - přednačítání souvisejících dat
  - snadné doplnění podpory dalších ORM frameworků

<h2 id="usage">Použití</h2>

Text nemusí být úplný ani aktuální, protože se rozhraní stále často mění.
Příkladem plného využití HaveAPI je
[vpsadmin-api](https://github.com/vpsfreecz/vpsadmin-api)
([online dokumentace](https://api.vpsfree.cz)).

Všechny zdroje a akce představují třídy. Musí být uložené v modulu, jehož
název se předá HaveAPI. Framework pak projde třídy v tomto modulu a sestaví API.

V tomto dokumentu budou všechny zdroje v modulu `MyAPI`.

<h3 id="example">Příklad</h3>

Základní příklad neukazuje všechny možnosti a funkce.

Předpokládejme tento model:

```ruby
class User < ActiveRecord::Base
  validates :login, :full_name, :role, presence: true
  validates :login, format: {
      with: /[a-zA-Z\.\-]{3,30}/,
      message: 'not a valid login'
  }, uniqueness: true
  validates :role, inclusion: {
    in: %w(admin user),
    message '%{value} is not a valid role'
  }

  # Příklad autentizace s heslem v prostém textu
  def self.authenticate(username, password)
    u = User.find_by(login: username)

    if u
      u if u.password == password
    end
  end
end
```

Zdroj pro uživatele může vypadat takto:

```ruby
module MyAPI
  class User < HaveAPI::Resource
    # Tento zdroj patří do verze 1.
    # Zdroj může patřit i do více verzí, například [1, 2]
    version 1

    # Popis zdroje
    desc 'Manage users'

    # Model ActiveRecord, ze kterého se načtou validátory
    model ::User

    # Vyžadovat autentizaci; jde o výchozí nastavení
    auth true

    # Pojmenovaná skupina sdílených parametrů, kterou pak mohou
    # použít akce.
    params(:id) do
      id :id, label: 'User ID'
    end

    params(:common) do
      string :login, label: 'Login', desc: 'Used for authentication'
      string :full_name, label: 'Full name'
      string :role, label: 'User role', desc: 'admin or user'
    end

    # Akce
    # Modul HaveAPI::Actions::Default obsahuje pomocné třídy, které definují
    # HTTP metody a cesty pro obecné akce.
    class Index < HaveAPI::Actions::Default::Index
      desc 'List all users'

      # Žádné vstupní parametry

      # Výstupní parametry
      output(:object_list) do
        use :id
        use :common
      end

      # Určení, zda může aktuální uživatel tuto akci použít.
      # allow/deny ihned ukončí tento blok.
      # Výchozím pravidlem je deny.
      authorize do |u|
        allow if u.role == 'admin'
        deny  # deny je implicitní, takže ho lze vynechat
      end

      # Příklad použití
      example do
        request({})
        response({
          users: [
            {
              id: 1,
              login: 'myuser',
              full_name: 'My Very Name'
            }
          ]
        })
        comment 'Get a list of all users like this'
      end

      # Pomocná metoda vracející dotaz na všechny uživatele
      def query
        ::User.all
      end

      # Tato metoda se volá, pokud požadavek obsahuje meta[:count] = true
      def count
        query.count
      end

      # Provedení akce a vrácení seznamu
      def exec
        with_pagination(query)
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create new user'

      input do
        use :common
      end

      output do
        use :id
        use :common
      end

      authorize do |u|
        allow if u.role == 'admin'
        deny
      end

      example do
        request({
          user: {
            login: 'anotherlogin',
            full_name: 'My Very New Name'
          }
        })
        response({
          user: {
            id: 2
          }
        })
        comment 'Create new user like this'
      end

      def exec
        user = ::User.new(input)

        if user.save
          ok!(user)
        else
          error!('save failed', user.errors.to_hash)
        end
      end
    end
  end
end
```

<h3 id="what-you-get">Výsledek</h3>

Z tohoto kódu HaveAPI vygeneruje API s vlastním popisem. Bude obsahovat zdroj
`User` s akcemi `Index` a `Create`, kterými můžeš vypsat existující uživatele
a vytvářet nové.

S API můžeš pracovat pomocí kteréhokoli z dostupných klientů.

<h3 id="run-the-example">Spuštění příkladu</h3>

```ruby
api = HaveAPI::Server.new(MyAPI)

# Použití HTTP Basic autentizace
class BasicAuth < HaveAPI::Authentication::Basic::Provider
  def find_user(request, username, password)
      User.authenticate(username, password)
  end
end

api.use_version(:all)
api.auth_chain << BasicAuth
api.mount('/')

api.start!
```

Tím by se měla aplikace spustit pomocí WEBrick. Otevři
[http://localhost:4567](http://localhost:4567).

- `GET /` – seznam verzí API
- `GET /doc` – dokumentace HaveAPI
- `GET /v1/` – dokumentace verze 1
- `OPTIONS /` – popis celého API
- `OPTIONS /v1/` – popis verze API 1

a další rozhraní.

<h2 id="localization">Lokalizace</h2>

HaveAPI může pomocí Ruby `i18n` překládat vlastní zprávy v odpovědích,
validační chyby a popisy validátorů. Struktura JSON obálky zůstává stejná;
`message`, `errors` i zprávy validátorů v popisu API jsou nadále obyčejné
řetězce. Řetězce dodané aplikací do `error!` nebo do voleb `message:` vlastních
validátorů se vracejí beze změny.

Výchozím jazykem je angličtina. Součástí jsou české překlady, které lze vybrat
hlavičkou `Accept-Language: cs` nebo regionální variantou, například
`Accept-Language: cs-CZ`.

```ruby
api = HaveAPI::Server.new(MyAPI)

api.default_locale = :en
api.available_locales = %i[en cs]
api.locale_header = 'Accept-Language'

api.locale do |request:, current_user:, default_locale:|
  current_user&.language&.code || default_locale
end
```

Explicitní hlavička požadavku má přednost před resolverem. Resolver se volá
znovu po autentizaci, takže aplikace může použít jazykové nastavení
přihlášeného uživatele, pokud klient jazyk nezvolil. Pokud `locale_header`
určuje vlastní název hlavičky, HaveAPI ji také povolí v odpovědích na CORS
preflight požadavky. Hodnota hlavičky má stejnou syntaxi jako `Accept-Language`.

Akce mohou používat překlady aplikace předáním odložených zpráv do `error!`
nebo do voleb validátoru:

```ruby
error!(api_message('my_api.errors.quota_exceeded', limit: max_limit))

input do
  string :name, required: {
    message: HaveAPI.message('my_api.validation.name_required')
  }
end
```

Pokud akce potřebuje překlad ihned jako řetězec, použij `api_t(key, **values)`.
V DSL blocích na úrovni třídy, například `input`, použij
`HaveAPI.message(key, **values)`.

Popisky a popisy parametrů akcí se mohou překládat v kontextu popisu API.
Nastav `parameter_i18n_scope` na jmenný prostor překladů aplikace a ponech
stávající anglické popisky a popisy jako náhradní hodnoty:

```ruby
api.parameter_i18n_scope = 'my_api'

input do
  string :hostname,
         label: 'Hostname',
         desc: 'VPS hostname'
end
```

HaveAPI nejprve hledá přesný klíč parametru akce:

```yaml
cs:
  my_api:
    resources:
      vps:
        actions:
          create:
            input:
              hostname:
                label: "Hostname"
                description: "Nazev VPS"
```

Vygenerovaná cesta je
`resources.<resource_path>.actions.<action>.<input|output>.<name>`.
U parametrů metadat zahrnuje také typ metadat a směr, například
`resources.vps.actions.create.meta.global.output.action_state_id.label`.

Pokud přesný klíč chybí, HaveAPI hledá mezi vstupními a výstupními klíči
zdroje, atributy zdroje a nakonec sdílenými atributy:

```yaml
cs:
  my_api:
    resources:
      vps:
        input:
          hostname:
            label: "Hostname"
            description: "Nazev VPS"
        output:
          hostname:
            label: "Hostname"
        attributes:
          hostname:
            label: "Hostname"
    attributes:
      hostname:
        label: "Hostname"
```

Popisky voleb deklarovaných validátorem `choices`/`include` používají stejnou
cestu metadat parametru s připojeným `choices.<value>.label`. Pokud jsou volby
zadané jako mapa hodnot na popisky, použije se deklarovaný popisek jako
anglická náhradní hodnota. Pokud jsou zadané jako pole, nepřeložený popis API
zachová formát pole; jazyk, který poskytuje popisky, vrací existující formát
mapy HaveAPI `{value: label}`.

```yaml
cs:
  my_api:
    resources:
      vps:
        attributes:
          state:
            choices:
              running:
                label: "bezi"
              stopped:
                label: "vypnuto"
```

U parametrů metadat se jako náhrada hledají klíče metadat zdroje a globálních metadat:

```yaml
cs:
  my_api:
    resources:
      vps:
        meta:
          global:
            output:
              count:
                label: "Return item count"
    meta:
      global:
        output:
          count:
            label: "Return item count"
```

Vlastní metadata HaveAPI, například stránkování a vestavěné meta parametry,
překládá přímo HaveAPI a nehledá je v jmenném prostoru parametrů aplikace.
Pokud parametr potřebuje explicitní klíč, který nevychází z jeho umístění
v akci, použij `label_key` a `desc_key`:

```ruby
string :hostname,
       label: 'Hostname',
       desc: 'VPS hostname',
       label_key: 'my_api.attributes.hostname.label',
       desc_key: 'my_api.attributes.hostname.description'
```

HaveAPI také zpřístupňuje `api.parameter_metadata_i18n_items` pro nástroje,
které z deklarovaných parametrů generují katalogy překladů aplikace.

<h3 id="run-with-rackup">Spuštění pomocí rackup</h3>

Použij stejný kód jako výše, pouze poslední řádek nahraď tímto:

```ruby
run api.app
```

<h2 id="authentication">Autentizace</h2>

HaveAPI definuje rozhraní pro poskytovatele autentizace. Vestavěná je HTTP
Basic autentizace a autentizace tokenem.

Možnosti autentizace jsou součástí popisu API. Klient si může zvolit metodu,
které rozumí a kterou chce použít.

<h2 id="authorization">Autorizace</h2>

HaveAPI poskytuje prostředky pro autorizaci přístupu uživatelů k akcím.
Tento proces není součástí popisu API.

Pokud je uživatel při požadavku na popis API přihlášený, vrátí se pouze
zdroje, akce a parametry, ke kterým má přístup.

<h2 id="validation-of-input-data">Validace vstupních dat</h2>

Validátory jsou součástí dokumentace API, takže klienti mohou validovat data
ještě před jejich odesláním na server.

<h2 id="blocking-actions">Blokující akce</h2>

Blokující režim slouží pro akce, jejichž provedení není okamžité a trvá
předem neurčenou dobu. Protokol HaveAPI umožňuje klientům sledovat jejich
průběh nebo je zrušit.

<h2 id="contributing">Přispívání</h2>

1. Vytvoř fork ( https://github.com/vpsfreecz/haveapi/fork )
2. Vytvoř větev pro svou změnu (`git checkout -b my-new-feature`)
3. Vytvoř commit se změnami (`git commit -am 'Add some feature'`)
4. Odešli větev (`git push origin my-new-feature`)
5. Vytvoř nový pull request
