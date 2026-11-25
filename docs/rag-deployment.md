# Revisión y despliegue posterior de RAG-01

Estos comandos son instrucciones; no se ejecutaron contra Supabase.

Para pruebas sin proyecto remoto se validó la alternativa mínima documentada en
[`../infrastructure/rag-local/README.md`](../infrastructure/rag-local/README.md).
Utiliza PostgreSQL, pgvector y PostgREST ligados exclusivamente a loopback.
El mismo entorno incluye pruebas HTTP reales del servidor RAG con embeddings
deterministas de integración, restringidos a loopback y sin valor semántico.

## 1. Pruebas locales

```powershell
python -m pip install -r .\requirements-test.txt
python -m pytest -v tests\test_rag_components.py tests\test_rag_lifecycle_migration.py
$env:NEBULA_RAG_DOCKER_TEST = '1'
python -m pytest -v tests\test_rag01_postgres_integration.py
Remove-Item Env:NEBULA_RAG_DOCKER_TEST
```

## 2. Proyecto Supabase aislado

Confirmar antes la versión principal de PostgreSQL, pgvector 0.8.2 en
`extensions`, el rol ejecutor y que la URL corresponde al proyecto de pruebas.

```powershell
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -f .\supabase\migrations\20261124060000_rag_academic_documents.sql
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -f .\supabase\migrations\20261124070000_rag_document_lifecycle.sql
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -f .\supabase\migrations\20261124080000_rag_classification_hybrid_search.sql
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -f .\supabase\migrations\20261124090000_rag_api_role.sql
```

Después se debe verificar propietario, `prosecdef`, `proconfig`, ACL, RLS y una
llamada PostgREST con un vector sintético. No usar producción como primer destino.

## 3. Perfil de embeddings

Tras aprobar proveedor, costo, términos y dimensión, una sesión administrativa
revisada puede registrar el perfil. No deben hacerlo los logins de búsqueda,
ingesta o revisión. Ejecutar en SQL Editor, en consultas separadas y completas:

1. `scripts/rag/precheck_rag_embedding_profile.sql` y exigir
   `RAG_EMBEDDING_PROFILE_PREFLIGHT_READY`.
2. `scripts/rag/create_rag_embedding_profile.sql`, que inserta una sola fila
   `gemini-embedding-001-768` con estado `inactive`.
3. `scripts/rag/verify_rag_embedding_profile.sql` y exigir
   `RAG_EMBEDDING_PROFILE_VERIFIED`.

La creación no usa `ON CONFLICT`, no actualiza perfiles existentes y se ejecuta
dentro de una sola transacción.

Debe comprobarse primero que no exista otro perfil activo y generar un vector de
prueba para verificar exactamente 768 componentes y norma cercana a 1. El perfil
solo cambia a `active` despues de completar staging, embeddings, revision humana
y aprobacion del primer documento. La activacion es una operacion administrativa
separada; el login de busqueda y la futura identidad de ingesta no deben poder
activar perfiles.

## 4. Herramienta HTTP para n8n

El proceso se inicia únicamente en infraestructura privada:

```powershell
python -m nebula_rag.server
```

Contrato:

```http
POST /v1/rag/search
X-Nebula-Tool-Key: <credencial de servidor n8n>
Content-Type: application/json

{"query":"texto de consulta","limit":5,"threshold":0.2,"curriculum_scope":"old_9s_151c"}
```

La respuesta contiene `success`, `result_count`, `sources` y `context`. Cada
fuente incluye título, URL, localizador, similitud, metadatos y flags de
seguridad. Un resultado vacío es válido.

En n8n, la clave debe residir en una credencial de Header Auth, no en el prompt,
expresiones visibles ni configuración del modelo. Gemini recibe únicamente el
resultado delimitado como referencia no confiable. Antes de conectar el workflow
principal se debe probar en un workflow aislado: 401 sin clave, 400 para contrato
inválido, 200 vacío, 200 con citas y 503 cuando el proveedor no está disponible.

`curriculum_scope` solo admite `old_9s_151c` o `general`; el servicio rechaza
`new_2027_8s_134c`. Un HTTP 200 con `result_count: 0` significa ausencia de
evidencia, no un error.

## 5. Scripts protegidos y rollback

