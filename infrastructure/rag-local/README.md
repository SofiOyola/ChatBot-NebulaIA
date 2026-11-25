# RAG local con PostgreSQL, pgvector y PostgREST

Entorno mínimo alternativo a Supabase CLI. No usa `supabase link`, `db push` ni
`db reset`; tampoco monta el directorio completo de migraciones. Solo aplica, en
orden, las migraciones RAG 006, 007 y 008, seguidas de fixtures sintéticos.

Servicios y superficies:

- PostgreSQL 15.18 + pgvector 0.8.2: `127.0.0.1:55432`.
- PostgREST 12.2.3: `127.0.0.1:53000`.
- Proyecto Compose: `nebula-rag-local-it`.
- Volumen: `nebula-rag-local-pgdata`.

Las credenciales aleatorias se generan en `.env.rag-local`, ignorado por Git.
No son credenciales de Supabase y no deben copiarse a reportes.
La API usa `nebula_rag_api_login`, miembro del rol `nebula_rag_api`. Este solo
ejecuta las dos RPC de busqueda y no accede directamente al esquema `rag`.

## Iniciar o reiniciar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Start-RagLocal.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Configure-RagApiRole.ps1
```

## Probar PostgreSQL y PostgREST

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Test-RagLocal.ps1
```

## Probar el API HTTP RAG real

El test sincroniza los vectores sintéticos con el mismo proveedor determinista
de tres dimensiones, inicia el API solamente en `127.0.0.1:58091`, prueba sus
contratos y lo termina automáticamente. No invoca Gemini.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Test-RagHttpLocal.ps1
```

El proveedor `deterministic-test-only` requiere simultáneamente
`RAG_ALLOW_TEST_PROVIDER=true` y un host loopback. Sus resultados solo validan
integración técnica; no representan similitud semántica académica.

## Detener sin perder fixtures

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Stop-RagLocal.ps1
```

## Eliminar exclusivamente este entorno

La siguiente operación elimina sus dos contenedores, red y volumen. Requiere
escribir `ELIMINAR RAG LOCAL` y nunca selecciona recursos ajenos.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\infrastructure\rag-local\Remove-RagLocal.ps1
```

Este entorno prueba PostgreSQL y PostgREST, pero no reproduce GoTrue, Kong,
Realtime, Storage, Studio ni todos los defaults administrados de Supabase.
