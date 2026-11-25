# Comprobación previa del perfil RAG en n8n

La migración 012 incorpora `public.nebula_get_rag_profile_readiness(text)` sin
conceder acceso directo a `rag.embedding_profiles`. El subworkflow debe mantener
`RAG_ENABLED=false` hasta que se autoricen perfil, corpus y pruebas reales.

Primera consulta PostgreSQL del subworkflow:

```sql
SELECT ready,profile_id,dimension
FROM public.nebula_get_rag_profile_readiness($1::text);
```

Único parámetro: `gemini-embedding-001-768`.

El nodo `RAG - Gemini Query Embedding` solo puede recibir la rama positiva si se
cumplen simultáneamente: `RAG_ENABLED === true`, exactamente una fila,
`ready === true`, `profile_id === 'gemini-embedding-001-768'` y
`dimension === 768`. Una fila ausente, una propiedad inesperada, un error SQL o
un fallo de conexión debe terminar antes de Gemini.

Perfil no disponible:

```json
{"success":false,"error":"rag_not_ready","retryable":false,"sources":[],"context":""}
```

Fallo de comprobación:

```json
{"success":false,"error":"rag_readiness_unavailable","retryable":true,"sources":[],"context":""}
```

No se debe usar `result_count: 0`: esa respuesta se reserva para una búsqueda
real ejecutada correctamente sin coincidencias. En la evidencia de n8n, las
ramas negativas deben mostrar los nodos Gemini y búsqueda como `Not executed`.