```powershell
$env:RAG_TEST_DATABASE_URL = '<solo proyecto aislado>'
.\scripts\rag\Apply-RagMigrations.ps1 -AllowRemote -ExpectedProjectRef '<ref-aislada>'
python .\scripts\rag\Verify-RagPostgrest.py --allow-network
```

Ambos requieren confirmación interactiva y bloquean el proyecto principal
conocido. La reversión completa del RAG en el proyecto aislado es:

```powershell
.\scripts\rag\Remove-RagFromIsolatedProject.ps1 -AllowRemote -ExpectedProjectRef '<ref-aislada>'
```

El rollback elimina solo las RPC RAG y el esquema `rag`; no referencia
`academic`, `student`, Auth, memoria ni herramientas personales. Destruye el
corpus RAG, por lo que debe exportarse antes fuera de un entorno desechable.

## 6. Publicación HTTPS

`infrastructure/rag/compose.rag.example.yaml` es independiente del Compose
existente. Solo Caddy publica 443; el API permanece en la red Docker. Las claves
se cargan desde `.env.rag`, ignorado por Git. En n8n, `NEBULA_RAG_TOOL_KEY` se
guarda como Header Auth `X-Nebula-Tool-Key`; nunca se copian la conexión de
PostgreSQL ni la clave de Gemini al workflow o al prompt.

## Pendientes externos

- aplicar las tres migraciones en Supabase aislado;
- comprobar PostgREST con el tipo `extensions.vector`;
- confirmar propietario real de la RPC;
- aprobar costos/términos de Gemini Embeddings;
- inventariar y autorizar fuentes UNAB;
- desplegar el servidor de herramienta detrás de HTTPS;
- crear credenciales de servidor en n8n y verificar visualmente la tool call.

## Rol minimo y activacion controlada

La migracion 009 crea `nebula_rag_api` como `NOLOGIN`, sin atributos
administrativos, sin acceso directo a `rag` y con `EXECUTE` solamente sobre las
dos RPC de busqueda. El login operativo se crea aparte y su clave nunca se
versiona:

```powershell
$env:RAG_TARGET_DATABASE_URL = '<conexion administrativa temporal revisada>'
.\scripts\rag\Invoke-RagPreflight.ps1 -AllowRemoteReadOnly
# Aplicar 006, 007, 008 y 009 con ON_ERROR_STOP=1.
.\scripts\rag\Create-RagApiLogin.ps1 -AllowDatabaseChange
```

Antes de dirigir trafico: ejecutar `verify_rag_deployment.sql`, comprobar que el
login ejecuta ambas RPC y que no puede hacer `SELECT`, `INSERT`, `UPDATE` o
`DELETE` en `rag.*`; luego probar por HTTPS 401, 400, 200 sin resultados y 200
con referencias, inicialmente sin Gemini. Supabase Cloud puede limitar roles
personalizados o su acceso por Supavisor; esto debe verificarse en el destino.

Produccion usa `RAG_EMBEDDING_PROVIDER=gemini`, el perfil y dimension aprobados,
y un gestor de secretos para `RAG_DATABASE_URL`, `GEMINI_API_KEY` y
`NEBULA_RAG_TOOL_KEY`. El contenedor escucha en su red privada y solo el proxy
HTTPS publica 443. El proveedor determinista exige loopback, por lo que no puede
arrancar con el host publico del contenedor. n8n conserva exclusivamente la
clave `X-Nebula-Tool-Key` como Header Auth; no recibe credenciales PostgreSQL.

Rollback no destructivo: retirar primero la credencial de n8n, detener la API y
ejecutar `scripts/rag/disable_rag_service_access.sql` para revocar solamente las
dos ejecuciones del rol de servicio. Conservar tablas y corpus para diagnostico. El rollback que
elimina RPC y esquema se reserva para proyectos aislados porque destruye el
corpus; nunca debe ejecutarse automaticamente en el proyecto principal.

### Despliegue revisado en el proyecto principal

Las migraciones 006, 007 y 008 revocan `EXECUTE` a `PUBLIC`, `anon` y
`authenticated` antes de cada `COMMIT`. La 009 vuelve a revocar defensivamente
y concede acceso solo a `nebula_rag_api`. Si el proceso se interrumpe antes de
009, las RPC quedan instaladas pero inaccesibles.

El respaldo y despliegue no aceptan URLs con contrasena como argumento. Solicitan
la clave mediante `SecureString`, usan variables `PG*` solo durante el proceso y
las restauran al finalizar:

