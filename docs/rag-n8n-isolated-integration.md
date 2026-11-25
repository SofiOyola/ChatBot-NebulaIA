# Integración aislada n8n → API RAG

Esta guía prepara una prueba técnica local. No modifica el workflow principal,
no activa el perfil real, no ingiere documentos y no invoca Gemini.

## Topología mínima

- PostgreSQL y PostgREST RAG: entorno `nebula-rag-local-it`, ligado a loopback.
- API RAG de prueba: proceso Python ligado a `127.0.0.1:58091`, proveedor
  `deterministic-test-only` y perfil sintético local de tres dimensiones.
- n8n aislado: `infrastructure/n8n/compose.yaml`, publicado únicamente en
  `127.0.0.1:5679`.
- Desde el contenedor n8n, la API se referencia como
  `http://host.docker.internal:58091/v1/rag/search`.

Docker Desktop enruta `host.docker.internal` al host. Esto permite reutilizar
el servidor ligado al loopback sin publicar la API en Internet ni crear otra
red. La ruta debe probarse de nuevo en cada host; no es el destino de n8n Cloud.

## Contrato del nodo HTTP

Configurar en una **copia inactiva** del workflow:

- método: `POST`;
- URL local: `http://host.docker.internal:58091/v1/rag/search`;
- autenticación: credencial **Header Auth** de n8n;
- nombre del header: `X-Nebula-Tool-Key`;
- valor: secreto local independiente, nunca incluido en el prompt o JSON;
- `Content-Type`: `application/json`;
- cuerpo:

```json
{
  "query": "texto de consulta",
  "limit": 5,
  "threshold": 0.2,
  "curriculum_scope": "old_9s_151c"
}
```

`query` admite 1–2000 caracteres; `limit`, 1–20; `threshold`, 0–1; y
`curriculum_scope`, únicamente `old_9s_151c` o `general`. La respuesta exitosa
contiene `success`, `result_count`, `sources` y `context`. Cada fuente incluye
título, URL, localizador, similitud, metadatos, flags de seguridad y contenido
limitado. Un `200` con cero resultados es válido y no autoriza al agente a
inventar una respuesta.

## Copia aislada del workflow

1. Inspeccionar el workflow principal por una operación de lectura de MCP n8n.
2. Duplicarlo con otro identificador y nombre, mantenerlo inactivo y verificar
   que ninguna operación actualice el identificador original.
3. Conservar Gemini, memoria, Auth, MCP curricular y herramientas personales sin
   cambios, pero no ejecutar el agente durante las pruebas de conectividad.
4. Añadir primero un nodo HTTP normal o un workflow auxiliar manual que llame a
   la API. Validar `401`, `400`, `200` vacío y `503` sin AI Agent.
5. Solo después añadir el mismo contrato como herramienta HTTP del agente. La
   evidencia de uso de la herramienta y la calidad académica quedan pendientes
   hasta autorizar una ejecución real.

La conexión MCP disponible debe usarse para listar/leer y crear la copia, si el
servidor expone esas operaciones. No debe importarse ni ejecutarse el respaldo
privado de `infrastructure/n8n/backups`. Antes de cualquier escritura, registrar
el ID principal y comprobar que el destino de la creación es un ID nuevo.

## Estados seguros esperados

| Condición | HTTP | JSON mínimo |
|---|---:|---|
| Falta clave o es incorrecta | 401 | `success:false`, `error:"unauthorized"` |
| Contrato inválido | 400 | `success:false`, `error:"invalid_search_request"` |
| Perfil activo y sin coincidencias | 200 | `success:true`, `result_count:0` |
| Perfil inactivo/inexistente | 503 | `success:false`, `error:"rag_unavailable"` |
| PostgreSQL/proveedor no disponible | 503 | `success:false`, `error:"rag_unavailable"` |

El `503` es deliberadamente genérico y no expone cadenas de conexión ni detalles
internos. Con la implementación actual, el embedding de consulta se calcula
antes de que la RPC valide el perfil. Por ello, **no se debe apuntar la copia al
perfil real inactivo usando Gemini**: consumiría una solicitud y terminaría en
`503`. Para conectividad se usa exclusivamente el proveedor determinista local.

## Ejecución local sin Gemini

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Start-RagLocal.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Test-RagHttpLocal.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Stop-RagLocal.ps1
```

El test HTTP inicia y detiene automáticamente la API. Para una prueba manual
desde n8n, se necesita un lanzador equivalente que mantenga el proceso activo y
que solicite o genere la clave solo en memoria; no se debe copiar
`.env.rag-local` a n8n. El servicio sigue siendo de prueba y sus vectores no
tienen significado semántico.

## Límites de la evidencia

Se puede demostrar ahora transporte, autenticación, validación, respuesta vacía,
límites y manejo de dependencia caída. No se puede demostrar recuperación
académica, citas reales ni uso correcto por Gemini hasta contar con al menos un
documento institucional autorizado, embeddings reales revisados, perfil activo
y despliegue HTTPS privado alcanzable desde n8n Cloud.
