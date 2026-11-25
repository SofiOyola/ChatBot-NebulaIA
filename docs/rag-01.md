# RAG-01: documentos academicos trazables

## Alcance

RAG-01 separa documentos academicos comunes de `student` y del historial personal. La migracion crea un esquema privado `rag`; clientes y modelos solo pueden usar `public.nebula_search_academic_chunks`. No incluye documentos, contenido, perfiles de embeddings ni vectores reales.

Se reutilizan las convenciones locales de `academic.sources` y `academic.evidence`: URL HTTPS, tipo `official`/`third_party`, fecha de consulta y estado de validacion. No se reutilizan esas tablas directamente porque un documento RAG necesita revisiones por hash, fragmentos y multiples embeddings por perfil.

## Modelo

- `rag.documents`: titulo, URL, editor, fechas, tipo, estado, alcance, hash SHA-256 y metadatos.
- `rag.document_chunks`: fragmento, localizador trazable, indice, hash, conteo opcional de tokens y metadatos.
- `rag.embedding_profiles`: proveedor, modelo, dimension, metrica y estado. La migracion no inserta ninguno.
- `rag.chunk_embeddings`: relacion fragmento/perfil y vector. La dimension del vector debe coincidir con la dimension declarada por el perfil.

Solo documentos con `validation_status = 'documented'` participan en busqueda. Resultados incluyen URL, titulo, fecha consultada y localizador para construir citas.

## Dimension y pgvector

La instalacion remota fue verificada manualmente el 25 de noviembre de 2026: extension `vector` 0.8.2 en el esquema `extensions`, propiedad de `supabase_admin`. La migracion vuelve a comprobar localizacion y presencia antes de crear objetos. El modelo y la dimension siguen pendientes.

No se eligio una dimension arbitraria. `extensions.vector` se almacena sin dimension fija y cada perfil declara su dimension; una restriccion con `vector_dims` impide mezclar dimensiones. Como la metrica admitida es coseno, tambien se rechazan embeddings de norma cero tanto al almacenar como al consultar. Cuando se seleccione el modelo se debe:

1. consultar la dimension publicada por el proveedor;
2. confirmar limites, privacidad, costo y politica de retencion;
3. insertar un perfil inicialmente `inactive`;
4. generar un vector de prueba y verificar `vector_dims`;
5. activar un unico perfil;
6. crear una migracion posterior con indice HNSW o IVFFlat tipado a esa dimension, por ejemplo mediante un cast `embedding::vector(D)`, donde `D` sea la dimension ya comprobada.

RAG-01 usa busqueda exacta sin indice vectorial. Es adecuada para validacion estructural y un corpus pequeno, no para produccion a escala.

## Plan de indexacion sin llamadas a Gemini

1. Inventariar documentos reales sin descargarlos automaticamente.
2. Validar manualmente URL, editor, licencia, version, fecha y alcance.
3. Calcular SHA-256 localmente y cargar la revision de forma idempotente por `(source_url, content_sha256)`.
4. Extraer texto localmente; conservar pagina, seccion o parrafo en `locator`.
5. Fragmentar de forma determinista y probar hashes, orden y reconstruccion sin embeddings.
6. Elegir el modelo y registrar el perfil despues de verificar su dimension.
7. Generar embeddings en un entorno controlado, nunca desde pruebas estructurales.
8. Comparar recuperacion con un conjunto de preguntas y fuentes esperadas.
9. Crear el indice vectorial dimensionado y medir recall/latencia.
10. Conectar n8n mediante una herramienta HTTP/MCP que reciba consulta y devuelva fragmentos con citas; las credenciales permanecen fuera del prompt y del modelo.

## Seguridad

- RLS habilitado y sin politicas cliente en las cuatro tablas.
- Sin permisos directos sobre `rag` para `PUBLIC`, `anon` o `authenticated`.
- RPC `SECURITY DEFINER`, `search_path` vacio y referencias calificadas.
- La RPC acepta embeddings, perfil, limite y umbral; no acepta `user_id`.
- No existe referencia a `student`, Auth, memoria o conversaciones.
- Antes de desplegar se debe confirmar que el propietario de la funcion sea un rol administrativo no controlable por clientes.
- La migracion aborta si el propietario efectivo de la funcion es `anon`, `authenticated` o `service_role`; aun asi debe registrarse el propietario observado tras aplicar.

## Pendientes obligatorios

- Proveedor, modelo y dimension de embeddings.
- Politicas del proveedor sobre datos y retencion.
- Documentos concretos, licencia, autoridad y vigencia.
- Estrategia de parsing, chunking, solapamiento y limites de tokens.
- Umbral de similitud evaluado con datos reales.
- Dimension y parametros del indice vectorial.
- Rol administrativo de ingestion y procedimiento de rotacion/reindexacion.

## Comandos para revision posterior (no ejecutados)

Pruebas locales:

```powershell
python -m pytest -v tests/test_rag01_migration.py
```

Comprobar la instalacion en un proyecto Supabase de pruebas:

```powershell
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -c "select e.extversion, n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='vector';"
```

Aplicar solo despues de revisar el resultado anterior y seleccionar un proyecto aislado:

```powershell
psql $env:TEST_DATABASE_URL -v ON_ERROR_STOP=1 -f .\supabase\migrations\20261124060000_rag_academic_documents.sql
```

No use una URL de produccion para la primera aplicacion.

## Validacion PostgreSQL desechable

La prueba de integracion crea un contenedor exclusivo con
`pgvector/pgvector:0.8.2-pg15`, aplica la migracion dos veces y lo elimina al
terminar. No usa Compose, volumen persistente ni credenciales del proyecto.
Debe habilitarse expresamente:

```powershell
$env:NEBULA_RAG_DOCKER_TEST = '1'
python -m pytest -v tests/test_rag01_postgres_integration.py
Remove-Item Env:NEBULA_RAG_DOCKER_TEST
```

PostgreSQL 15 es la version fijada para esta validacion local. La version
principal del proyecto Supabase aun debe comprobarse; esta prueba tampoco
reproduce PostgREST, el gateway de Supabase ni sus roles administrados.