```powershell
.\scripts\rag\Backup-RagPredeploy.ps1 `
  -ProjectRef icsekpkuheckfkgkqosg `
  -DatabaseHost '<host copiado de Supabase Connect>' `
  -DatabaseUser '<postgres o postgres.icsekpkuheckfkgkqosg>' `
  -OutputFile 'D:\respaldo-seguro\nebula-pre-rag.dump'

.\scripts\rag\Deploy-RagToPrimary.ps1 `
  -ProjectRef icsekpkuheckfkgkqosg `
  -DatabaseHost '<mismo host revisado>' `
  -DatabaseUser '<mismo usuario revisado>' `
  -AllowPrimaryDeployment
```

El respaldo debe estar fuera del repositorio, protegido por controles de acceso
y cifrado por el sistema de almacenamiento. El despliegue usa `ON_ERROR_STOP`,
`lock_timeout=5s` y `statement_timeout=120s`, aplica 006-009 en orden y ejecuta
la verificacion SQL. No crea el login del servicio ni carga documentos.

## Ingesta y revision con identidades separadas

La migracion 010 (`20261124100000_rag_ingestion_roles.sql`) propone dos roles
grupales `NOLOGIN`:

- `nebula_rag_ingest`: puede crear documentos pendientes, fragmentos y
  embeddings asociados a sus propios documentos. No puede aprobar, rechazar,
  activar perfiles, borrar filas ni consultar datos estudiantiles.
- `nebula_rag_reviewer`: puede leer el corpus RAG y ejecutar exclusivamente
  `public.nebula_review_rag_document`. No puede ingerir, editar tablas
  directamente ni activar perfiles.

Los logins operativos se deben crear por separado, con secretos solicitados de
forma privada y membresia en un solo rol grupal. No se debe reutilizar
`nebula_rag_api_login`. La activacion o retiro de perfiles sigue siendo una
operacion administrativa controlada y queda fuera de ambos roles.
La propiedad se registra con `SESSION_USER`, no con `CURRENT_USER`, para
conservar la identidad del login aun si una conexion ejecuta `SET ROLE`.

El orden seguro es: `preview` sin base de datos; `stage` con la identidad de
ingesta; `embed` con la misma identidad; revision humana; y `approve` o `reject`
con la identidad revisora. Una revision anterior permanece vigente durante el
staging y solo se marca reemplazada dentro de la aprobacion transaccional de la
nueva revision.

Verificacion local repetible:

```powershell
python -m pytest -q tests/test_rag_ingestion_migration.py tests/test_rag_local_isolation.py
$env:NEBULA_RAG_DOCKER_TEST = '1'
try { python -m pytest -q tests/test_rag01_postgres_integration.py } `
finally { Remove-Item Env:NEBULA_RAG_DOCKER_TEST -ErrorAction SilentlyContinue }
```

Antes de aplicar 010 en Supabase Cloud se debe ejecutar un preflight de solo
lectura para confirmar que no existen roles, columna, politicas o firma RPC con
los mismos nombres, y que no hay documentos reales cuyo propietario de ingesta
requiera una decision de migracion. Despues de aplicarla, ejecutar
`scripts/rag/verify_rag_ingestion_security.sql` antes de crear logins.

En Supabase SQL Editor, abrir una consulta nueva, copiar integramente
`scripts/rag/preflight_rag_ingestion.sql` y ejecutar. El resultado aceptable es
`RAG_INGESTION_PREFLIGHT_READY`; cualquier excepcion o el resultado
`RAG_INGESTION_PREFLIGHT_PENDING_EXISTING_DOCUMENTS` detiene el despliegue.
El script inicia `BEGIN TRANSACTION READ ONLY` y termina siempre en `ROLLBACK`.

El despliegue controlado de 010 requiere: respaldo logico verificado fuera del
repositorio; preflight READY; una ventana sin procesos de ingesta; ejecucion
integra de la migracion 010 con parada ante el primer error; y ejecucion de
`scripts/rag/verify_rag_ingestion_security.sql`. Si falla la migracion, su
transaccion hace rollback. Si falla solamente la verificacion posterior, no se
crean logins ni se carga contenido hasta investigar; se conservan las tablas y
el corpus, evitando un rollback destructivo.
